import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { deleteCalendarEvent } from '@/lib/google';
import { sendCancellation } from '@/lib/mail';

export async function POST(
  _request: NextRequest,
  { params }: { params: Promise<{ token: string }> }
) {
  const { token } = await params;
  const booking = await db.booking.findUnique({
    where: { manageToken: token },
    include: { eventType: { include: { user: true } } },
  });
  if (!booking) {
    return NextResponse.json({ error: 'Rendez-vous introuvable.' }, { status: 404 });
  }
  if (booking.status === 'CANCELLED') {
    return NextResponse.json({ ok: true });
  }

  const updated = await db.booking.update({
    where: { id: booking.id },
    data: { status: 'CANCELLED' },
  });

  await deleteCalendarEvent(booking.eventType.user, booking.googleEventId);
  await sendCancellation(
    { booking: updated, eventType: booking.eventType, host: booking.eventType.user },
    booking.inviteeName
  );

  return NextResponse.json({ ok: true });
}
