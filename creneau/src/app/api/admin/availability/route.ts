import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';
import { getSessionUser } from '@/lib/auth';
import { db } from '@/lib/db';

const bodySchema = z.object({
  windows: z
    .array(
      z.object({
        weekday: z.number().int().min(1).max(7),
        startMinute: z.number().int().min(0).max(24 * 60),
        endMinute: z.number().int().min(0).max(24 * 60),
      })
    )
    .max(100),
});

export async function PUT(request: NextRequest) {
  const user = await getSessionUser();
  if (!user) return NextResponse.json({ error: 'Non connecté.' }, { status: 401 });

  const parsed = bodySchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ error: 'Requête invalide.' }, { status: 400 });
  }
  const windows = parsed.data.windows.filter((w) => w.endMinute > w.startMinute);

  await db.$transaction([
    db.availability.deleteMany({ where: { userId: user.id } }),
    db.availability.createMany({
      data: windows.map((w) => ({ ...w, userId: user.id })),
    }),
  ]);

  return NextResponse.json({ ok: true });
}
