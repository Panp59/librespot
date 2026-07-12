import type { Metadata } from 'next';
import './globals.css';
import { db } from '@/lib/db';
import { hexToRgbTriplet, lightenTriplet } from '@/lib/utils';

export const dynamic = 'force-dynamic';

export async function generateMetadata(): Promise<Metadata> {
  const settings = await db.settings.findUnique({ where: { id: 'main' } });
  return {
    title: settings?.orgName || 'Créneau',
    description: 'Prise de rendez-vous en ligne',
  };
}

export default async function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const settings = await db.settings.findUnique({ where: { id: 'main' } });
  const accent = hexToRgbTriplet(settings?.accentColor || '#3E63F5');
  const accentLight = lightenTriplet(accent);

  return (
    <html
      lang="fr"
      style={
        {
          ['--accent' as string]: accent,
          ['--accent-light' as string]: accentLight,
        } as React.CSSProperties
      }
    >
      <body>{children}</body>
    </html>
  );
}
