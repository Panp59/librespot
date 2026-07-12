import { z } from 'zod';

function isJsonArray(value: string): boolean {
  try {
    return Array.isArray(JSON.parse(value));
  } catch {
    return false;
  }
}

export const eventTypeSchema = z.object({
  name: z.string().trim().min(1).max(120),
  slug: z.string().trim().max(120).default(''),
  description: z.string().max(2000).default(''),
  durationMin: z.number().int().min(5).max(480),
  bufferBeforeMin: z.number().int().min(0).max(240).default(0),
  bufferAfterMin: z.number().int().min(0).max(240).default(0),
  minNoticeMin: z.number().int().min(0).max(60 * 24 * 30).default(240),
  maxDaysAhead: z.number().int().min(1).max(365).default(60),
  color: z.string().regex(/^#[0-9a-fA-F]{6}$/).default('#4f46e5'),
  locationType: z.enum(['MEET', 'PHONE', 'ADDRESS', 'CUSTOM']).default('MEET'),
  locationDetail: z.string().max(500).default(''),
  questions: z.string().refine(isJsonArray, 'JSON invalide').default('[]'),
  reminders: z.string().refine(isJsonArray, 'JSON invalide').default('[1440,60]'),
  active: z.boolean().default(true),
});
