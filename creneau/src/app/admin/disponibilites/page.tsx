import { redirect } from 'next/navigation';
import { getSessionUser } from '@/lib/auth';
import { db } from '@/lib/db';
import AdminNav from '../AdminNav';
import AvailabilityClient from './AvailabilityClient';

export const dynamic = 'force-dynamic';

export default async function AvailabilityPage() {
  const user = await getSessionUser();
  if (!user) redirect('/admin');

  const availability = await db.availability.findMany({
    where: { userId: user.id },
    orderBy: [{ weekday: 'asc' }, { startMinute: 'asc' }],
  });

  return (
    <>
      <AdminNav userName={user.name} />
      <main className="mx-auto max-w-3xl px-4 py-8">
        <h1 className="mb-2 text-2xl font-bold">Disponibilités hebdomadaires</h1>
        <p className="mb-6 text-sm text-slate-500">
          Fuseau : {user.timezone}. Les créneaux proposés aux visiteurs sont
          calculés à partir de ces plages, moins vos rendez-vous et votre
          agenda Google.
        </p>
        <AvailabilityClient
          initial={availability.map((a) => ({
            weekday: a.weekday,
            startMinute: a.startMinute,
            endMinute: a.endMinute,
          }))}
        />
      </main>
    </>
  );
}
