import { redirect } from 'next/navigation';
import { getSessionUser } from '@/lib/auth';
import { db } from '@/lib/db';
import AdminNav from '../AdminNav';
import EventTypesClient from './EventTypesClient';

export const dynamic = 'force-dynamic';

export default async function EventTypesPage() {
  const user = await getSessionUser();
  if (!user) redirect('/admin');

  const eventTypes = await db.eventType.findMany({
    where: { userId: user.id },
    orderBy: { createdAt: 'asc' },
  });

  return (
    <>
      <AdminNav userName={user.name} />
      <main className="mx-auto max-w-5xl px-4 py-8">
        <h1 className="mb-6 text-2xl font-bold">Types de rendez-vous</h1>
        <EventTypesClient
          hostSlug={user.slug}
          initial={eventTypes.map((eventType) => ({
            id: eventType.id,
            name: eventType.name,
            slug: eventType.slug,
            description: eventType.description,
            durationMin: eventType.durationMin,
            bufferBeforeMin: eventType.bufferBeforeMin,
            bufferAfterMin: eventType.bufferAfterMin,
            minNoticeMin: eventType.minNoticeMin,
            maxDaysAhead: eventType.maxDaysAhead,
            color: eventType.color,
            locationType: eventType.locationType,
            locationDetail: eventType.locationDetail,
            questions: eventType.questions,
            reminders: eventType.reminders,
            active: eventType.active,
          }))}
        />
      </main>
    </>
  );
}
