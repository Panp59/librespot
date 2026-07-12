import { NextRequest, NextResponse } from 'next/server';
import { jwtVerify } from 'jose';

// Protège /admin/* (sauf la page de connexion /admin elle-même).
export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;
  if (pathname === '/admin') return NextResponse.next();

  const token = request.cookies.get('creneau_session')?.value;
  if (token) {
    try {
      await jwtVerify(
        token,
        new TextEncoder().encode(process.env.SESSION_SECRET || 'dev-secret')
      );
      return NextResponse.next();
    } catch {
      // jeton invalide → redirection connexion
    }
  }
  const loginUrl = request.nextUrl.clone();
  loginUrl.pathname = '/admin';
  return NextResponse.redirect(loginUrl);
}

export const config = {
  matcher: ['/admin/:path+'],
};
