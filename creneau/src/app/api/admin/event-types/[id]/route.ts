import { NextRequest, NextResponse } from 'next/server';
import { getSessionUser } from '@/lib/auth';
import { db } from '@/lib/db';
import { slugify } from '@/lib/utils';
import { eventTypeSchema } from '../../event-type-schema';

export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const user = await getSessionUser();
  if (!user) return NextResponse.json({ error: 'Non connecté.' }, { status: 401 });
  const { id } = await params;

  const existing = await db.eventType.findFirst({ where: { id, userId: user.id } });
  if (!existing) {
    return NextResponse.json({ error: 'Introuvable.' }, { status: 404 });
  }

  const parsed = eventTypeSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ error: 'Formulaire invalide.' }, { status: 400 });
  }
  const data = parsed.data;
  const slug = slugify(data.slug || data.name);

  const duplicate = await db.eventType.findFirst({
    where: { userId: user.id, slug, id: { not: id } },
  });
  if (duplicate) {
    return NextResponse.json({ error: `L'adresse « ${slug} » est déjà utilisée.` }, { status: 409 });
  }

  const eventType = await db.eventType.update({
    where: { id },
    data: { ...data, slug },
  });
  return NextResponse.json({ eventType });
}

export async function DELETE(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const user = await getSessionUser();
  if (!user) return NextResponse.json({ error: 'Non connecté.' }, { status: 401 });
  const { id } = await params;

  const existing = await db.eventType.findFirst({ where: { id, userId: user.id } });
  if (!existing) {
    return NextResponse.json({ error: 'Introuvable.' }, { status: 404 });
  }
  await db.eventType.delete({ where: { id } });
  return NextResponse.json({ ok: true });
}
