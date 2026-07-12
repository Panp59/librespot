import { DateTime, Interval } from 'luxon';
import { db } from './db';
import { getBusyIntervals } from './google';

type EventTypeWithUser = NonNullable<
  Awaited<ReturnType<typeof loadEventType>>
>;

export async function loadEventType(hostSlug: string, eventSlug: string) {
  const user = await db.user.findUnique({ where: { slug: hostSlug } });
  if (!user) return null;
  const eventType = await db.eventType.findFirst({
    where: { userId: user.id, slug: eventSlug, active: true },
  });
  if (!eventType) return null;
  return { ...eventType, user };
}

/**
 * Créneaux disponibles (instants ISO UTC) pour un type de RDV entre deux
 * dates : disponibilités hebdomadaires de l'hôte, moins les réservations
 * existantes (avec tampons), moins les occupations Google Calendar,
 * en respectant préavis minimal et horizon maximal.
 */
export async function computeSlots(
  eventType: EventTypeWithUser,
  fromIso: string,
  toIso: string,
  excludeBookingId?: string
): Promise<string[]> {
  const zone = eventType.user.timezone || 'Europe/Paris';
  const now = DateTime.utc();
  const earliest = now.plus({ minutes: eventType.minNoticeMin });
  const latest = now.plus({ days: eventType.maxDaysAhead });

  let from = DateTime.fromISO(fromIso, { zone: 'utc' });
  let to = DateTime.fromISO(toIso, { zone: 'utc' });
  if (!from.isValid || !to.isValid) return [];
  if (from < earliest) from = earliest;
  if (to > latest) to = latest;
  if (from >= to) return [];

  const availability = await db.availability.findMany({
    where: { userId: eventType.userId },
  });
  if (availability.length === 0) return [];

  // Occupé = réservations confirmées de l'hôte (tous types de RDV)…
  const bookings = await db.booking.findMany({
    where: {
      userId: eventType.userId,
      status: 'CONFIRMED',
      endUtc: { gte: from.toJSDate() },
      startUtc: { lte: to.toJSDate() },
      // Lors d'une reprogrammation, le RDV déplacé ne se bloque pas lui-même.
      ...(excludeBookingId ? { id: { not: excludeBookingId } } : {}),
    },
    select: { startUtc: true, endUtc: true },
  });
  // Les RDV existants réservent aussi leurs tampons : un RDV avec 10 min de
  // tampon « après » bloque le créneau qui suivrait immédiatement.
  let busy: Interval[] = bookings.map((b) =>
    Interval.fromDateTimes(
      DateTime.fromJSDate(b.startUtc, { zone: 'utc' }).minus({
        minutes: eventType.bufferBeforeMin,
      }),
      DateTime.fromJSDate(b.endUtc, { zone: 'utc' }).plus({
        minutes: eventType.bufferAfterMin,
      })
    )
  );

  // … plus les événements Google Calendar si le compte est connecté.
  const googleBusy = await getBusyIntervals(eventType.user, from, to);
  busy = busy.concat(googleBusy);

  const duration = eventType.durationMin;
  const slotStep = duration >= 30 ? 30 : 15;
  const slots: string[] = [];

  // Parcours jour par jour dans le fuseau de l'hôte.
  let day = from.setZone(zone).startOf('day');
  const lastDay = to.setZone(zone).endOf('day');

  while (day <= lastDay) {
    const windows = availability.filter((a) => a.weekday === day.weekday);
    for (const window of windows) {
      const windowStart = day.plus({ minutes: window.startMinute });
      const windowEnd = day.plus({ minutes: window.endMinute });

      let cursor = windowStart;
      while (cursor.plus({ minutes: duration }) <= windowEnd) {
        const slotStart = cursor.toUTC();
        const slotEnd = slotStart.plus({ minutes: duration });

        const withinRange = slotStart >= from && slotStart <= to;
        if (withinRange) {
          // Le créneau élargi des tampons ne doit croiser aucune occupation.
          const padded = Interval.fromDateTimes(
            slotStart.minus({ minutes: eventType.bufferBeforeMin }),
            slotEnd.plus({ minutes: eventType.bufferAfterMin })
          );
          const conflict = busy.some((b) => b.overlaps(padded));
          if (!conflict) slots.push(slotStart.toISO()!);
        }
        cursor = cursor.plus({ minutes: slotStep });
      }
    }
    day = day.plus({ days: 1 });
  }

  return slots.sort();
}

/** Vérifie qu'un créneau précis est (encore) disponible. */
export async function isSlotAvailable(
  eventType: EventTypeWithUser,
  startIsoUtc: string,
  excludeBookingId?: string
): Promise<boolean> {
  const start = DateTime.fromISO(startIsoUtc, { zone: 'utc' });
  if (!start.isValid) return false;
  const slots = await computeSlots(
    eventType,
    start.minus({ hours: 1 }).toISO()!,
    start.plus({ hours: 1 }).toISO()!,
    excludeBookingId
  );
  return slots.includes(start.toISO()!);
}
