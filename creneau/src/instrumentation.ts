export async function register() {
  if (process.env.NEXT_RUNTIME === 'nodejs') {
    const { startReminderLoop } = await import('./lib/reminders');
    startReminderLoop();
  }
}
