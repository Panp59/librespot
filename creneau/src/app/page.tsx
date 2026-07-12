import Link from 'next/link';
import { db } from '@/lib/db';

export const dynamic = 'force-dynamic';

export default async function HomePage() {
  const [settings, hosts] = await Promise.all([
    db.settings.findUnique({ where: { id: 'main' } }),
    db.user.findMany({
      where: { eventTypes: { some: { active: true } } },
      include: { eventTypes: { where: { active: true } } },
      orderBy: { createdAt: 'asc' },
    }),
  ]);

  return (
    <main className="mx-auto max-w-3xl px-4 py-16">
      <header className="mb-12 text-center">
        {settings?.logoUrl ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={settings.logoUrl}
            alt=""
            className="mx-auto mb-6 h-14 w-auto"
          />
        ) : null}
        <p className="mb-4">
          <span className="pill">Prise de rendez-vous</span>
        </p>
        <h1 className="text-3xl font-bold tracking-tight text-white">
          {settings?.orgName || 'Créneau'}
        </h1>
        <p className="mt-3 text-slate-300">{settings?.welcomeText}</p>
      </header>

      <div className="grid gap-4">
        {hosts.map((host) => (
          <section key={host.id} className="card p-6">
            <h2 className="text-lg font-semibold">{host.name}</h2>
            <div className="mt-4 grid gap-3 sm:grid-cols-2">
              {host.eventTypes.map((eventType) => (
                <Link
                  key={eventType.id}
                  href={`/${host.slug}/${eventType.slug}`}
                  className="group flex items-center gap-3 rounded-xl border border-white/10 p-4 transition hover:border-accent hover:shadow-sm"
                >
                  <span
                    className="h-3 w-3 shrink-0 rounded-full"
                    style={{ backgroundColor: eventType.color }}
                  />
                  <span>
                    <span className="block font-medium group-hover:text-accent-light">
                      {eventType.name}
                    </span>
                    <span className="text-sm text-slate-400">
                      {eventType.durationMin} min
                    </span>
                  </span>
                </Link>
              ))}
            </div>
          </section>
        ))}
        {hosts.length === 0 && (
          <p className="text-center text-slate-400">
            Aucun rendez-vous disponible pour le moment.
          </p>
        )}
      </div>

      <footer className="mt-16 text-center text-xs text-slate-400">
        Propulsé par Créneau. Vos données restent chez vous.
      </footer>
    </main>
  );
}
