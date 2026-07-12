'use client';

import { useState } from 'react';

export default function CancelButton({ token }: { token: string }) {
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);

  async function cancel() {
    setBusy(true);
    await fetch(`/api/rdv/${token}/cancel`, { method: 'POST' });
    window.location.href = `/rdv/${token}`;
  }

  if (!confirming) {
    return (
      <button type="button" className="btn-danger" onClick={() => setConfirming(true)}>
        Annuler le rendez-vous
      </button>
    );
  }
  return (
    <span className="flex items-center gap-2">
      <button type="button" className="btn-danger" onClick={cancel} disabled={busy}>
        {busy ? 'Annulation…' : 'Oui, annuler'}
      </button>
      <button
        type="button"
        className="btn-secondary"
        onClick={() => setConfirming(false)}
        disabled={busy}
      >
        Non
      </button>
    </span>
  );
}
