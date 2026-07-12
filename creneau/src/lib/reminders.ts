import { db } from './db';
import { reminderHeartbeat } from './health';
import { manageUrl, sendReminder } from './mail';
import { smsReminder } from './sms';
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
  reminderHeartbeat();
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
        const bundle = {
          booking,
          eventType: booking.eventType,
          host: booking.eventType.user,
        };
        await sendReminder(bundle);
        await smsReminder(bundle, manageUrl(booking));
      }
    }
  }
}
