# Murmure 🎙️

Clone local de Wispr Flow pour macOS : **dictée vocale partout** (push-to-talk)
et **transcription de réunions avec identification des locuteurs** — le tout
avec des modèles qui tournent **100 % en local** sur ton Mac (Apple Silicon).
Aucun audio ne quitte la machine.

## Ce que ça fait

1. **Dictée (mode Wispr Flow)** : tu maintiens la touche **⌥ Option droite**,
   tu parles, tu relâches → le texte transcrit (ponctué, sans les « euh »)
   est inséré au curseur, dans n'importe quelle application.
2. **Réunions** :
   - **Présentiel** : enregistrement au micro, puis transcription + *diarization*
     (« Intervenant 1 », « Intervenant 2 »… : on sait qui a dit quoi).
   - **Teams / visio** : enregistrement du micro (toi) **et** de l'audio
     système (les autres participants) → transcription fusionnée
     chronologiquement, avec « Moi » et « Interlocuteur 1, 2… ».
   - Export en **Markdown + JSON** dans `~/Documents/Murmure/Réunions/`.
3. **Compte-rendu automatique (façon Granola)** : en plus de la transcription
   brute, un LLM local (via **Ollama**) génère `compte-rendu.md` — résumé,
   décisions, actions (« **Qui** : quoi »), points ouverts. Les longues
   réunions sont résumées en plusieurs passes. C'est ce fichier qui s'ouvre
   à la fin ; la transcription complète reste à côté.

## Architecture

```
murmure/
├── backend/     Serveur Python local (FastAPI, port 8765)
│                ├── mlx-whisper large-v3-turbo  → transcription (GPU Metal)
│                └── pyannote speaker-diarization-3.1 → qui parle quand
└── mac/         App macOS native (Swift, barre de menus)
                 ├── raccourci global ⌥ droite (push-to-talk)
                 ├── insertion du texte au curseur (⌘V synthétique)
                 ├── capture micro (AVAudioRecorder)
                 └── capture audio système (ScreenCaptureKit) pour Teams
```

L'app Swift enregistre l'audio et l'envoie au backend sur `127.0.0.1:8765` ;
le backend fait tourner les modèles et renvoie le texte.

## Prérequis

- Mac **Apple Silicon** (M1 ou plus récent), macOS 13+ — idéalement 16 Go de
  RAM ou plus (large-v3-turbo + pyannote tiennent très bien dans 24 Go).
