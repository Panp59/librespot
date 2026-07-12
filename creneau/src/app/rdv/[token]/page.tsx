import Link from 'next/link';
import { notFound } from 'next/navigation';
import { db } from '@/lib/db';
import { locationText } from '@/lib/mail';
import { formatDateTimeFr } from '@/lib/utils';
import CancelButton from './CancelButton';

export const dynamic = 'force-dynamic';

export default async function ManageBookingPage({
  params,
  searchParams,
}: {
  params: Promise<{ token: string }>;
  searchParams: Promise<{ nouveau?: string; deplace?: string }>;
}) {
  const { token } = await params;
  const query = await searchParams;

  const booking = await db.booking.findUnique({
    where: { manageToken: token },
    include: { eventType: { include: { user: true } } },
  });
  if (!booking) notFound();

  const host = booking.eventType.user;
  const cancelled = booking.status === 'CANCELLED';
  const banner = query.nouveau
    ? '✅ Votre rendez-vous est confirmé ! Un email récapitulatif vous a été envoyé.'
    : query.deplace
      ? '✅ Votre rendez-vous a bien été déplacé.'
      : null;
  const location = locationText({ booking, eventType: booking.eventType, host });
  const isLink = location.startsWith('http');

  return (
    <main className="mx-auto max-w-lg px-4 py-16">
      {banner && !cancelled && (
        <p className="mb-6 rounded-xl bg-green-50 p-4 text-sm font-medium text-green-800">
          {banner}
        </p>
      )}

      <div className="card p-6">
        <p className="text-sm text-slate-500">
          {cancelled ? 'Rendez-vous annulé' : 'Votre rendez-vous'}
        </p>
        <h1 className={`mt-1 text-xl font-bold ${cancelled ? 'line-through' : ''}`}>
          {booking.eventType.name} avec {host.name}
        </h1>

        <div className="mt-5 grid gap-2 text-sm text-slate-700">
          <p>
            📅 {formatDateTimeFr(booking.startUtc, booking.inviteeTimezone)}{' '}
            <span className="text-slate-400">({booking.inviteeTimezone})</span>
          </p>
          <p>🕐 {booking.eventType.durationMin} minutes</p>
          <p>
            📍{' '}
            {isLink ? (
              <a
                href={location}
                className="font-medium text-accent hover:underline"
                target="_blank"
                rel="noreferrer"
              >
                Rejoindre la visioconférence
              </a>
            ) : (
              location
            )}
          </p>
          <p>👤 {booking.inviteeName} ({booking.inviteeEmail})</p>
        </div>

        {!cancelled && (
          <div className="mt-8 flex flex-wrap gap-3">
            <Link
              href={`/rdv/${token}/reprogrammer`}
              className="btn-secondary"
            >
              Reprogrammer
            </Link>
            <CancelButton token={token} />
          </div>
        )}

        {cancelled && (
          <p className="mt-8 text-sm text-slate-600">
            Vous pouvez reprendre un créneau ici :{' '}
            <Link
              href={`/${host.slug}/${booking.eventType.slug}`}
              className="font-medium text-accent hover:underline"
            >
              {booking.eventType.name}
            </Link>
          </p>
        )}
      </div>
    </main>
  );
}
