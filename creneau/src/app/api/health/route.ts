import { NextResponse } from 'next/server';
import { runHealthChecks } from '@/lib/health';

/** Contrôle de santé complet, prêt pour un moniteur externe
 *  (UptimeRobot, Better Stack…) : 200 si tout va bien, 503 si panne. */
export async function GET() {
  const report = await runHealthChecks();
  return NextResponse.json(report, {
    status: report.status === 'fail' ? 503 : 200,
  });
}
