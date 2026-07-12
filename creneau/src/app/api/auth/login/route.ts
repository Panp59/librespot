import { NextRequest, NextResponse } from 'next/server';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { createSession } from '@/lib/auth';
import { db } from '@/lib/db';

const bodySchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

export async function POST(request: NextRequest) {
  const parsed = bodySchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ error: 'Requête invalide.' }, { status: 400 });
  }
  const user = await db.user.findUnique({
    where: { email: parsed.data.email.toLowerCase().trim() },
  });
  if (!user || !bcrypt.compareSync(parsed.data.password, user.passwordHash)) {
    return NextResponse.json({ error: 'Identifiants incorrects.' }, { status: 401 });
  }
  await createSession(user.id);
  return NextResponse.json({ ok: true });
}
