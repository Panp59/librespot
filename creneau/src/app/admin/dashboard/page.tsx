import { redirect } from 'next/navigation';
import { getSessionUser } from '@/lib/auth';
import { db } from '@/lib/db';
import { lastReport, runHealthChecks, type HealthReport } from '@/lib/health';
import { formatDateTimeFr, parseQuestions } from '@/lib/utils';
import AdminNav from '../AdminNav';
import BookingRow from './BookingRow';

export const dynamic = 'force-dynamic';

const STATUS_BADGE: Record<string, string> = {
  ok: 'bg-green-500/15 text-green-300',
  warn: 'bg-amber-500/15 text-amber-300',
  fail: 'bg-red-500/15 text-red-300',
};
const STATUS_LABEL: Record<string, string> = {
  ok: 'Opérationnel',
  warn: 'À surveiller',
  fail: 'PANNE',
};

function HealthCard({ report }: { report: HealthReport }) {
  return (
    <section className="card mb-6 p-5">
      <div className="mb-3 flex items-center gap-3">
        <h2 className="font-semibold">État du système</h2>
        <span className={`rounded-full px-2.5 py-0.5 text-xs font-semibold ${STATUS_BADGE[report.status]}`}>
          {STATUS_LABEL[report.status]}
        </span>
        <span className="ml-auto text-xs text-slate-400">
          Contrôlé {formatDateTimeFr(new Date(report.at), 'Europe/Paris')} · toutes les 10 min ·{' '}
          <a href="/api/health" className="underline" target="_blank" rel="noreferrer">/api/health</a>
        </span>
      </div>
      <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
        {report.checks.map((check) => (
          <div key={check.name} className="rounded-xl bg-white/5 p-3">
            <p className="flex items-center gap-2 text-sm font-medium">
              <span className={`h-2 w-2 rounded-full ${
                check.status === 'ok' ? 'bg-green-500' : check.status === 'warn' ? 'bg-amber-500' : 'bg-red-500'
              }`} />
              {check.label}
            </p>
            <p className="mt-1 text-xs leading-relaxed text-slate-400">{check.detail}</p>
          </div>
        ))}
      </div>
    </section>
  );
}

export default async function DashboardPage() {
  const user = await getSessionUser();
  if (!user) redirect('/admin');

  const bookings = await db.booking.findMany({
    where: {
      userId: user.id,
      status: 'CONFIRMED',
      endUtc: { gte: new Date() },
    },
    include: { eventType: true },
    orderBy: { startUtc: 'asc' },
    take: 100,
  });

  // État de santé : résultat du dernier contrôle automatique (10 min),
  // ou contrôle immédiat au premier affichage.
  const health = lastReport() ?? (await runHealthChecks());

  return (
    <>
      <AdminNav userName={user.name} />
      <main className="mx-auto max-w-5xl px-4 py-8">
        <HealthCard report={health} />

        <div className="mb-6 flex items-center justify-between">
          <h1 className="text-2xl font-bold">Rendez-vous à venir</h1>
          <a
            href={`/${user.slug}`}
            target="_blank"
            className="btn-secondary"
            rel="noreferrer"
          >
            Voir ma page publique ↗
          </a>
        </div>

        {bookings.length === 0 ? (
          <div className="card p-10 text-center text-slate-400">
            Aucun rendez-vous à venir pour le moment.
          </div>
        ) : (
          <div className="card divide-y divide-white/10">
            {bookings.map((booking) => {
              // Réponses affichées avec le libellé des questions.
              let raw: Record<string, string> = {};
              try {
                raw = JSON.parse(booking.answers);
              } catch {}
              const labelled: Record<string, string> = {};
              for (const question of parseQuestions(booking.eventType.questions)) {
                if (raw[question.id]) labelled[question.label] = raw[question.id];
              }
              return (
                <BookingRow
                  key={booking.id}
                  id={booking.id}
                  when={formatDateTimeFr(booking.startUtc, user.timezone)}
                  eventName={booking.eventType.name}
                  color={booking.eventType.color}
                  inviteeName={booking.inviteeName}
                  inviteeEmail={
                    booking.inviteePhone
                      ? `${booking.inviteeEmail} · ${booking.inviteePhone}`
                      : booking.inviteeEmail
                  }
                  answers={JSON.stringify(labelled)}
                  meetLink={booking.meetLink}
                />
              );
            })}
          </div>
        )}
      </main>
    </>
  );
}
