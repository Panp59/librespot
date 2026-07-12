import { createHash } from 'crypto';
import type { Booking, EventType, User } from '@prisma/client';
import { DateTime } from 'luxon';

/**
 * Envoi de SMS transactionnels (confirmations, rappels).
 * Fournisseurs supportés via SMS_PROVIDER :
 *  - "brevo" : BREVO_API_KEY + SMS_SENDER
 *  - "ovh"   : OVH_APP_KEY + OVH_APP_SECRET + OVH_CONSUMER_KEY +
 *              OVH_SERVICE_NAME (+ SMS_SENDER)
 * Sans configuration, les SMS sont simplement journalisés.
 */

export function smsConfigured(): boolean {
  const provider = (process.env.SMS_PROVIDER || '').toLowerCase();
  if (provider === 'brevo') return Boolean(process.env.BREVO_API_KEY);
  if (provider === 'ovh') {
    return Boolean(
      process.env.OVH_APP_KEY &&
        process.env.OVH_APP_SECRET &&
        process.env.OVH_CONSUMER_KEY &&
        process.env.OVH_SERVICE_NAME
    );
  }
  return false;
}

/** 06 12 34 56 78 → +33612345678 ; conserve les numéros internationaux. */
export function normalizePhone(raw: string): string | null {
  const cleaned = raw.replace(/[\s.\-()]/g, '');
  if (/^\+[1-9]\d{6,14}$/.test(cleaned)) return cleaned;
  if (/^00[1-9]\d{6,14}$/.test(cleaned)) return `+${cleaned.slice(2)}`;
  if (/^0[67]\d{8}$/.test(cleaned)) return `+33${cleaned.slice(1)}`;
  if (/^0[1-9]\d{8}$/.test(cleaned)) return `+33${cleaned.slice(1)}`;
  return null;
}

export async function sendSms(to: string, message: string): Promise<void> {
  const phone = normalizePhone(to);
  if (!phone) {
    console.warn(`SMS non envoyé, numéro invalide : ${to}`);
    return;
  }
  if (!smsConfigured()) {
    console.log(`[SMS non envoyé — fournisseur non configuré] À: ${phone} | ${message}`);
    return;
  }
  const provider = (process.env.SMS_PROVIDER || '').toLowerCase();
  try {
    if (provider === 'brevo') {
      await sendViaBrevo(phone, message);
    } else if (provider === 'ovh') {
      await sendViaOvh(phone, message);
    }
  } catch (error) {
    console.error(`Envoi SMS en échec (${phone}):`, error);
  }
}

async function sendViaBrevo(phone: string, message: string): Promise<void> {
  const response = await fetch('https://api.brevo.com/v3/transactionalSMS/sms', {
    method: 'POST',
    headers: {
      'api-key': process.env.BREVO_API_KEY!,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      sender: (process.env.SMS_SENDER || 'Creneau').slice(0, 11),
      recipient: phone,
      content: message,
      type: 'transactional',
    }),
  });
  if (!response.ok) {
    throw new Error(`Brevo ${response.status}: ${await response.text()}`);
  }
}

async function sendViaOvh(phone: string, message: string): Promise<void> {
  const serviceName = process.env.OVH_SERVICE_NAME!;
  const url = `https://eu.api.ovh.com/1.0/sms/${serviceName}/jobs`;
  const body = JSON.stringify({
    message,
    receivers: [phone],
    sender: (process.env.SMS_SENDER || 'Creneau').slice(0, 11),
    // SMS transactionnel : pas de mention « STOP » publicitaire.
    noStopClause: true,
    priority: 'high',
  });
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const toSign = [
    process.env.OVH_APP_SECRET,
    process.env.OVH_CONSUMER_KEY,
    'POST',
    url,
    body,
    timestamp,
  ].join('+');
  const signature = '$1$' + createHash('sha1').update(toSign).digest('hex');

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Ovh-Application': process.env.OVH_APP_KEY!,
      'X-Ovh-Consumer': process.env.OVH_CONSUMER_KEY!,
      'X-Ovh-Timestamp': timestamp,
      'X-Ovh-Signature': signature,
    },
    body,
  });
  if (!response.ok) {
    throw new Error(`OVH ${response.status}: ${await response.text()}`);
  }
}

// --- Messages liés aux rendez-vous (courts, format SMS) ---

type BookingBundle = { booking: Booking; eventType: EventType; host: User };

function shortDate(bundle: BookingBundle): string {
  return DateTime.fromJSDate(bundle.booking.startUtc, { zone: 'utc' })
    .setZone(bundle.booking.inviteeTimezone)
    .setLocale('fr')
    .toFormat("ccc d LLL 'à' HH:mm");
}

export async function smsConfirmation(bundle: BookingBundle, manageUrl: string): Promise<void> {
  if (!bundle.booking.inviteePhone) return;
  await sendSms(
    bundle.booking.inviteePhone,
    `RDV confirmé : ${bundle.eventType.name} avec ${bundle.host.name}, ${shortDate(bundle)}. Gérer : ${manageUrl}`
  );
}

export async function smsReminder(bundle: BookingBundle, manageUrl: string): Promise<void> {
  if (!bundle.booking.inviteePhone) return;
  const link = bundle.booking.meetLink || bundle.host.videoLink;
  await sendSms(
    bundle.booking.inviteePhone,
    `Rappel : ${bundle.eventType.name} avec ${bundle.host.name}, ${shortDate(bundle)}.` +
      (link ? ` Visio : ${link}` : '') +
      ` Gérer : ${manageUrl}`
  );
}

export async function smsReschedule(bundle: BookingBundle): Promise<void> {
  if (!bundle.booking.inviteePhone) return;
  await sendSms(
    bundle.booking.inviteePhone,
    `RDV déplacé : ${bundle.eventType.name} avec ${bundle.host.name}, nouveau créneau ${shortDate(bundle)}.`
  );
}

export async function smsCancellation(bundle: BookingBundle): Promise<void> {
  if (!bundle.booking.inviteePhone) return;
  await sendSms(
    bundle.booking.inviteePhone,
    `RDV annulé : ${bundle.eventType.name} avec ${bundle.host.name} du ${shortDate(bundle)}.`
  );
}
