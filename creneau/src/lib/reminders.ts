import { db } from './db';
import { sendReminder } from './mail';
import { parseJsonArray } from './utils';

let started = false;

/** Boucle de rappels : chaque minute, envoie les rappels arrivés à échéance.
 *  Démarrée une seule fois au boot du serveur (instrumentation.ts). */
export function startReminderLoop(): void {
  if (started) return;
  started = true;
  console.log('Créneau : boucle de rappels démarrée.');
  setInterval(() => {
    tick().catch((error) => console.error('Boucle de rappels en erreur:', error));
  }, 60_000);
}

async function tick(): Promise<void> {
  const now = Date.now();
  const bookings = await db.booking.findMany({
    where: { status: 'CONFIRMED', startUtc: { gte: new Date(now) } },
    include: { eventType: { include: { user: true } } },
  });

  for (const booking of bookings) {
    const offsets = parseJsonArray(booking.eventType.reminders);
    const sent = parseJsonArray(booking.remindersSent);
    const minutesUntilStart = (booking.startUtc.getTime() - now) / 60_000;

    for (const offset of offsets) {
      if (minutesUntilStart <= offset && !sent.includes(offset)) {
        sent.push(offset);
        await db.booking.update({
          where: { id: booking.id },
          data: { remindersSent: JSON.stringify(sent) },
        });
        await sendReminder({
          booking,
          eventType: booking.eventType,
          host: booking.eventType.user,
        });
      }
    }
  }
}
