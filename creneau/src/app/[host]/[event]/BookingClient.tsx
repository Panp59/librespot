'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { DateTime } from 'luxon';
import type { Question } from '@/lib/utils';

type Props = {
  eventTypeId: string;
  eventName: string;
  durationMin: number;
  questions: Question[];
  collectPhone?: boolean;
  mode: 'book' | 'reschedule';
  manageToken?: string;
};

const COMMON_TIMEZONES = [
  'Europe/Paris',
  'Europe/Brussels',
  'Europe/Zurich',
  'Europe/London',
  'America/New_York',
  'America/Montreal',
  'Africa/Casablanca',
  'Indian/Reunion',
];

const WEEKDAY_LABELS = ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'];

export default function BookingClient({
  eventTypeId,
  eventName,
  durationMin,
  questions,
  collectPhone = false,
  mode,
  manageToken,
}: Props) {
  const detectedTz = useMemo(
    () => Intl.DateTimeFormat().resolvedOptions().timeZone || 'Europe/Paris',
    []
  );
  const [timezone, setTimezone] = useState(detectedTz);
  const [month, setMonth] = useState(() =>
    DateTime.now().setZone(detectedTz).startOf('month')
  );
  const [slots, setSlots] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedDay, setSelectedDay] = useState<string | null>(null);
  const [selectedSlot, setSelectedSlot] = useState<string | null>(null);

  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [phone, setPhone] = useState('');
  const [answers, setAnswers] = useState<Record<string, string>>({});
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');

  const timezones = useMemo(
    () =>
      COMMON_TIMEZONES.includes(detectedTz)
        ? COMMON_TIMEZONES
        : [detectedTz, ...COMMON_TIMEZONES],
    [detectedTz]
  );

  const fetchSlots = useCallback(async () => {
    setLoading(true);
    try {
      const from = DateTime.max(month, DateTime.now().setZone(timezone))
        .startOf('day')
        .toUTC()
        .toISO();
      const to = month.endOf('month').endOf('day').toUTC().toISO();
      const exclude =
        mode === 'reschedule' && manageToken ? `&exclude=${manageToken}` : '';
      const response = await fetch(
        `/api/slots?eventTypeId=${eventTypeId}&from=${encodeURIComponent(from!)}&to=${encodeURIComponent(to!)}${exclude}`
      );
      const data = await response.json();
      setSlots(Array.isArray(data.slots) ? data.slots : []);
    } catch {
      setSlots([]);
    } finally {
      setLoading(false);
    }
  }, [eventTypeId, month, timezone, mode, manageToken]);

  useEffect(() => {
    fetchSlots();
  }, [fetchSlots]);

  // Créneaux groupés par jour (dans le fuseau du visiteur).
  const slotsByDay = useMemo(() => {
    const map = new Map<string, string[]>();
    for (const iso of slots) {
      const key = DateTime.fromISO(iso).setZone(timezone).toISODate()!;
      map.set(key, [...(map.get(key) ?? []), iso]);
    }
    return map;
  }, [slots, timezone]);

  const daySlots = selectedDay ? (slotsByDay.get(selectedDay) ?? []) : [];

  // Grille du mois : lundi = première colonne.
  const gridDays = useMemo(() => {
    const first = month.startOf('month');
    const blanks = first.weekday - 1;
    const total = month.daysInMonth ?? 30;
    return [
      ...Array.from({ length: blanks }, () => null),
      ...Array.from({ length: total }, (_, i) => first.plus({ days: i })),
    ];
  }, [month]);

  async function submit(formEvent: React.FormEvent) {
    formEvent.preventDefault();
    if (!selectedSlot) return;
    setSubmitting(true);
    setError('');
    try {
      const url =
        mode === 'reschedule'
          ? `/api/rdv/${manageToken}/reschedule`
          : '/api/bookings';
      const response = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(
          mode === 'reschedule'
            ? { start: selectedSlot, timezone }
            : {
                eventTypeId,
                start: selectedSlot,
                name,
                email,
                phone,
                timezone,
                answers,
              }
        ),
      });
      const data = await response.json();
      if (!response.ok) {
        throw new Error(data.error || 'Une erreur est survenue.');
      }
      const token = mode === 'reschedule' ? manageToken : data.token;
      window.location.href = `/rdv/${token}?${mode === 'reschedule' ? 'deplace' : 'nouveau'}=1`;
    } catch (submitError) {
      setError(
        submitError instanceof Error
          ? submitError.message
          : 'Une erreur est survenue.'
      );
      setSubmitting(false);
      // Le créneau a pu être pris entre-temps : on rafraîchit.
      fetchSlots();
    }
  }

  // --- Étape 3 : formulaire ---
  if (selectedSlot) {
    const when = DateTime.fromISO(selectedSlot)
      .setZone(timezone)
      .setLocale('fr');
    return (
      <div>
        <button
          type="button"
          onClick={() => setSelectedSlot(null)}
          className="mb-4 text-sm font-medium text-accent-light hover:underline"
        >
          ← Changer de créneau
        </button>
        <div className="mb-6 rounded-xl bg-accent/10 p-4 text-sm">
          <p className="font-semibold">{eventName}</p>
          <p className="mt-1 text-slate-300">
            {when.toFormat("cccc d LLLL yyyy 'à' HH:mm")} ({durationMin} min)
          </p>
        </div>

        <form onSubmit={submit} className="grid gap-4">
          {mode === 'book' && (
            <>
              <div>
                <label className="label" htmlFor="booking-name">
                  Nom complet *
                </label>
                <input
                  id="booking-name"
                  className="input"
                  required
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="Marie Dupont"
                />
              </div>
              <div>
                <label className="label" htmlFor="booking-email">
                  Email *
                </label>
                <input
                  id="booking-email"
                  className="input"
                  type="email"
                  required
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="marie@societe.fr"
                />
              </div>
              {collectPhone && (
                <div>
                  <label className="label" htmlFor="booking-phone">
                    Mobile (pour les rappels SMS)
                  </label>
                  <input
                    id="booking-phone"
                    className="input"
                    type="tel"
                    value={phone}
                    onChange={(e) => setPhone(e.target.value)}
                    placeholder="06 12 34 56 78"
                  />
                </div>
              )}
              {questions.map((question) => (
                <div key={question.id}>
                  <label className="label" htmlFor={`q-${question.id}`}>
                    {question.label} {question.required && '*'}
                  </label>
                  {question.type === 'textarea' ? (
                    <textarea
                      id={`q-${question.id}`}
                      className="input min-h-24"
                      required={question.required}
                      value={answers[question.id] ?? ''}
                      onChange={(e) =>
                        setAnswers({ ...answers, [question.id]: e.target.value })
                      }
                    />
                  ) : question.type === 'select' ? (
                    <select
                      id={`q-${question.id}`}
                      className="input"
                      required={question.required}
                      value={answers[question.id] ?? ''}
                      onChange={(e) =>
                        setAnswers({ ...answers, [question.id]: e.target.value })
                      }
                    >
                      <option value="">Choisir…</option>
                      {(question.options ?? []).map((option) => (
                        <option key={option} value={option}>
                          {option}
                        </option>
                      ))}
                    </select>
                  ) : (
                    <input
                      id={`q-${question.id}`}
                      className="input"
                      type={question.type === 'phone' ? 'tel' : 'text'}
                      required={question.required}
                      value={answers[question.id] ?? ''}
                      onChange={(e) =>
                        setAnswers({ ...answers, [question.id]: e.target.value })
                      }
                    />
                  )}
                </div>
              ))}
            </>
          )}

          {error && (
            <p className="rounded-xl bg-red-500/10 p-3 text-sm text-red-300">
              {error}
            </p>
          )}

          <button type="submit" className="btn-primary" disabled={submitting}>
            {submitting
              ? 'Un instant…'
              : mode === 'reschedule'
                ? 'Confirmer le nouveau créneau'
                : 'Confirmer le rendez-vous'}
          </button>
        </form>
      </div>
    );
  }

  // --- Étapes 1 et 2 : calendrier + créneaux ---
  return (
    <div className="grid gap-8 md:grid-cols-[1fr_220px]">
      <div>
        <div className="mb-4 flex items-center justify-between">
          <h2 className="font-semibold capitalize">
            {month.setLocale('fr').toFormat('LLLL yyyy')}
          </h2>
          <div className="flex gap-1">
            <button
              type="button"
              onClick={() => setMonth(month.minus({ months: 1 }))}
              disabled={month <= DateTime.now().setZone(timezone).startOf('month')}
              className="btn-secondary !px-3 !py-1.5"
              aria-label="Mois précédent"
            >
              ←
            </button>
            <button
              type="button"
              onClick={() => setMonth(month.plus({ months: 1 }))}
              className="btn-secondary !px-3 !py-1.5"
              aria-label="Mois suivant"
            >
              →
            </button>
          </div>
        </div>

        <div className="grid grid-cols-7 gap-1 text-center">
          {WEEKDAY_LABELS.map((label) => (
            <div key={label} className="py-1 text-xs font-medium uppercase text-slate-400">
              {label}
            </div>
          ))}
          {gridDays.map((day, index) =>
            day === null ? (
              <div key={`blank-${index}`} />
            ) : (
              (() => {
                const key = day.toISODate()!;
                const hasSlots = slotsByDay.has(key);
                const isSelected = selectedDay === key;
                return (
                  <button
                    key={key}
                    type="button"
                    disabled={!hasSlots}
                    onClick={() => setSelectedDay(key)}
                    className={`aspect-square rounded-xl text-sm font-medium transition
                      ${
                        isSelected
                          ? 'bg-accent text-white'
                          : hasSlots
                            ? 'bg-accent/10 text-accent-light hover:bg-accent/20'
                            : 'text-slate-600'
                      }`}
                  >
                    {day.day}
                  </button>
                );
              })()
            )
          )}
        </div>

        <div className="mt-5">
          <label className="label" htmlFor="tz-select">
            Fuseau horaire
          </label>
          <select
            id="tz-select"
            className="input"
            value={timezone}
            onChange={(e) => {
              setTimezone(e.target.value);
              setSelectedDay(null);
            }}
          >
            {timezones.map((tz) => (
              <option key={tz} value={tz}>
                {tz.replace(/_/g, ' ')}
              </option>
            ))}
          </select>
        </div>
      </div>

      <div>
        <h3 className="mb-3 text-sm font-semibold text-slate-200">
          {selectedDay
            ? DateTime.fromISO(selectedDay).setLocale('fr').toFormat('cccc d LLLL')
            : 'Choisissez un jour'}
        </h3>
        {loading ? (
          <p className="text-sm text-slate-400">Chargement…</p>
        ) : selectedDay ? (
          <div className="grid max-h-80 gap-2 overflow-y-auto pr-1">
            {daySlots.map((iso) => (
              <button
                key={iso}
                type="button"
                onClick={() => setSelectedSlot(iso)}
                className="rounded-xl border border-accent/40 px-3 py-2 text-sm font-semibold text-accent-light transition hover:bg-accent hover:text-white"
              >
                {DateTime.fromISO(iso).setZone(timezone).toFormat('HH:mm')}
              </button>
            ))}
          </div>
        ) : (
          <p className="text-sm text-slate-400">
            Les jours disponibles sont surlignés.
          </p>
        )}
      </div>
    </div>
  );
}
