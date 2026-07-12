'use client';

import { useState } from 'react';

type Props = {
  profile: { name: string; slug: string; timezone: string; videoLink: string };
  isAdmin: boolean;
  googleAvailable: boolean;
  googleConnected: boolean;
  settings: { orgName: string; accentColor: string; logoUrl: string; welcomeText: string };
  users: { id: string; name: string; email: string; slug: string; isAdmin: boolean }[];
  baseUrl: string;
};

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="card p-6">
      <h2 className="mb-4 text-lg font-semibold">{title}</h2>
      {children}
    </section>
  );
}

export default function SettingsClient(props: Props) {
  const [profile, setProfile] = useState({ ...props.profile, password: '' });
  const [settings, setSettings] = useState(props.settings);
  const [users, setUsers] = useState(props.users);
  const [newUser, setNewUser] = useState({ name: '', email: '', password: '' });
  const [message, setMessage] = useState('');

  async function post(url: string, body: unknown, method = 'PUT'): Promise<boolean> {
    setMessage('');
    const response = await fetch(url, {
      method,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const data = await response.json().catch(() => ({}));
    setMessage(response.ok ? '✅ Enregistré.' : `⚠️ ${data.error || 'Erreur.'}`);
    return response.ok;
  }

  const embedCode = `<iframe src="${props.baseUrl}/${profile.slug}/VOTRE-TYPE-DE-RDV?embed=1"\n  style="width:100%;min-height:680px;border:none;border-radius:16px"\n  title="Prendre rendez-vous"></iframe>`;

  return (
    <div className="grid gap-6">
      {message && <p className="rounded-xl bg-white/10 p-3 text-sm">{message}</p>}

      <Section title="Mon profil">
        <div className="grid gap-4 md:grid-cols-2">
          <div>
            <label className="label">Nom affiché</label>
            <input
              className="input"
              value={profile.name}
              onChange={(e) => setProfile({ ...profile, name: e.target.value })}
            />
          </div>
          <div>
            <label className="label">Adresse de ma page (slug)</label>
            <input
              className="input"
              value={profile.slug}
              onChange={(e) => setProfile({ ...profile, slug: e.target.value })}
            />
          </div>
          <div>
            <label className="label">Fuseau horaire</label>
            <select
              className="input"
              value={profile.timezone}
              onChange={(e) => setProfile({ ...profile, timezone: e.target.value })}
            >
              {['Europe/Paris', 'Europe/Brussels', 'Europe/Zurich', 'Europe/London', 'Indian/Reunion', 'America/Montreal'].map(
                (tz) => (
                  <option key={tz} value={tz}>
                    {tz}
                  </option>
                )
              )}
            </select>
          </div>
          <div>
            <label className="label">Lien visio de secours (si Google non connecté)</label>
            <input
              className="input"
              value={profile.videoLink}
              placeholder="https://meet.google.com/xxx-xxxx-xxx"
              onChange={(e) => setProfile({ ...profile, videoLink: e.target.value })}
            />
          </div>
          <div>
            <label className="label">Nouveau mot de passe (laisser vide pour conserver)</label>
            <input
              className="input"
              type="password"
              value={profile.password}
              onChange={(e) => setProfile({ ...profile, password: e.target.value })}
            />
          </div>
        </div>
        <button type="button" className="btn-primary mt-4" onClick={() => post('/api/admin/profile', profile)}>
          Enregistrer mon profil
        </button>
      </Section>

      <Section title="Google Calendar">
        {!props.googleAvailable ? (
          <p className="text-sm text-slate-300">
            Renseigne <code className="rounded bg-white/10 px-1">GOOGLE_CLIENT_ID</code> et{' '}
            <code className="rounded bg-white/10 px-1">GOOGLE_CLIENT_SECRET</code> dans la
            configuration du serveur pour activer la synchronisation (voir README).
          </p>
        ) : props.googleConnected ? (
          <div className="flex items-center justify-between">
            <p className="text-sm text-green-300">
              ✅ Connecté — vos occupations bloquent les créneaux et les RDV créent un
              événement avec lien Meet.
            </p>
            <a className="btn-secondary" href="/api/google/connect">
              Reconnecter
            </a>
          </div>
        ) : (
          <div className="flex items-center justify-between">
            <p className="text-sm text-slate-300">
              Connecte ton agenda pour bloquer automatiquement tes créneaux occupés et générer
              les liens Meet.
            </p>
            <a className="btn-primary" href="/api/google/connect">
              Connecter Google
            </a>
          </div>
        )}
      </Section>

      <Section title="Intégrer sur votre site (gmao.org…)">
        <p className="mb-3 text-sm text-slate-300">
          Colle ce code dans ta page — remplace <code className="rounded bg-white/10 px-1">VOTRE-TYPE-DE-RDV</code>{' '}
          par le slug voulu (visible dans « Types de RDV ») :
        </p>
        <pre className="overflow-x-auto rounded-xl bg-black/50 p-4 text-xs leading-relaxed text-slate-100">
          {embedCode}
        </pre>
      </Section>

      {props.isAdmin && (
        <>
          <Section title="Apparence (pages publiques)">
            <div className="grid gap-4 md:grid-cols-2">
              <div>
                <label className="label">Nom de l'organisation</label>
                <input
                  className="input"
                  value={settings.orgName}
                  onChange={(e) => setSettings({ ...settings, orgName: e.target.value })}
                />
              </div>
              <div>
                <label className="label">Couleur d'accent</label>
                <input
                  type="color"
                  className="h-11 w-full cursor-pointer rounded-xl border border-white/15"
                  value={settings.accentColor}
                  onChange={(e) => setSettings({ ...settings, accentColor: e.target.value })}
                />
              </div>
              <div>
                <label className="label">URL du logo (optionnel)</label>
                <input
                  className="input"
                  value={settings.logoUrl}
                  placeholder="https://gmao.org/logo.png"
                  onChange={(e) => setSettings({ ...settings, logoUrl: e.target.value })}
                />
              </div>
              <div>
                <label className="label">Texte d'accueil</label>
                <input
                  className="input"
                  value={settings.welcomeText}
                  onChange={(e) => setSettings({ ...settings, welcomeText: e.target.value })}
                />
              </div>
            </div>
            <button
              type="button"
              className="btn-primary mt-4"
              onClick={async () => {
                if (await post('/api/admin/settings', settings)) window.location.reload();
              }}
            >
              Enregistrer l'apparence
            </button>
          </Section>

          <Section title="Hôtes (comptes)">
            <ul className="mb-5 grid gap-2">
              {users.map((user) => (
                <li key={user.id} className="flex items-center gap-3 rounded-xl bg-white/5 p-3 text-sm">
                  <span className="font-medium">{user.name}</span>
                  <span className="text-slate-400">{user.email}</span>
                  <span className="text-slate-400">/{user.slug}</span>
                  {user.isAdmin && (
                    <span className="rounded-full bg-accent/10 px-2 py-0.5 text-xs font-medium text-accent-light">
                      admin
                    </span>
                  )}
                </li>
              ))}
            </ul>
            <div className="grid gap-3 md:grid-cols-3">
              <input
                className="input"
                placeholder="Nom (ex. Le Commercial)"
                value={newUser.name}
                onChange={(e) => setNewUser({ ...newUser, name: e.target.value })}
              />
              <input
                className="input"
                type="email"
                placeholder="email@adti.fr"
                value={newUser.email}
                onChange={(e) => setNewUser({ ...newUser, email: e.target.value })}
              />
              <input
                className="input"
                type="password"
                placeholder="Mot de passe"
                value={newUser.password}
                onChange={(e) => setNewUser({ ...newUser, password: e.target.value })}
              />
            </div>
            <button
              type="button"
              className="btn-primary mt-3"
              disabled={!newUser.name || !newUser.email || !newUser.password}
              onClick={async () => {
                const ok = await post('/api/admin/users', newUser, 'POST');
                if (ok) {
                  const response = await fetch('/api/admin/users');
                  const data = await response.json();
                  setUsers(data.users);
                  setNewUser({ name: '', email: '', password: '' });
                }
              }}
            >
              Ajouter un hôte
            </button>
          </Section>
        </>
      )}
    </div>
  );
}
