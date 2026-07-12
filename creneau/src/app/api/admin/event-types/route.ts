import { NextRequest, NextResponse } from 'next/server';
import { getSessionUser } from '@/lib/auth';
import { db } from '@/lib/db';
import { slugify } from '@/lib/utils';
import { eventTypeSchema } from '../event-type-schema';

export async function POST(request: NextRequest) {
  const user = await getSessionUser();
  if (!user) return NextResponse.json({ error: 'Non connecté.' }, { status: 401 });

  const parsed = eventTypeSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ error: 'Formulaire invalide.' }, { status: 400 });
  }
  const data = parsed.data;
  const slug = slugify(data.slug || data.name);
  if (!slug) {
    return NextResponse.json({ error: 'Nom invalide.' }, { status: 400 });
  }

  const duplicate = await db.eventType.findFirst({ where: { userId: user.id, slug } });
  if (duplicate) {
    return NextResponse.json({ error: `L'adresse « ${slug} » est déjà utilisée.` }, { status: 409 });
  }

  const eventType = await db.eventType.create({
    data: { ...data, slug, userId: user.id },
  });
  return NextResponse.json({ eventType });
}
