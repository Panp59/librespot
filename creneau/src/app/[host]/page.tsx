import Link from 'next/link';
import { notFound } from 'next/navigation';
import { db } from '@/lib/db';

export const dynamic = 'force-dynamic';

export default async function HostPage({
  params,
}: {
  params: Promise<{ host: string }>;
}) {
  const { host: hostSlug } = await params;
  const host = await db.user.findUnique({
    where: { slug: hostSlug },
    include: { eventTypes: { where: { active: true } } },
  });
  if (!host) notFound();

  const settings = await db.settings.findUnique({ where: { id: 'main' } });

  return (
    <main className="mx-auto max-w-xl px-4 py-16">
      <header className="mb-10 text-center">
        <p>
          <span className="pill">{settings?.orgName}</span>
        </p>
        <h1 className="mt-1 text-3xl font-bold tracking-tight">{host.name}</h1>
        <p className="mt-3 text-slate-300">
          Choisissez le type de rendez-vous qui vous convient.
        </p>
      </header>

      <div className="grid gap-4">
        {host.eventTypes.map((eventType) => (
          <Link
            key={eventType.id}
            href={`/${host.slug}/${eventType.slug}`}
            className="card group flex items-center justify-between p-5 transition hover:border-accent"
          >
            <div className="flex items-center gap-4">
              <span
                className="h-3.5 w-3.5 shrink-0 rounded-full"
                style={{ backgroundColor: eventType.color }}
              />
              <div>
                <h2 className="font-semibold group-hover:text-accent-light">
                  {eventType.name}
                </h2>
                {eventType.description && (
                  <p className="mt-0.5 line-clamp-2 text-sm text-slate-400">
                    {eventType.description}
                  </p>
                )}
              </div>
            </div>
            <span className="ml-4 shrink-0 rounded-full bg-white/10 px-3 py-1 text-xs font-medium text-slate-300">
              {eventType.durationMin} min
            </span>
          </Link>
        ))}
      </div>
    </main>
  );
}
