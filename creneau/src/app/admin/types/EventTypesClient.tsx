'use client';

import { useState } from 'react';

type EventTypeData = {
  id?: string;
  name: string;
  slug: string;
  description: string;
  durationMin: number;
  bufferBeforeMin: number;
  bufferAfterMin: number;
  minNoticeMin: number;
  maxDaysAhead: number;
  color: string;
  locationType: string;
  locationDetail: string;
  collectPhone: boolean;
  questions: string;
  reminders: string;
  active: boolean;
};

type QuestionDraft = {
  id: string;
  label: string;
  type: string;
  required: boolean;
  options?: string[];
};

const EMPTY: EventTypeData = {
  name: '',
  slug: '',
  description: '',
  durationMin: 30,
  bufferBeforeMin: 0,
  bufferAfterMin: 10,
  minNoticeMin: 240,
  maxDaysAhead: 60,
  color: '#3E63F5',
  locationType: 'MEET',
  locationDetail: '',
  collectPhone: true,
  questions: '[]',
  reminders: '[1440,60]',
  active: true,
};

function parseDraftQuestions(json: string): QuestionDraft[] {
  try {
    const parsed = JSON.parse(json);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

export default function EventTypesClient({
  hostSlug,
  initial,
}: {
  hostSlug: string;
  initial: EventTypeData[];
}) {
  const [items, setItems] = useState(initial);
  const [editing, setEditing] = useState<EventTypeData | null>(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  async function save() {
    if (!editing) return;
    setBusy(true);
    setError('');
    const isNew = !editing.id;
    const response = await fetch(
      isNew ? '/api/admin/event-types' : `/api/admin/event-types/${editing.id}`,
      {
        method: isNew ? 'POST' : 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(editing),
      }
    );
    const data = await response.json();
    if (!response.ok) {
      setError(data.error || 'Enregistrement impossible.');
      setBusy(false);
      return;
    }
    if (isNew) {
      setItems([...items, data.eventType]);
    } else {
      setItems(items.map((item) => (item.id === editing.id ? data.eventType : item)));
    }
    setEditing(null);
    setBusy(false);
  }

  async function remove(id: string) {
    if (!window.confirm('Supprimer ce type de rendez-vous ? Les RDV passés restent conservés.')) return;
    const response = await fetch(`/api/admin/event-types/${id}`, { method: 'DELETE' });
    if (response.ok) setItems(items.filter((item) => item.id !== id));
  }

  // --- Formulaire d'édition ---
  if (editing) {
    const questions = parseDraftQuestions(editing.questions);
    const reminders = (() => {
      try {
        const parsed = JSON.parse(editing.reminders);
        return Array.isArray(parsed) ? parsed.join(', ') : '';
      } catch {
        return '';
      }
    })();

    const setQuestion = (index: number, patch: Partial<QuestionDraft>) => {
      const next = questions.map((question, i) =>
        i === index ? { ...question, ...patch } : question
      );
      setEditing({ ...editing, questions: JSON.stringify(next) });
    };

    return (
      <div className="card p-6">
        <h2 className="mb-5 text-lg font-semibold">
          {editing.id ? 'Modifier le type de rendez-vous' : 'Nouveau type de rendez-vous'}
        </h2>
        <div className="grid gap-4 md:grid-cols-2">
          <div>
            <label className="label">Nom *</label>
            <input
              className="input"
              value={editing.name}
              onChange={(e) => setEditing({ ...editing, name: e.target.value })}
              placeholder="Démo (30 min)"
            />
          </div>
          <div>
            <label className="label">Adresse (slug)</label>
            <input
              className="input"
              value={editing.slug}
              onChange={(e) => setEditing({ ...editing, slug: e.target.value })}
              placeholder="demo-30 (auto si vide)"
            />
          </div>
          <div className="md:col-span-2">
            <label className="label">Description</label>
            <textarea
              className="input min-h-20"
              value={editing.description}
              onChange={(e) => setEditing({ ...editing, description: e.target.value })}
            />
          </div>
          <div>
            <label className="label">Durée (minutes)</label>
            <input
              className="input"
              type="number"
              min={5}
              value={editing.durationMin}
              onChange={(e) => setEditing({ ...editing, durationMin: Number(e.target.value) })}
            />
          </div>
          <div>
            <label className="label">Couleur</label>
            <input
              className="h-11 w-full cursor-pointer rounded-xl border border-white/15"
              type="color"
              value={editing.color}
              onChange={(e) => setEditing({ ...editing, color: e.target.value })}
            />
          </div>
          <div>
            <label className="label">Tampon avant (min)</label>
            <input
              className="input"
              type="number"
              min={0}
              value={editing.bufferBeforeMin}
              onChange={(e) => setEditing({ ...editing, bufferBeforeMin: Number(e.target.value) })}
            />
          </div>
          <div>
            <label className="label">Tampon après (min)</label>
            <input
              className="input"
              type="number"
              min={0}
              value={editing.bufferAfterMin}
              onChange={(e) => setEditing({ ...editing, bufferAfterMin: Number(e.target.value) })}
            />
          </div>
          <div>
            <label className="label">Préavis minimal (min)</label>
            <input
              className="input"
              type="number"
              min={0}
              value={editing.minNoticeMin}
              onChange={(e) => setEditing({ ...editing, minNoticeMin: Number(e.target.value) })}
            />
          </div>
          <div>
            <label className="label">Réservable jusqu'à (jours)</label>
            <input
              className="input"
              type="number"
              min={1}
              value={editing.maxDaysAhead}
              onChange={(e) => setEditing({ ...editing, maxDaysAhead: Number(e.target.value) })}
            />
          </div>
          <div>
            <label className="label">Lieu</label>
            <select
              className="input"
              value={editing.locationType}
              onChange={(e) => setEditing({ ...editing, locationType: e.target.value })}
            >
              <option value="MEET">Visio (lien Meet automatique)</option>
              <option value="PHONE">Téléphone</option>
              <option value="ADDRESS">Sur place (adresse)</option>
              <option value="CUSTOM">Autre (texte libre)</option>
            </select>
          </div>
          {(editing.locationType === 'ADDRESS' || editing.locationType === 'CUSTOM') && (
            <div>
              <label className="label">Détail du lieu</label>
              <input
                className="input"
                value={editing.locationDetail}
                onChange={(e) => setEditing({ ...editing, locationDetail: e.target.value })}
              />
            </div>
          )}
          <div className="flex items-end pb-2">
            <label className="flex items-center gap-2 text-sm font-medium">
              <input
                type="checkbox"
                checked={editing.collectPhone}
                onChange={(e) => setEditing({ ...editing, collectPhone: e.target.checked })}
              />
              Demander le mobile (rappels SMS)
            </label>
          </div>
          <div>
            <label className="label">Rappels avant RDV (minutes, séparés par des virgules)</label>
            <input
              className="input"
              value={reminders}
              placeholder="1440, 60"
              onChange={(e) => {
                const values = e.target.value
                  .split(',')
                  .map((v) => parseInt(v.trim(), 10))
                  .filter((n) => Number.isFinite(n) && n > 0);
                setEditing({ ...editing, reminders: JSON.stringify(values) });
              }}
            />
          </div>
        </div>

        {/* Questions personnalisées */}
        <div className="mt-6">
          <div className="mb-2 flex items-center justify-between">
            <h3 className="font-semibold">Questions posées à la réservation</h3>
            <button
              type="button"
              className="btn-secondary !py-1.5 text-xs"
              onClick={() =>
                setEditing({
                  ...editing,
                  questions: JSON.stringify([
                    ...questions,
                    { id: `q${Date.now()}`, label: '', type: 'text', required: false },
                  ]),
                })
              }
            >
              ＋ Ajouter une question
            </button>
          </div>
          <div className="grid gap-2">
            {questions.map((question, index) => (
              <div key={question.id} className="flex flex-wrap items-center gap-2 rounded-xl bg-white/5 p-3">
                <input
                  className="input !w-auto flex-1"
                  placeholder="Libellé de la question"
                  value={question.label}
                  onChange={(e) => setQuestion(index, { label: e.target.value })}
                />
                <select
                  className="input !w-auto"
                  value={question.type}
                  onChange={(e) => setQuestion(index, { type: e.target.value })}
                >
                  <option value="text">Texte court</option>
                  <option value="textarea">Texte long</option>
                  <option value="phone">Téléphone</option>
                  <option value="select">Liste de choix</option>
                </select>
                {question.type === 'select' && (
                  <input
                    className="input !w-auto flex-1"
                    placeholder="Choix séparés par des virgules"
                    value={(question.options ?? []).join(', ')}
                    onChange={(e) =>
                      setQuestion(index, {
                        options: e.target.value.split(',').map((o) => o.trim()).filter(Boolean),
                      })
                    }
                  />
                )}
                <label className="flex items-center gap-1.5 text-sm">
                  <input
                    type="checkbox"
                    checked={question.required}
                    onChange={(e) => setQuestion(index, { required: e.target.checked })}
                  />
                  Obligatoire
                </label>
                <button
                  type="button"
                  className="text-sm text-red-400 hover:underline"
                  onClick={() =>
                    setEditing({
                      ...editing,
                      questions: JSON.stringify(questions.filter((_, i) => i !== index)),
                    })
                  }
                >
                  Supprimer
                </button>
              </div>
            ))}
            {questions.length === 0 && (
              <p className="text-sm text-slate-400">
                Aucune question : seuls le nom et l'email seront demandés.
              </p>
            )}
          </div>
        </div>

        {error && <p className="mt-4 rounded-xl bg-red-500/10 p-3 text-sm text-red-300">{error}</p>}

        <div className="mt-6 flex gap-3">
          <button type="button" className="btn-primary" onClick={save} disabled={busy || !editing.name}>
            {busy ? 'Enregistrement…' : 'Enregistrer'}
          </button>
          <button type="button" className="btn-secondary" onClick={() => setEditing(null)} disabled={busy}>
            Annuler
          </button>
        </div>
      </div>
    );
  }

  // --- Liste ---
  return (
    <div className="grid gap-4">
      <div>
        <button type="button" className="btn-primary" onClick={() => setEditing({ ...EMPTY })}>
          ＋ Nouveau type de rendez-vous
        </button>
      </div>
      {items.map((item) => (
        <div key={item.id} className="card flex flex-wrap items-center gap-4 p-5">
          <span className="h-3 w-3 shrink-0 rounded-full" style={{ backgroundColor: item.color }} />
          <div className="min-w-0 flex-1">
            <p className="font-semibold">
              {item.name}
              {!item.active && (
                <span className="ml-2 rounded-full bg-white/10 px-2 py-0.5 text-xs text-slate-400">
                  désactivé
                </span>
              )}
            </p>
            <p className="text-sm text-slate-400">
              {item.durationMin} min · /{hostSlug}/{item.slug}
            </p>
          </div>
          <a
            className="btn-secondary !py-1.5 text-xs"
            href={`/${hostSlug}/${item.slug}`}
            target="_blank"
            rel="noreferrer"
          >
            Voir ↗
          </a>
          <button type="button" className="btn-secondary !py-1.5 text-xs" onClick={() => setEditing({ ...item })}>
            Modifier
          </button>
          <button type="button" className="btn-danger !py-1.5 text-xs" onClick={() => item.id && remove(item.id)}>
            Supprimer
          </button>
        </div>
      ))}
      {items.length === 0 && (
        <p className="text-slate-400">Aucun type de rendez-vous pour l'instant.</p>
      )}
    </div>
  );
}
