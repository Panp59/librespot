import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';
import { getSessionUser } from '@/lib/auth';
import { db } from '@/lib/db';

const bodySchema = z.object({
  orgName: z.string().trim().min(1).max(120),
  accentColor: z.string().regex(/^#[0-9a-fA-F]{6}$/),
  logoUrl: z.string().trim().max(500).default(''),
  welcomeText: z.string().trim().max(500).default(''),
});

export async function PUT(request: NextRequest) {
  const user = await getSessionUser();
  if (!user?.isAdmin) {
    return NextResponse.json({ error: 'Réservé aux administrateurs.' }, { status: 403 });
  }
  const parsed = bodySchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ error: 'Formulaire invalide.' }, { status: 400 });
  }
  await db.settings.upsert({
    where: { id: 'main' },
    update: parsed.data,
    create: { id: 'main', ...parsed.data },
  });
  return NextResponse.json({ ok: true });
}
