'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';

const LINKS = [
  { href: '/admin/dashboard', label: 'Rendez-vous' },
  { href: '/admin/types', label: 'Types de RDV' },
  { href: '/admin/disponibilites', label: 'Disponibilités' },
  { href: '/admin/reglages', label: 'Réglages' },
];

export default function AdminNav({ userName }: { userName: string }) {
  const pathname = usePathname();

  async function logout() {
    await fetch('/api/auth/logout', { method: 'POST' });
    window.location.href = '/admin';
  }

  return (
    <header className="border-b border-white/10 bg-[#0d1626]/90 backdrop-blur">
      <div className="mx-auto flex max-w-5xl flex-wrap items-center gap-4 px-4 py-3">
        <span className="font-bold text-accent-light">Créneau</span>
        <nav className="flex flex-1 flex-wrap gap-1">
          {LINKS.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className={`rounded-lg px-3 py-1.5 text-sm font-medium transition ${
                pathname.startsWith(link.href)
                  ? 'bg-accent/10 text-accent'
                  : 'text-slate-300 hover:bg-white/10'
              }`}
            >
              {link.label}
            </Link>
          ))}
        </nav>
        <span className="text-sm text-slate-400">{userName}</span>
        <button
          type="button"
          onClick={logout}
          className="text-sm font-medium text-slate-400 hover:text-white"
        >
          Déconnexion
        </button>
      </div>
    </header>
  );
}
