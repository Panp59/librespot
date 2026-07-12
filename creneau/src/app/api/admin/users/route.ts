import { NextRequest, NextResponse } from 'next/server';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { getSessionUser } from '@/lib/auth';
import { db } from '@/lib/db';
import { slugify } from '@/lib/utils';

export async function GET() {
  const user = await getSessionUser();
  if (!user?.isAdmin) {
    return NextResponse.json({ error: 'Réservé aux administrateurs.' }, { status: 403 });
  }
  const users = await db.user.findMany({
    select: { id: true, name: true, email: true, slug: true, isAdmin: true },
    orderBy: { createdAt: 'asc' },
  });
  return NextResponse.json({ users });
}

const bodySchema = z.object({
  name: z.string().trim().min(1).max(120),
  email: z.string().trim().email(),
  password: z.string().min(8).max(200),
});

export async function POST(request: NextRequest) {
  const user = await getSessionUser();
  if (!user?.isAdmin) {
    return NextResponse.json({ error: 'Réservé aux administrateurs.' }, { status: 403 });
  }
  const parsed = bodySchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json(
      { error: 'Formulaire invalide (mot de passe : 8 caractères minimum).' },
      { status: 400 }
    );
  }
  const data = parsed.data;
  const email = data.email.toLowerCase();

  if (await db.user.findUnique({ where: { email } })) {
    return NextResponse.json({ error: 'Cet email existe déjà.' }, { status: 409 });
  }
  let slug = slugify(data.name);
  if (await db.user.findUnique({ where: { slug } })) {
    slug = `${slug}-${Math.floor(Math.random() * 1000)}`;
  }

  const created = await db.user.create({
    data: {
      name: data.name,
      email,
      slug,
      passwordHash: bcrypt.hashSync(data.password, 12),
      // Disponibilités par défaut : lun-ven 9h-18h (modifiable ensuite).
      availability: {
        create: [1, 2, 3, 4, 5].map((weekday) => ({
          weekday,
          startMinute: 9 * 60,
          endMinute: 18 * 60,
        })),
      },
    },
  });
  return NextResponse.json({ id: created.id });
}
