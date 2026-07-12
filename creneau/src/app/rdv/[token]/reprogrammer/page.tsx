import Link from 'next/link';
import { notFound } from 'next/navigation';
import { db } from '@/lib/db';
import { formatDateTimeFr, parseQuestions } from '@/lib/utils';
import BookingClient from '@/app/[host]/[event]/BookingClient';

export const dynamic = 'force-dynamic';

export default async function ReschedulePage({
  params,
}: {
  params: Promise<{ token: string }>;
}) {
  const { token } = await params;
  const booking = await db.booking.findUnique({
    where: { manageToken: token },
    include: { eventType: { include: { user: true } } },
  });
  if (!booking || booking.status === 'CANCELLED') notFound();

  return (
    <main className="mx-auto max-w-4xl px-4 py-12">
      <Link href={`/rdv/${token}`} className="text-sm font-medium text-accent hover:underline">
        ← Retour au rendez-vous
      </Link>
      <div className="card mt-4 p-6">
        <h1 className="text-xl font-bold">Reprogrammer votre rendez-vous</h1>
        <p className="mt-1 text-sm text-slate-600">
          Créneau actuel : {formatDateTimeFr(booking.startUtc, booking.inviteeTimezone)}
        </p>
        <div className="mt-6">
          <BookingClient
            eventTypeId={booking.eventTypeId}
            eventName={booking.eventType.name}
            durationMin={booking.eventType.durationMin}
            questions={parseQuestions(booking.eventType.questions)}
            mode="reschedule"
            manageToken={token}
          />
        </div>
      </div>
    </main>
  );
}
