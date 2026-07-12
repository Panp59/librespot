import { DateTime } from 'luxon';

export function slugify(text: string): string {
  return text
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

/** « lundi 14 juillet 2026 à 10:30 » dans le fuseau donné. */
export function formatDateTimeFr(isoUtc: string | Date, timezone: string): string {
  const dt = (
    typeof isoUtc === 'string'
      ? DateTime.fromISO(isoUtc, { zone: 'utc' })
      : DateTime.fromJSDate(isoUtc, { zone: 'utc' })
  )
    .setZone(timezone)
    .setLocale('fr');
  return `${dt.toFormat("cccc d LLLL yyyy 'à' HH:mm")}`;
}

export function baseUrl(): string {
  return (process.env.BASE_URL || 'http://localhost:3000').replace(/\/$/, '');
}

export type Question = {
  id: string;
  label: string;
  type: 'text' | 'textarea' | 'phone' | 'select';
  required: boolean;
  options?: string[];
};

export function parseQuestions(json: string): Question[] {
  try {
    const parsed = JSON.parse(json);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

export function parseJsonArray(json: string): number[] {
  try {
    const parsed = JSON.parse(json);
    return Array.isArray(parsed) ? parsed.filter((n) => typeof n === 'number') : [];
  } catch {
    return [];
  }
}

/** #4f46e5 → « 79 70 229 » pour la variable CSS Tailwind. */
export function hexToRgbTriplet(hex: string): string {
  const clean = hex.replace('#', '');
  const full = clean.length === 3 ? clean.split('').map((c) => c + c).join('') : clean;
  const n = parseInt(full, 16);
  if (Number.isNaN(n) || full.length !== 6) return '79 70 229';
  return `${(n >> 16) & 255} ${(n >> 8) & 255} ${n & 255}`;
}
