import { DateTime } from 'luxon';
import { db } from './db';
import { checkGoogleAccess, googleConfigured } from './google';
import { sendAlertEmail, smtpConfigured, verifySmtp } from './mail';
import { sendSms, smsConfigured } from './sms';
import { computeSlots } from './slots';

/**
 * Surveillance de l'application : « est-ce qu'un prospect peut réserver,
 * là, maintenant ? ». Exposée sur /api/health (pour un moniteur externe
 * type UptimeRobot) et exécutée en interne toutes les 10 minutes avec
 * alerte email/SMS de l'admin en cas de panne.
 */

export type HealthStatus = 'ok' | 'warn' | 'fail';
export type HealthCheck = { name: string; label: string; status: HealthStatus; detail: string };
export type HealthReport = { status: HealthStatus; at: string; checks: HealthCheck[] };

type HealthState = {
  report?: HealthReport;
  // Dernière alerte envoyée par contrôle (epoch ms), pour le cooldown.
  alertedAt: Record<string, number>;
  watchdogStarted?: boolean;
};

function state(): HealthState {
  const g = globalThis as unknown as { __creneauHealth?: HealthState };
  if (!g.__creneauHealth) g.__creneauHealth = { alertedAt: {} };
  return g.__creneauHealth;
}

/** Battement de cœur de la boucle de rappels (mis à jour à chaque tick). */
export function reminderHeartbeat(): void {
  (globalThis as unknown as { __creneauBeat?: number }).__creneauBeat = Date.now();
}

export function lastReport(): HealthReport | undefined {
  return state().report;
}

export async function runHealthChecks(): Promise<HealthReport> {
  const checks: HealthCheck[] = [];

  // 1. Base de données (lecture + écriture).
  try {
    await db.settings.upsert({ where: { id: 'main' }, update: {}, create: { id: 'main' } });
    checks.push({ name: 'database', label: 'Base de données', status: 'ok', detail: 'Lecture/écriture OK.' });
  } catch (error) {
    checks.push({
      name: 'database', label: 'Base de données', status: 'fail',
      detail: `Erreur : ${error instanceof Error ? error.message : String(error)}`,
    });
  }

  // 2. Réservation : le calcul de créneaux fonctionne ET il reste des
  //    créneaux réservables (le vrai risque métier : agenda saturé ou
  //    disponibilités vides = plus aucune démo possible).
  try {
    const eventTypes = await db.eventType.findMany({
      where: { active: true },
      include: { user: true },
    });
    if (eventTypes.length === 0) {
      checks.push({
        name: 'booking', label: 'Réservation', status: 'warn',
        detail: 'Aucun type de rendez-vous actif.',
      });
    } else {
      const from = DateTime.utc().toISO()!;
      const to = DateTime.utc().plus({ days: 14 }).toISO()!;
      const empty: string[] = [];
      let total = 0;
      for (const eventType of eventTypes) {
        const slots = await computeSlots(eventType, from, to);
        total += slots.length;
        if (slots.length === 0) empty.push(eventType.name);
      }
      if (total === 0) {
        checks.push({
          name: 'booking', label: 'Réservation', status: 'fail',
          detail: 'Aucun créneau réservable sur les 14 prochains jours (disponibilités vides ou agenda saturé).',
        });
      } else if (empty.length > 0) {
        checks.push({
          name: 'booking', label: 'Réservation', status: 'warn',
          detail: `Sans créneau sur 14 jours : ${empty.join(', ')}.`,
        });
      } else {
        checks.push({
          name: 'booking', label: 'Réservation', status: 'ok',
          detail: `${total} créneaux ouverts sur les 14 prochains jours.`,
        });
      }
    }
  } catch (error) {
    checks.push({
      name: 'booking', label: 'Réservation', status: 'fail',
      detail: `Le calcul des créneaux échoue : ${error instanceof Error ? error.message : String(error)}`,
    });
  }

  // 3. Emails.
  if (!smtpConfigured()) {
    checks.push({
      name: 'smtp', label: 'Emails', status: 'warn',
      detail: 'SMTP non configuré : les emails sont seulement journalisés.',
    });
  } else {
    try {
      await verifySmtp();
      checks.push({ name: 'smtp', label: 'Emails', status: 'ok', detail: 'Connexion SMTP OK.' });
    } catch (error) {
      checks.push({
        name: 'smtp', label: 'Emails', status: 'fail',
        detail: `SMTP injoignable : ${error instanceof Error ? error.message : String(error)}`,
      });
    }
  }

  // 4. SMS.
  checks.push(
    smsConfigured()
      ? {
          name: 'sms', label: 'SMS', status: 'ok',
          detail: `Fournisseur : ${process.env.SMS_PROVIDER}.`,
        }
      : {
          name: 'sms', label: 'SMS', status: 'warn',
          detail: 'Fournisseur SMS non configuré : les SMS sont seulement journalisés.',
        }
  );

  // 5. Google Calendar (chaque hôte connecté doit avoir un accès valide,
  //    sinon ses créneaux ignorent son agenda → risque de double booking).
  if (!googleConfigured()) {
    checks.push({
      name: 'google', label: 'Google Calendar', status: 'warn',
      detail: 'Identifiants Google non configurés (créneaux internes uniquement).',
    });
  } else {
    const hosts = await db.user.findMany({ where: { googleTokens: { not: '' } } });
    if (hosts.length === 0) {
      checks.push({
        name: 'google', label: 'Google Calendar', status: 'warn',
        detail: 'Aucun hôte n’a connecté son agenda.',
      });
    } else {
      const broken: string[] = [];
      for (const host of hosts) {
        try {
          await checkGoogleAccess(host);
        } catch {
          broken.push(host.name);
        }
      }
      checks.push(
        broken.length === 0
          ? {
              name: 'google', label: 'Google Calendar', status: 'ok',
              detail: `${hosts.length} agenda(s) accessibles.`,
            }
          : {
              name: 'google', label: 'Google Calendar', status: 'fail',
              detail: `Accès agenda en échec pour : ${broken.join(', ')} (reconnexion nécessaire, risque de double réservation).`,
            }
      );
    }
  }

  // 6. Boucle de rappels.
  const beat = (globalThis as unknown as { __creneauBeat?: number }).__creneauBeat;
  if (!beat) {
    checks.push({
      name: 'reminders', label: 'Rappels', status: 'warn',
      detail: 'Boucle de rappels pas encore démarrée.',
    });
  } else if (Date.now() - beat > 5 * 60_000) {
    checks.push({
      name: 'reminders', label: 'Rappels', status: 'fail',
      detail: `Boucle de rappels silencieuse depuis ${Math.round((Date.now() - beat) / 60_000)} min.`,
    });
  } else {
    checks.push({ name: 'reminders', label: 'Rappels', status: 'ok', detail: 'Boucle active.' });
  }

  const worst: HealthStatus = checks.some((c) => c.status === 'fail')
    ? 'fail'
    : checks.some((c) => c.status === 'warn')
      ? 'warn'
      : 'ok';

  const report: HealthReport = { status: worst, at: new Date().toISOString(), checks };
  state().report = report;
  return report;
}