- **Xcode Command Line Tools** : `xcode-select --install`
- **Homebrew**, puis : `brew install ffmpeg python@3.12`
- Un compte **Hugging Face** (gratuit) pour la diarization :
  1. Accepte les conditions de
     [pyannote/speaker-diarization-3.1](https://huggingface.co/pyannote/speaker-diarization-3.1)
     et de
     [pyannote/segmentation-3.0](https://huggingface.co/pyannote/segmentation-3.0).
  2. Connecte-toi : `pip install huggingface_hub && huggingface-cli login`
     (ou exporte `HF_TOKEN=hf_…` avant de lancer le backend).

  > La dictée fonctionne sans ce compte — il n'est nécessaire que pour le
  > « qui a dit quoi » des réunions.
- **Ollama** (optionnel, pour le compte-rendu automatique) :
  ```bash
  brew install ollama
  ollama serve          # ou lance l'app Ollama
  ollama pull qwen3:14b # ~9 Go, très bon en français sur 24 Go de RAM
  ```
  Sans Ollama, tout le reste fonctionne : seul `compte-rendu.md` n'est pas
  généré. Modèle plus léger : `MURMURE_SUMMARY_MODEL=qwen3:8b`.

## Installation

### 1. Le backend

```bash
cd murmure/backend
./run.sh        # crée le venv, installe les dépendances, démarre le serveur
```

Au premier lancement, les modèles sont téléchargés depuis Hugging Face
(~1,6 Go pour Whisper large-v3-turbo) puis mis en cache — ensuite tout est
hors-ligne. Laisse ce terminal ouvert (ou lance le backend depuis le menu de
l'app, voir plus bas).

### 2. L'app macOS

```bash
cd murmure/mac
./make_app.sh
cp -r build/Murmure.app /Applications/
open /Applications/Murmure.app
```

### 3. Les autorisations macOS (une seule fois)

Au premier lancement, macOS va demander :

| Autorisation | Sert à | Où l'activer |
|---|---|---|
| **Microphone** | dictée + réunions | Réglages → Confidentialité → Microphone |
| **Accessibilité** | raccourci global + insertion du texte | Réglages → Confidentialité → Accessibilité |
| **Enregistrement de l'écran** | audio système (mode Teams uniquement) | Réglages → Confidentialité → Enregistrement de l'écran et audio système |

Après avoir accordé Accessibilité, quitte et relance l'app.

## Utilisation

- **Dictée** : place ton curseur où tu veux écrire, **maintiens ⌥ droite**,
  parle, relâche. Le texte apparaît. (Un petit HUD en bas d'écran indique
  l'état.) **Échap** pendant l'enregistrement annule la dictée. Des sons
  discrets marquent le début/la fin (désactivables dans le menu).
- **Vocabulaire personnalisé** : ajoute tes noms propres et ton jargon
  (un par ligne) dans `~/Documents/Murmure/vocabulaire.txt` — ils seront
  mieux reconnus. Les lignes commençant par `#` sont ignorées.
- **Historique** : chaque dictée est ajoutée à
  `~/Documents/Murmure/Dictées.md` (désactivable avec `MURMURE_HISTORY=0`).
- **Langue** : le menu propose la « Détection automatique de la langue »
  pour les dictées bilingues, sans redémarrer le backend.
- Le menu permet aussi de **lancer Murmure à l'ouverture de session**.
- **Réunion en présentiel** : menu 🎙️ → « Réunion en présentiel : démarrer »,
  puis « Arrêter la réunion et transcrire » à la fin. Donne un titre → le
  compte-rendu Markdown s'ouvre tout seul.
- **Réunion Teams/visio** : menu 🎙️ → « Réunion Teams/visio : démarrer ».
  Porte un casque (sinon ta voix sera aussi captée dans l'audio système).
- **Backend** : le menu affiche son état ; « Démarrer le backend » le lance
  pour toi (il te demandera où se trouve le dossier `backend` la première fois).

Les enregistrements bruts sont conservés dans
`~/Documents/Murmure/Enregistrements/` (supprime-les quand tu n'en as plus
besoin), les comptes-rendus dans `~/Documents/Murmure/Réunions/`.

## Configuration (variables d'environnement du backend)

| Variable | Défaut | Description |
|---|---|---|
| `MURMURE_MODEL` | `mlx-community/whisper-large-v3-turbo` | Modèle Whisper (format MLX) |
| `MURMURE_LANGUAGE` | `fr` | Langue, ou `auto` pour la détection |
| `MURMURE_OUTPUT_DIR` | `~/Documents/Murmure` | Dossier des comptes-rendus |
| `MURMURE_PORT` | `8765` | Port du serveur local |
| `HF_TOKEN` | — | Jeton Hugging Face (diarization) |
| `MURMURE_SUMMARY` | `1` | Compte-rendu automatique (`0` pour désactiver) |
| `MURMURE_SUMMARY_MODEL` | `qwen3:14b` | Modèle Ollama du compte-rendu |
| `MURMURE_OLLAMA_URL` | `http://127.0.0.1:11434` | URL du serveur Ollama |

Exemple : `MURMURE_LANGUAGE=auto ./run.sh` pour des réunions bilingues FR/EN.

## Notes & limites connues

- **Latence de dictée** : ~1 s pour une phrase courte avec large-v3-turbo sur
  un M-series récent. Pour encore plus de réactivité :
  `MURMURE_MODEL=mlx-community/whisper-medium-mlx` (léger compromis qualité).
- **Diarization** : pyannote est très bon mais pas parfait — les locuteurs aux
  voix proches peuvent être confondus ; le nombre de locuteurs est détecté
  automatiquement.
- En mode Teams, l'attribution est structurelle : ta piste micro = « Moi »,
  la piste système est diarizée entre les interlocuteurs distants.
- Le traitement d'une réunion d'une heure prend quelques minutes (transcription
  + diarization) ; le HUD reste affiché pendant ce temps.

## Pistes d'évolution

- Renommage interactif des intervenants (« Intervenant 1 » → « David »).
- Résumé automatique du compte-rendu via un LLM local (Ollama).
- Vocabulaire personnalisé (noms propres, jargon) injecté dans le prompt Whisper.
- Choix de la touche de dictée dans les réglages.
