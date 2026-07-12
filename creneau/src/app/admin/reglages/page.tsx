import { redirect } from 'next/navigation';
import { getSessionUser } from '@/lib/auth';
import { db } from '@/lib/db';
import { googleConfigured } from '@/lib/google';
import { baseUrl } from '@/lib/utils';
import AdminNav from '../AdminNav';
import SettingsClient from './SettingsClient';

export const dynamic = 'force-dynamic';

export default async function SettingsPage({
  searchParams,
}: {
  searchParams: Promise<{ google?: string }>;
}) {
  const user = await getSessionUser();
  if (!user) redirect('/admin');
  const query = await searchParams;

  const settings = await db.settings.findUnique({ where: { id: 'main' } });
  const users = user.isAdmin
    ? await db.user.findMany({
        select: { id: true, name: true, email: true, slug: true, isAdmin: true },
        orderBy: { createdAt: 'asc' },
      })
    : [];

  return (
    <>
      <AdminNav userName={user.name} />
      <main className="mx-auto max-w-3xl px-4 py-8">
        <h1 className="mb-6 text-2xl font-bold">Réglages</h1>
        {query.google === 'ok' && (
          <p className="mb-6 rounded-xl bg-green-500/10 p-4 text-sm font-medium text-green-300">
            ✅ Google Calendar connecté !
          </p>
        )}
        {query.google === 'erreur' && (
          <p className="mb-6 rounded-xl bg-red-500/10 p-4 text-sm font-medium text-red-300">
            ⚠️ La connexion Google a échoué. Réessaie.
          </p>
        )}
        <SettingsClient
          profile={{
            name: user.name,
            slug: user.slug,
            timezone: user.timezone,
            videoLink: user.videoLink,
          }}
          isAdmin={user.isAdmin}
          googleAvailable={googleConfigured()}
          googleConnected={Boolean(user.googleTokens)}
          settings={{
            orgName: settings?.orgName ?? 'Créneau',
            accentColor: settings?.accentColor ?? '#4f46e5',
            logoUrl: settings?.logoUrl ?? '',
            welcomeText: settings?.welcomeText ?? '',
          }}
          users={users}
          baseUrl={baseUrl()}
        />
      </main>
    </>
  );
}
