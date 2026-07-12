import nodemailer from 'nodemailer';
import type { Booking, EventType, User } from '@prisma/client';
import { buildIcs } from './ics';
import { baseUrl, formatDateTimeFr } from './utils';

function smtpConfigured(): boolean {
  return Boolean(process.env.SMTP_HOST);
}

function transporter() {
  return nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port: Number(process.env.SMTP_PORT || 587),
    secure: Number(process.env.SMTP_PORT) === 465,
    auth: process.env.SMTP_USER
      ? { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS }
      : undefined,
  });
}

type Mail = {
  to: string;
  subject: string;
  text: string;
  ics?: { content: string; method: string };
};

async function send(mail: Mail): Promise<void> {
  if (!smtpConfigured()) {
    console.log(`[mail non envoyé — SMTP non configuré] À: ${mail.to} | ${mail.subject}\n${mail.text}`);
    return;
  }
  try {
    await transporter().sendMail({
      from: process.env.SMTP_FROM || process.env.SMTP_USER,
      to: mail.to,
      subject: mail.subject,
      text: mail.text,
      ...(mail.ics
        ? {
            icalEvent: {
              method: mail.ics.method,
              content: mail.ics.content,
            },
          }
        : {}),
    });
  } catch (error) {
    console.error(`Envoi email en échec (${mail.subject} → ${mail.to}):`, error);
  }
}

type BookingBundle = {
  booking: Booking;
  eventType: EventType;
  host: User;
};

export function locationText(bundle: BookingBundle): string {
  const { booking, eventType, host } = bundle;
  switch (eventType.locationType) {
    case 'MEET':
      return booking.meetLink || host.videoLink || 'Lien visio communiqué par email';
    case 'PHONE':
      return 'Par téléphone';
    case 'ADDRESS':
      return eventType.locationDetail;
    default:
      return eventType.locationDetail;
  }
}

function bookingIcs(bundle: BookingBundle, method: 'REQUEST' | 'CANCEL', sequence = 0) {
  const { booking, eventType, host } = bundle;
  return buildIcs({
    uid: booking.id,
    start: booking.startUtc,
    end: booking.endUtc,
    summary: `${eventType.name} — ${booking.inviteeName} / ${host.name}`,
    description: `Rendez-vous réservé via ${baseUrl()}\nGérer : ${manageUrl(booking)}`,
    location: locationText(bundle),
    organizerName: host.name,
    organizerEmail: host.email,
    attendeeName: booking.inviteeName,
    attendeeEmail: booking.inviteeEmail,
    method,
    sequence,
  });
}

export function manageUrl(booking: Booking): string {
  return `${baseUrl()}/rdv/${booking.manageToken}`;
}

export async function sendConfirmation(bundle: BookingBundle): Promise<void> {
  const { booking, eventType, host } = bundle;
  const when = formatDateTimeFr(booking.startUtc, booking.inviteeTimezone);
  const ics = bookingIcs(bundle, 'REQUEST');

  await send({
    to: booking.inviteeEmail,
    subject: `Confirmé : ${eventType.name} avec ${host.name} — ${when}`,
    text: [
      `Bonjour ${booking.inviteeName},`,
      '',
      `Votre rendez-vous « ${eventType.name} » avec ${host.name} est confirmé.`,
      '',
      `📅 ${when} (${booking.inviteeTimezone})`,
      `📍 ${locationText(bundle)}`,
      '',
      `Pour annuler ou reprogrammer : ${manageUrl(booking)}`,
      '',
      'À bientôt !',
    ].join('\n'),
    ics: { content: ics, method: 'REQUEST' },
  });

  await send({
    to: host.email,
    subject: `Nouveau RDV : ${eventType.name} avec ${booking.inviteeName} — ${formatDateTimeFr(booking.startUtc, host.timezone)}`,
    text: [
      `${booking.inviteeName} (${booking.inviteeEmail}) a réservé « ${eventType.name} ».`,
      '',
      `📅 ${formatDateTimeFr(booking.startUtc, host.timezone)} (${host.timezone})`,
      `📍 ${locationText(bundle)}`,
      '',
      `Réponses au formulaire : ${booking.answers}`,
    ].join('\n'),
    ics: { content: ics, method: 'REQUEST' },
  });
}

export async function sendCancellation(bundle: BookingBundle, cancelledBy: string): Promise<void> {
  const { booking, eventType, host } = bundle;
  const when = formatDateTimeFr(booking.startUtc, booking.inviteeTimezone);
  const ics = bookingIcs(bundle, 'CANCEL', 1);

  const text = [
    `Le rendez-vous « ${eventType.name} » du ${when} a été annulé${cancelledBy ? ` par ${cancelledBy}` : ''}.`,
    '',
    `Pour reprendre un créneau : ${baseUrl()}/${host.slug}/${eventType.slug}`,
  ].join('\n');

  await send({
    to: booking.inviteeEmail,
    subject: `Annulé : ${eventType.name} — ${when}`,
    text,
    ics: { content: ics, method: 'CANCEL' },
  });
  await send({
    to: host.email,
    subject: `Annulé : ${eventType.name} avec ${booking.inviteeName}`,
    text,
    ics: { content: ics, method: 'CANCEL' },
  });
}

export async function sendReschedule(bundle: BookingBundle): Promise<void> {
  const { booking, eventType, host } = bundle;
  const when = formatDateTimeFr(booking.startUtc, booking.inviteeTimezone);
  const ics = bookingIcs(bundle, 'REQUEST', 1);

  await send({
    to: booking.inviteeEmail,
    subject: `Reprogrammé : ${eventType.name} avec ${host.name} — ${when}`,
    text: [
      `Votre rendez-vous « ${eventType.name} » a été déplacé.`,
      '',
      `📅 Nouveau créneau : ${when} (${booking.inviteeTimezone})`,
      `📍 ${locationText(bundle)}`,
      '',
      `Pour annuler ou reprogrammer : ${manageUrl(booking)}`,
    ].join('\n'),
    ics: { content: ics, method: 'REQUEST' },
  });
  await send({
    to: host.email,
    subject: `Reprogrammé : ${eventType.name} avec ${booking.inviteeName} — ${formatDateTimeFr(booking.startUtc, host.timezone)}`,
    text: `Nouveau créneau : ${formatDateTimeFr(booking.startUtc, host.timezone)} (${host.timezone})`,
    ics: { content: ics, method: 'REQUEST' },
  });
}

export async function sendReminder(bundle: BookingBundle): Promise<void> {
  const { booking, eventType, host } = bundle;
  const when = formatDateTimeFr(booking.startUtc, booking.inviteeTimezone);

  await send({
    to: booking.inviteeEmail,
    subject: `Rappel : ${eventType.name} avec ${host.name} — ${when}`,
    text: [
      `Bonjour ${booking.inviteeName},`,
      '',
      `Petit rappel de votre rendez-vous « ${eventType.name} » avec ${host.name}.`,
      '',
      `📅 ${when} (${booking.inviteeTimezone})`,
      `📍 ${locationText(bundle)}`,
      '',
      `Pour annuler ou reprogrammer : ${manageUrl(booking)}`,
    ].join('\n'),
  });
}
