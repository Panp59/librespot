# Créneau 🗓️

Clone léger de Calendly, en **français** et auto-hébergé : vos prospects et
clients réservent un rendez-vous en ligne (démo, suivi…), l'événement se crée
dans votre Google Calendar avec un **lien Meet automatique**, et tout le monde
reçoit confirmations et **rappels par email**. Un seul conteneur Docker, une
base SQLite, aucune dépendance externe obligatoire.

## Fonctionnalités

- **Pages publiques élégantes** : `/{hôte}` liste les types de RDV,
  `/{hôte}/{type}` affiche le calendrier et les créneaux. Fuseau horaire du
  visiteur détecté automatiquement (dates affichées en français).
- **Multi-hôtes** : chaque hôte (toi, le commercial…) a sa page, ses types de
  RDV, ses disponibilités hebdomadaires et son compte Google.
- **Types de RDV paramétrables** : durée, tampons avant/après, préavis
  minimal, horizon de réservation, couleur, lieu (visio Meet auto, téléphone,
  adresse, libre), **questions personnalisées** (texte, texte long,
  téléphone, liste de choix, obligatoires ou non), rappels configurables.
- **Google Calendar** (optionnel) : vos événements existants bloquent les
  créneaux (free/busy), chaque réservation crée un événement avec les
  participants et un lien **Google Meet**. Sans Google : disponibilités
  internes + lien visio statique de secours.
- **Emails** : confirmation (avec invitation .ics), annulation,
  reprogrammation, et **rappels automatiques** (ex. 24 h et 1 h avant,
  réglable par type de RDV). Sans SMTP configuré, les emails sont journalisés.
- **SMS** (en plus des emails) : confirmation, rappels, annulation,
  déplacement — envoyés au mobile de l'invité (champ optionnel du formulaire,
  numéros normalisés au format +33). Fournisseurs : **Brevo** ou **OVH SMS**.
- **Surveillance intégrée** : contrôle automatique toutes les 10 minutes que
  la réservation fonctionne vraiment — base de données, calcul des créneaux
  (alerte si plus aucun créneau réservable sous 14 jours !), SMTP, accès
  Google Calendar de chaque hôte, boucle de rappels. **Alerte email/SMS de
  l'admin en cas de panne** (avec anti-spam 6 h) + message de rétablissement.
  État visible en haut du tableau de bord admin, et endpoint `/api/health`
  (200/503) prêt pour un moniteur externe type UptimeRobot.
- **L'invité gère son RDV** : lien unique pour annuler ou reprogrammer.
- **Admin en français** : tableau des RDV à venir (réponses au formulaire,
  lien visio, annulation), éditeur de types de RDV, grille de disponibilités,
  réglages (nom, logo, couleur d'accent, texte d'accueil), gestion des hôtes.
- **Intégrable sur votre site** (gmao.org…) : mode `?embed=1` + snippet
  iframe fourni dans les réglages.

## Démarrage rapide (Docker)

```bash
cd creneau
cp .env.example .env       # renseigne au minimum SESSION_SECRET et ADMIN_PASSWORD
docker compose up -d --build
```

L'app écoute sur `http://localhost:3000`. Au premier démarrage, la base est
créée dans le volume `creneau-data` et le compte admin est créé à partir de
`ADMIN_EMAIL` / `ADMIN_PASSWORD`. Connecte-toi sur `/admin`.

En production : mets `BASE_URL=https://rdv.tondomaine.fr` et place un reverse
proxy (Caddy, Traefik, nginx) devant pour le HTTPS.

## Développement local

```bash
npm install
cp .env.example .env
npx prisma db push && npx prisma generate && npm run db:seed
npm run dev
```

## Configuration

| Variable | Rôle |
|---|---|
| `BASE_URL` | URL publique (liens des emails, OAuth Google) |
| `SESSION_SECRET` | Secret de session — `openssl rand -hex 32` |
| `ADMIN_EMAIL` / `ADMIN_PASSWORD` / `ADMIN_NAME` | Compte admin créé au premier démarrage |
| `SMTP_HOST` / `SMTP_PORT` / `SMTP_USER` / `SMTP_PASS` / `SMTP_FROM` | Envoi des emails |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | Sync Google Calendar + Meet |
| `SMS_PROVIDER` | `brevo` ou `ovh` (vide = SMS journalisés) |
| `SMS_SENDER` | Nom d'expéditeur SMS (11 caractères max) |
| `BREVO_API_KEY` | Clé API Brevo (si `brevo`) |
| `OVH_APP_KEY` / `OVH_APP_SECRET` / `OVH_CONSUMER_KEY` / `OVH_SERVICE_NAME` | Identifiants OVH SMS (si `ovh`) |
| `HEALTH_ALERT_EMAIL` | Email alerté en cas de panne (défaut : admin) |
| `HEALTH_ALERT_PHONE` | Mobile alerté par SMS en cas de panne |

### Activer Google Calendar

1. [Console Google Cloud](https://console.cloud.google.com) → crée un projet →
   « APIs & Services » → active **Google Calendar API**.
2. « Credentials » → « Create credentials » → **OAuth client ID** → type
   « Web application » → URI de redirection :
   `https://TON-BASE-URL/api/google/callback`.
3. Renseigne `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET`, redémarre, puis
   dans **Réglages → Google Calendar → Connecter** (chaque hôte connecte son
   propre agenda).

### Intégrer sur votre site

Dans **Réglages → Intégrer sur votre site**, copie le snippet iframe :

```html
<iframe src="https://rdv.tondomaine.fr/david/demo-30?embed=1"
  style="width:100%;min-height:680px;border:none;border-radius:16px"
  title="Prendre rendez-vous"></iframe>
```

## Architecture

Next.js 15 (App Router) + Tailwind + Prisma/SQLite, image Docker `standalone`
(~150 Mo). Le calcul des créneaux (`src/lib/slots.ts`) croise : disponibilités
hebdomadaires de l'hôte (dans son fuseau), réservations existantes **avec
leurs tampons**, occupations Google (free/busy), préavis et horizon. Les
rappels sont envoyés par une boucle interne au serveur (aucun cron externe).

## Testé

Parcours complet vérifié automatiquement : calcul des créneaux (fuseaux,
week-ends, tampons adjacents), réservation, question obligatoire manquante
(400), double réservation du même créneau (409), reprogrammation (sans que le
RDV se bloque lui-même), annulation, emails générés (heure de Paris correcte),
authentification admin et protection des routes.

## Limites connues / pistes

- Le build Docker n'a pas pu être vérifié dans l'environnement de dev
  (registre Docker inaccessible) — signale-moi toute erreur au premier
  `docker compose up --build`.
- Pas de round-robin d'équipe ni de paiement Stripe (volontairement, v1).
- SQLite convient parfaitement à ce volume ; passage PostgreSQL possible en
  changeant `datasource` Prisma si besoin un jour.
