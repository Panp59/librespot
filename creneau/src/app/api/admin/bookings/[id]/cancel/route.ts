import { NextRequest, NextResponse } from 'next/server';
import { getSessionUser } from '@/lib/auth';
import { db } from '@/lib/db';
import { deleteCalendarEvent } from '@/lib/google';
import { sendCancellation } from '@/lib/mail';
import { smsCancellation } from '@/lib/sms';

export async function POST(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const user = await getSessionUser();
  if (!user) return NextResponse.json({ error: 'Non connecté.' }, { status: 401 });
  const { id } = await params;

  const booking = await db.booking.findFirst({
    where: { id, userId: user.id },
    include: { eventType: { include: { user: true } } },
  });
  if (!booking) {
    return NextResponse.json({ error: 'Introuvable.' }, { status: 404 });
  }
  if (booking.status === 'CANCELLED') return NextResponse.json({ ok: true });

  const updated = await db.booking.update({
    where: { id },
    data: { status: 'CANCELLED' },
  });
  await deleteCalendarEvent(booking.eventType.user, booking.googleEventId);
  const bundle = { booking: updated, eventType: booking.eventType, host: booking.eventType.user };
  await sendCancellation(bundle, user.name);
  await smsCancellation(bundle);
  return NextResponse.json({ ok: true });
}
