import { NextRequest, NextResponse } from 'next/server';
import { DateTime } from 'luxon';
import { z } from 'zod';
import { db } from '@/lib/db';
import { updateCalendarEvent } from '@/lib/google';
import { sendReschedule } from '@/lib/mail';
import { smsReschedule } from '@/lib/sms';
import { isSlotAvailable } from '@/lib/slots';

const bodySchema = z.object({
  start: z.string().min(1),
  timezone: z.string().min(1).max(64).optional(),
});

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ token: string }> }
) {
  const { token } = await params;
  const parsed = bodySchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ error: 'Requête invalide.' }, { status: 400 });
  }

  const booking = await db.booking.findUnique({
    where: { manageToken: token },
    include: { eventType: { include: { user: true } } },
  });
  if (!booking || booking.status === 'CANCELLED') {
    return NextResponse.json({ error: 'Rendez-vous introuvable.' }, { status: 404 });
  }

  const start = DateTime.fromISO(parsed.data.start, { zone: 'utc' });
  if (!start.isValid) {
    return NextResponse.json({ error: 'Créneau invalide.' }, { status: 400 });
  }
  const eventTypeWithUser = { ...booking.eventType, user: booking.eventType.user };
  if (!(await isSlotAvailable(eventTypeWithUser, start.toISO()!, booking.id))) {
    return NextResponse.json(
      { error: 'Ce créneau vient d’être réservé. Merci d’en choisir un autre.' },
      { status: 409 }
    );
  }

  const end = start.plus({ minutes: booking.eventType.durationMin });
  const updated = await db.booking.update({
    where: { id: booking.id },
    data: {
      startUtc: start.toJSDate(),
      endUtc: end.toJSDate(),
      inviteeTimezone: parsed.data.timezone ?? booking.inviteeTimezone,
      remindersSent: '[]', // les rappels repartent pour le nouveau créneau
    },
  });

  await updateCalendarEvent(
    booking.eventType.user,
    booking.googleEventId,
    start.toISO()!,
    end.toISO()!
  );
  const bundle = { booking: updated, eventType: booking.eventType, host: booking.eventType.user };
  await sendReschedule(bundle);
  await smsReschedule(bundle);

  return NextResponse.json({ ok: true });
}
