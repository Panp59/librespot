import { NextResponse } from 'next/server';
import { SignJWT } from 'jose';
import { getSessionUser } from '@/lib/auth';
import { googleAuthUrl, googleConfigured } from '@/lib/google';

export async function GET() {
  const user = await getSessionUser();
  if (!user) {
    return NextResponse.redirect(new URL('/admin', process.env.BASE_URL || 'http://localhost:3000'));
  }
  if (!googleConfigured()) {
    return NextResponse.json(
      { error: 'GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET non configurés.' },
      { status: 400 }
    );
  }
  // Le paramètre state (signé) identifie l'utilisateur au retour d'OAuth.
  const state = await new SignJWT({ sub: user.id })
    .setProtectedHeader({ alg: 'HS256' })
    .setExpirationTime('15m')
    .sign(new TextEncoder().encode(process.env.SESSION_SECRET || 'dev-secret'));

  return NextResponse.redirect(googleAuthUrl(state));
}
