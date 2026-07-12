import { redirect } from 'next/navigation';
import { getSessionUser } from '@/lib/auth';
import LoginForm from './LoginForm';

export const dynamic = 'force-dynamic';

export default async function AdminLoginPage() {
  const user = await getSessionUser();
  if (user) redirect('/admin/dashboard');

  return (
    <main className="flex min-h-screen items-center justify-center px-4">
      <div className="card w-full max-w-sm p-8">
        <h1 className="text-xl font-bold">Créneau — Administration</h1>
        <p className="mt-1 text-sm text-slate-500">Connectez-vous pour continuer.</p>
        <div className="mt-6">
          <LoginForm />
        </div>
      </div>
    </main>
  );
}
