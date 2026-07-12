import { NextRequest, NextResponse } from 'next/server';
import { jwtVerify } from 'jose';
import { db } from '@/lib/db';
import { exchangeCode } from '@/lib/google';
import { baseUrl } from '@/lib/utils';

export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get('code');
  const state = request.nextUrl.searchParams.get('state');
  const fail = () => NextResponse.redirect(`${baseUrl()}/admin/reglages?google=erreur`);

  if (!code || !state) return fail();

  let userId: string;
  try {
    const { payload } = await jwtVerify(
      state,
      new TextEncoder().encode(process.env.SESSION_SECRET || 'dev-secret')
    );
    userId = payload.sub as string;
  } catch {
    return fail();
  }

  try {
    const tokens = await exchangeCode(code);
    await db.user.update({
      where: { id: userId },
      data: { googleTokens: JSON.stringify(tokens) },
    });
  } catch (error) {
    console.error('Échange OAuth Google en échec:', error);
    return fail();
  }

  return NextResponse.redirect(`${baseUrl()}/admin/reglages?google=ok`);
}
