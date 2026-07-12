import { DateTime } from 'luxon';

type IcsEvent = {
  uid: string;
  start: Date;
  end: Date;
  summary: string;
  description: string;
  location: string;
  organizerName: string;
  organizerEmail: string;
  attendeeName: string;
  attendeeEmail: string;
  method: 'REQUEST' | 'CANCEL';
  sequence?: number;
};

function icsDate(date: Date): string {
  return DateTime.fromJSDate(date, { zone: 'utc' }).toFormat("yyyyLLdd'T'HHmmss'Z'");
}

function escapeText(text: string): string {
  return text.replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,').replace(/\r?\n/g, '\\n');
}

/** Fichier .ics (invitation ou annulation) joint aux emails. */
export function buildIcs(event: IcsEvent): string {
  const lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Creneau//FR',
    `METHOD:${event.method}`,
    'BEGIN:VEVENT',
    `UID:${event.uid}@creneau`,
    `SEQUENCE:${event.sequence ?? 0}`,
    `DTSTAMP:${icsDate(new Date())}`,
    `DTSTART:${icsDate(event.start)}`,
    `DTEND:${icsDate(event.end)}`,
    `SUMMARY:${escapeText(event.summary)}`,
    `DESCRIPTION:${escapeText(event.description)}`,
    `LOCATION:${escapeText(event.location)}`,
    `ORGANIZER;CN=${escapeText(event.organizerName)}:mailto:${event.organizerEmail}`,
    `ATTENDEE;CN=${escapeText(event.attendeeName)};RSVP=TRUE:mailto:${event.attendeeEmail}`,
    `STATUS:${event.method === 'CANCEL' ? 'CANCELLED' : 'CONFIRMED'}`,
    'END:VEVENT',
    'END:VCALENDAR',
  ];
  return lines.join('\r\n');
}