// --- Chien de garde interne : contrôle toutes les 10 min + alertes ---

const ALERT_COOLDOWN_MS = 6 * 3600_000;

async function alertAdmins(subject: string, text: string): Promise<void> {
  const email = process.env.HEALTH_ALERT_EMAIL || process.env.ADMIN_EMAIL;
  if (email) await sendAlertEmail(email, subject, text);
  const phone = process.env.HEALTH_ALERT_PHONE;
  if (phone) await sendSms(phone, `${subject} : ${text.slice(0, 120)}`);
}

async function watchdogTick(): Promise<void> {
  const report = await runHealthChecks();
  const s = state();
  const now = Date.now();

  for (const check of report.checks) {
    const alreadyAlerted = s.alertedAt[check.name];
    if (check.status === 'fail') {
      if (!alreadyAlerted || now - alreadyAlerted > ALERT_COOLDOWN_MS) {
        s.alertedAt[check.name] = now;
        await alertAdmins(
          `⚠️ [Créneau] Panne : ${check.label}`,
          `${check.detail}\n\nContrôle complet : ${process.env.BASE_URL || ''}/api/health`
        );
      }
    } else if (alreadyAlerted && check.status === 'ok') {
      delete s.alertedAt[check.name];
      await alertAdmins(`✅ [Créneau] Rétabli : ${check.label}`, check.detail);
    }
  }
}

export function startHealthWatchdog(): void {
  const s = state();
  if (s.watchdogStarted) return;
  s.watchdogStarted = true;
  console.log('Créneau : surveillance démarrée (contrôle toutes les 10 min).');
  // Premier contrôle une minute après le boot (laisse le temps au seed).
  setTimeout(() => {
    watchdogTick().catch((error) => console.error('Surveillance en erreur:', error));
  }, 60_000);
  setInterval(() => {
    watchdogTick().catch((error) => console.error('Surveillance en erreur:', error));
  }, 10 * 60_000);
}
