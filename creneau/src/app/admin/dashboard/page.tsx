import { redirect } from 'next/navigation';
import { getSessionUser } from '@/lib/auth';
import { db } from '@/lib/db';
import { formatDateTimeFr, parseQuestions } from '@/lib/utils';
import AdminNav from '../AdminNav';
import BookingRow from './BookingRow';

export const dynamic = 'force-dynamic';

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

  return (
    <>
      <AdminNav userName={user.name} />
      <main className="mx-auto max-w-5xl px-4 py-8">
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
          <div className="card p-10 text-center text-slate-500">
            Aucun rendez-vous à venir pour le moment.
          </div>
        ) : (
          <div className="card divide-y divide-slate-100">
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
                  inviteeEmail={booking.inviteeEmail}
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
