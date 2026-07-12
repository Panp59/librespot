import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { buildIcs } from '@/lib/ics';
import { locationText, manageUrl } from '@/lib/mail';
import { baseUrl } from '@/lib/utils';

/** Téléchargement de l'invitation .ics (ajout manuel au calendrier). */
export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ token: string }> }
) {
  const { token } = await params;
  const booking = await db.booking.findUnique({
    where: { manageToken: token },
    include: { eventType: { include: { user: true } } },
  });
  if (!booking || booking.status === 'CANCELLED') {
    return NextResponse.json({ error: 'Rendez-vous introuvable.' }, { status: 404 });
  }
  const host = booking.eventType.user;
  const ics = buildIcs({
    uid: booking.id,
    start: booking.startUtc,
    end: booking.endUtc,
    summary: `${booking.eventType.name} avec ${host.name}`,
    description: `Réservé via ${baseUrl()}\nGérer : ${manageUrl(booking)}`,
    location: locationText({ booking, eventType: booking.eventType, host }),
    organizerName: host.name,
    organizerEmail: host.email,
    attendeeName: booking.inviteeName,
    attendeeEmail: booking.inviteeEmail,
    method: 'REQUEST',
  });
  return new NextResponse(ics, {
    headers: {
      'Content-Type': 'text/calendar; charset=utf-8',
      'Content-Disposition': 'attachment; filename="rendez-vous.ics"',
    },
  });
}
