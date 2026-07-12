import { notFound } from 'next/navigation';
import { db } from '@/lib/db';
import { parseQuestions } from '@/lib/utils';
import BookingClient from './BookingClient';

export const dynamic = 'force-dynamic';

const LOCATION_LABELS: Record<string, string> = {
  MEET: '📹 Visioconférence (lien envoyé à la confirmation)',
  PHONE: '📞 Par téléphone',
  ADDRESS: '📍 Sur place',
  CUSTOM: 'ℹ️ Précisé à la confirmation',
};

export default async function BookingPage({
  params,
  searchParams,
}: {
  params: Promise<{ host: string; event: string }>;
  searchParams: Promise<{ embed?: string }>;
}) {
  const { host: hostSlug, event: eventSlug } = await params;
  const { embed } = await searchParams;
  const isEmbed = embed === '1';

  const host = await db.user.findUnique({ where: { slug: hostSlug } });
  if (!host) notFound();
  const eventType = await db.eventType.findFirst({
    where: { userId: host.id, slug: eventSlug, active: true },
  });
  if (!eventType) notFound();

  const settings = await db.settings.findUnique({ where: { id: 'main' } });

  return (
    <main className={`mx-auto max-w-4xl px-4 ${isEmbed ? 'py-4' : 'py-12'}`}>
      <div className="card overflow-hidden md:grid md:grid-cols-[280px_1fr]">
        {/* Panneau récapitulatif */}
        <aside
          className="border-b border-slate-200 p-6 md:border-b-0 md:border-r"
          style={{ borderTopColor: eventType.color, borderTopWidth: 4 }}
        >
          {!isEmbed && (
            <p className="text-sm font-medium uppercase tracking-wide text-slate-500">
              {settings?.orgName}
            </p>
          )}
          <p className="mt-1 text-sm text-slate-500">{host.name}</p>
          <h1 className="mt-1 text-xl font-bold">{eventType.name}</h1>
          <div className="mt-4 grid gap-2 text-sm text-slate-600">
            <p>🕐 {eventType.durationMin} minutes</p>
            <p>{LOCATION_LABELS[eventType.locationType] ?? eventType.locationDetail}</p>
          </div>
          {eventType.description && (
            <p className="mt-4 text-sm leading-relaxed text-slate-600">
              {eventType.description}
            </p>
          )}
        </aside>

        {/* Sélecteur de créneau + formulaire */}
        <section className="p-6">
          <BookingClient
            eventTypeId={eventType.id}
            eventName={eventType.name}
            durationMin={eventType.durationMin}
            questions={parseQuestions(eventType.questions)}
            collectPhone={eventType.collectPhone}
            mode="book"
          />
        </section>
      </div>
    </main>
  );
}
