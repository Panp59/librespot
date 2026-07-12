import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { computeSlots } from '@/lib/slots';

export async function GET(request: NextRequest) {
  const { searchParams } = request.nextUrl;
  const eventTypeId = searchParams.get('eventTypeId');
  const from = searchParams.get('from');
  const to = searchParams.get('to');
  // Jeton de gestion : en reprogrammation, le RDV déplacé est exclu des occupations.
  const excludeToken = searchParams.get('exclude');
  if (!eventTypeId || !from || !to) {
    return NextResponse.json({ error: 'Paramètres manquants.' }, { status: 400 });
  }

  const eventType = await db.eventType.findFirst({
    where: { id: eventTypeId, active: true },
    include: { user: true },
  });
  if (!eventType) {
    return NextResponse.json({ error: 'Type de rendez-vous introuvable.' }, { status: 404 });
  }

  let excludeBookingId: string | undefined;
  if (excludeToken) {
    const excluded = await db.booking.findUnique({
      where: { manageToken: excludeToken },
      select: { id: true },
    });
    excludeBookingId = excluded?.id;
  }

  const slots = await computeSlots(eventType, from, to, excludeBookingId);
  return NextResponse.json({ slots });
}
