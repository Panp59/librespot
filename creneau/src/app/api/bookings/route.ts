import { randomBytes } from 'crypto';
import { NextRequest, NextResponse } from 'next/server';
import { DateTime } from 'luxon';
import { z } from 'zod';
import { db } from '@/lib/db';
import { createCalendarEvent } from '@/lib/google';
import { sendConfirmation } from '@/lib/mail';
import { isSlotAvailable } from '@/lib/slots';
import { baseUrl, formatDateTimeFr, parseQuestions } from '@/lib/utils';

const bodySchema = z.object({
  eventTypeId: z.string().min(1),
  start: z.string().min(1),
  name: z.string().trim().min(1).max(200),
  email: z.string().trim().email(),
  timezone: z.string().min(1).max(64),
  answers: z.record(z.string(), z.string().max(4000)).default({}),
});

export async function POST(request: NextRequest) {
  const parsed = bodySchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ error: 'Formulaire invalide.' }, { status: 400 });
  }
  const body = parsed.data;

  const eventType = await db.eventType.findFirst({
    where: { id: body.eventTypeId, active: true },
    include: { user: true },
  });
  if (!eventType) {
    return NextResponse.json({ error: 'Type de rendez-vous introuvable.' }, { status: 404 });
  }

  // Questions obligatoires renseignées ?
  for (const question of parseQuestions(eventType.questions)) {
    if (question.required && !(body.answers[question.id] ?? '').trim()) {
      return NextResponse.json(
        { error: `Merci de répondre à « ${question.label} ».` },
        { status: 400 }
      );
    }
  }

  const start = DateTime.fromISO(body.start, { zone: 'utc' });
  if (!start.isValid) {
    return NextResponse.json({ error: 'Créneau invalide.' }, { status: 400 });
  }
  if (!(await isSlotAvailable(eventType, start.toISO()!))) {
    return NextResponse.json(
      { error: 'Ce créneau vient d’être réservé. Merci d’en choisir un autre.' },
      { status: 409 }
    );
  }

  const end = start.plus({ minutes: eventType.durationMin });
  const booking = await db.booking.create({
    data: {
      eventTypeId: eventType.id,
      userId: eventType.userId,
      startUtc: start.toJSDate(),
      endUtc: end.toJSDate(),
      inviteeName: body.name,
      inviteeEmail: body.email,
      inviteeTimezone: body.timezone,
      answers: JSON.stringify(body.answers),
      manageToken: randomBytes(24).toString('hex'),
    },
  });

  // Événement Google Calendar (+ lien Meet si visio) — non bloquant.
  const questions = parseQuestions(eventType.questions);
  const answersText = questions
    .map((q) => `${q.label} : ${body.answers[q.id] ?? '—'}`)
    .join('\n');
  const google = await createCalendarEvent(eventType.user, {
    id: booking.id,
    summary: `${eventType.name} — ${body.name}`,
    description: `${answersText}\n\nRéservé via ${baseUrl()}\n${formatDateTimeFr(booking.startUtc, eventType.user.timezone)}`,
    startIsoUtc: start.toISO()!,
    endIsoUtc: end.toISO()!,
    inviteeEmail: body.email,
    inviteeName: body.name,
    withMeet: eventType.locationType === 'MEET',
  });

  let finalBooking = booking;
  if (google) {
    finalBooking = await db.booking.update({
      where: { id: booking.id },
      data: { googleEventId: google.eventId, meetLink: google.meetLink },
    });
  }

  await sendConfirmation({
    booking: finalBooking,
    eventType,
    host: eventType.user,
  });

  return NextResponse.json({ token: booking.manageToken });
}
