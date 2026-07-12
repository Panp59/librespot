import { google } from 'googleapis';
import type { User } from '@prisma/client';
import { DateTime, Interval } from 'luxon';
import { db } from './db';
import { baseUrl } from './utils';

export function googleConfigured(): boolean {
  return Boolean(process.env.GOOGLE_CLIENT_ID && process.env.GOOGLE_CLIENT_SECRET);
}

function oauthClient() {
  return new google.auth.OAuth2(
    process.env.GOOGLE_CLIENT_ID,
    process.env.GOOGLE_CLIENT_SECRET,
    `${baseUrl()}/api/google/callback`
  );
}

export function googleAuthUrl(state: string): string {
  return oauthClient().generateAuthUrl({
    access_type: 'offline',
    prompt: 'consent',
    scope: [
      'https://www.googleapis.com/auth/calendar.events',
      'https://www.googleapis.com/auth/calendar.readonly',
    ],
    state,
  });
}

export async function exchangeCode(code: string) {
  const { tokens } = await oauthClient().getToken(code);
  return tokens;
}

/** Client authentifié pour un hôte, ou null si non connecté.
 *  Persiste les jetons rafraîchis automatiquement. */
function clientFor(user: User) {
  if (!user.googleTokens || !googleConfigured()) return null;
  let tokens;
  try {
    tokens = JSON.parse(user.googleTokens);
  } catch {
    return null;
  }
  const client = oauthClient();
  client.setCredentials(tokens);
  client.on('tokens', (updated) => {
    const merged = { ...tokens, ...updated };
    db.user
      .update({ where: { id: user.id }, data: { googleTokens: JSON.stringify(merged) } })
      .catch(() => {});
  });
  return client;
}

/** Plages occupées du calendrier principal (vide si Google non connecté). */
export async function getBusyIntervals(
  user: User,
  from: DateTime,
  to: DateTime
): Promise<Interval[]> {
  const auth = clientFor(user);
  if (!auth) return [];
  try {
    const calendar = google.calendar({ version: 'v3', auth });
    const response = await calendar.freebusy.query({
      requestBody: {
        timeMin: from.toISO(),
        timeMax: to.toISO(),
        items: [{ id: 'primary' }],
      },
    });
    const periods = response.data.calendars?.primary?.busy ?? [];
    return periods
      .filter((p) => p.start && p.end)
      .map((p) =>
        Interval.fromDateTimes(
          DateTime.fromISO(p.start!, { zone: 'utc' }),
          DateTime.fromISO(p.end!, { zone: 'utc' })
        )
      );
  } catch (error) {
    console.error('Google freebusy en échec (créneaux internes seulement):', error);
    return [];
  }
}

type BookingInfo = {
  id: string;
  summary: string;
  description: string;
  startIsoUtc: string;
  endIsoUtc: string;
  inviteeEmail: string;
  inviteeName: string;
  withMeet: boolean;
};

/** Crée l'événement dans le Google Calendar de l'hôte.
 *  Retourne {eventId, meetLink} ou null si Google non connecté / en échec. */
export async function createCalendarEvent(
  user: User,
  info: BookingInfo
): Promise<{ eventId: string; meetLink: string } | null> {
  const auth = clientFor(user);
  if (!auth) return null;
  try {
    const calendar = google.calendar({ version: 'v3', auth });
    const response = await calendar.events.insert({
      calendarId: 'primary',
      conferenceDataVersion: info.withMeet ? 1 : 0,
      sendUpdates: 'all',
      requestBody: {
        summary: info.summary,
        description: info.description,
        start: { dateTime: info.startIsoUtc },
        end: { dateTime: info.endIsoUtc },
        attendees: [{ email: info.inviteeEmail, displayName: info.inviteeName }],
        reminders: { useDefault: true },
        ...(info.withMeet
          ? {
              conferenceData: {
                createRequest: {
                  requestId: info.id,
                  conferenceSolutionKey: { type: 'hangoutsMeet' },
                },
              },
            }
          : {}),
      },
    });
    return {
      eventId: response.data.id ?? '',
      meetLink: response.data.hangoutLink ?? '',
    };
  } catch (error) {
    console.error('Création événement Google en échec:', error);
    return null;
  }
}

export async function updateCalendarEvent(
  user: User,
  eventId: string,
  startIsoUtc: string,
  endIsoUtc: string
): Promise<void> {
  const auth = clientFor(user);
  if (!auth || !eventId) return;
  try {
    const calendar = google.calendar({ version: 'v3', auth });
    await calendar.events.patch({
      calendarId: 'primary',
      eventId,
      sendUpdates: 'all',
      requestBody: {
        start: { dateTime: startIsoUtc },
        end: { dateTime: endIsoUtc },
      },
    });
  } catch (error) {
    console.error('Mise à jour événement Google en échec:', error);
  }
}

export async function deleteCalendarEvent(user: User, eventId: string): Promise<void> {
  const auth = clientFor(user);
  if (!auth || !eventId) return;
  try {
    const calendar = google.calendar({ version: 'v3', auth });
    await calendar.events.delete({ calendarId: 'primary', eventId, sendUpdates: 'all' });
  } catch (error) {
    console.error('Suppression événement Google en échec:', error);
  }
}
