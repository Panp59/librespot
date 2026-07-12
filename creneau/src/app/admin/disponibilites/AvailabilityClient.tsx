'use client';

import { useState } from 'react';

type Window = { weekday: number; startMinute: number; endMinute: number };

const DAYS = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];

function toTime(minute: number): string {
  return `${String(Math.floor(minute / 60)).padStart(2, '0')}:${String(minute % 60).padStart(2, '0')}`;
}

function toMinute(time: string): number {
  const [h, m] = time.split(':').map(Number);
  return (h || 0) * 60 + (m || 0);
}

export default function AvailabilityClient({ initial }: { initial: Window[] }) {
  const [windows, setWindows] = useState<Window[]>(initial);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');

  function update(index: number, patch: Partial<Window>) {
    setWindows(windows.map((w, i) => (i === index ? { ...w, ...patch } : w)));
  }

  async function save() {
    setBusy(true);
    setMessage('');
    const valid = windows.filter((w) => w.endMinute > w.startMinute);
    const response = await fetch('/api/admin/availability', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ windows: valid }),
    });
    setMessage(response.ok ? '✅ Disponibilités enregistrées.' : '⚠️ Enregistrement impossible.');
    setBusy(false);
  }

  return (
    <div className="card p-6">
      <div className="grid gap-5">
        {DAYS.map((label, dayIndex) => {
          const weekday = dayIndex + 1; // 1 = lundi (ISO)
          const dayWindows = windows
            .map((w, index) => ({ ...w, index }))
            .filter((w) => w.weekday === weekday);
          return (
            <div key={weekday} className="flex flex-wrap items-start gap-3">
              <span className="w-24 pt-2 text-sm font-medium">{label}</span>
              <div className="flex flex-1 flex-col gap-2">
                {dayWindows.length === 0 && (
                  <span className="pt-2 text-sm text-slate-400">Indisponible</span>
                )}
                {dayWindows.map((w) => (
                  <div key={w.index} className="flex items-center gap-2">
                    <input
                      type="time"
                      className="input !w-auto"
                      value={toTime(w.startMinute)}
                      onChange={(e) => update(w.index, { startMinute: toMinute(e.target.value) })}
                    />
                    <span className="text-slate-400">→</span>
                    <input
                      type="time"
                      className="input !w-auto"
                      value={toTime(w.endMinute)}
                      onChange={(e) => update(w.index, { endMinute: toMinute(e.target.value) })}
                    />
                    <button
                      type="button"
                      className="text-sm text-red-500 hover:underline"
                      onClick={() => setWindows(windows.filter((_, i) => i !== w.index))}
                    >
                      Supprimer
                    </button>
                  </div>
                ))}
              </div>
              <button
                type="button"
                className="btn-secondary !py-1.5 text-xs"
                onClick={() =>
                  setWindows([
                    ...windows,
                    { weekday, startMinute: 9 * 60, endMinute: 17 * 60 },
                  ])
                }
              >
                ＋ Plage
              </button>
            </div>
          );
        })}
      </div>

      <div className="mt-6 flex items-center gap-4">
        <button type="button" className="btn-primary" onClick={save} disabled={busy}>
          {busy ? 'Enregistrement…' : 'Enregistrer'}
        </button>
        {message && <span className="text-sm">{message}</span>}
      </div>
    </div>
  );
}
