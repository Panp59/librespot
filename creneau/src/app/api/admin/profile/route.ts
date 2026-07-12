import { NextRequest, NextResponse } from 'next/server';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { getSessionUser } from '@/lib/auth';
import { db } from '@/lib/db';
import { slugify } from '@/lib/utils';

const bodySchema = z.object({
  name: z.string().trim().min(1).max(120),
  slug: z.string().trim().min(1).max(120),
  timezone: z.string().min(1).max(64),
  videoLink: z.string().trim().max(500).default(''),
  password: z.string().max(200).default(''),
});

export async function PUT(request: NextRequest) {
  const user = await getSessionUser();
  if (!user) return NextResponse.json({ error: 'Non connecté.' }, { status: 401 });

  const parsed = bodySchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ error: 'Formulaire invalide.' }, { status: 400 });
  }
  const data = parsed.data;
  const slug = slugify(data.slug);
  if (!slug) return NextResponse.json({ error: 'Adresse invalide.' }, { status: 400 });

  const duplicate = await db.user.findFirst({ where: { slug, id: { not: user.id } } });
  if (duplicate) {
    return NextResponse.json({ error: `L'adresse « ${slug} » est déjà prise.` }, { status: 409 });
  }

  await db.user.update({
    where: { id: user.id },
    data: {
      name: data.name,
      slug,
      timezone: data.timezone,
      videoLink: data.videoLink,
      ...(data.password ? { passwordHash: bcrypt.hashSync(data.password, 12) } : {}),
    },
  });
  return NextResponse.json({ ok: true });
}
