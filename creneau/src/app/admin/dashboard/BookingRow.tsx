'use client';

import { useState } from 'react';

type Props = {
  id: string;
  when: string;
  eventName: string;
  color: string;
  inviteeName: string;
  inviteeEmail: string;
  answers: string;
  meetLink: string;
};

export default function BookingRow(props: Props) {
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [cancelled, setCancelled] = useState(false);

  const answers: Record<string, string> = (() => {
    try {
      return JSON.parse(props.answers);
    } catch {
      return {};
    }
  })();

  async function cancel() {
    if (!window.confirm(`Annuler le RDV avec ${props.inviteeName} ? Un email lui sera envoyé.`)) {
      return;
    }
    setBusy(true);
    const response = await fetch(`/api/admin/bookings/${props.id}/cancel`, { method: 'POST' });
    if (response.ok) setCancelled(true);
    setBusy(false);
  }

  if (cancelled) {
    return (
      <div className="p-4 text-sm text-slate-400 line-through">
        {props.when} — {props.eventName} avec {props.inviteeName} (annulé)
      </div>
    );
  }

  return (
    <div className="p-4">
      <div className="flex flex-wrap items-center gap-3">
        <span className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ backgroundColor: props.color }} />
        <div className="min-w-0 flex-1">
          <p className="font-medium">{props.when}</p>
          <p className="text-sm text-slate-400">
            {props.eventName} · {props.inviteeName} ({props.inviteeEmail})
          </p>
        </div>
        {props.meetLink && (
          <a href={props.meetLink} target="_blank" rel="noreferrer" className="btn-secondary !py-1.5 text-xs">
            Lien visio ↗
          </a>
        )}
        {Object.keys(answers).length > 0 && (
          <button type="button" className="btn-secondary !py-1.5 text-xs" onClick={() => setOpen(!open)}>
            {open ? 'Masquer' : 'Détails'}
          </button>
        )}
        <button type="button" className="btn-danger !py-1.5 text-xs" onClick={cancel} disabled={busy}>
          Annuler
        </button>
      </div>
      {open && (
        <dl className="mt-3 grid gap-1 rounded-xl bg-white/5 p-3 text-sm">
          {Object.entries(answers).map(([key, value]) => (
            <div key={key} className="flex gap-2">
              <dt className="font-medium text-slate-300">{key} :</dt>
              <dd className="text-white">{value || '—'}</dd>
            </div>
          ))}
        </dl>
      )}
    </div>
  );
}
