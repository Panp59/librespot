# Souffleur

Synthèse vocale française locale, pensée pour les voix off des démos Clap. Deux moteurs :

- **Piper** (défaut) : TTS neuronal local, voix naturelle, modèle tiré une fois puis 100% hors ligne.
- **say** (repli) : la voix intégrée à macOS, zéro dépendance. Utilisée automatiquement si Piper n'est pas installable.

Aucune donnée ne quitte le Mac.

## Installation

```bash
cd souffleur
./run.sh selftest
```

Le premier appel crée le venv et installe les dépendances. `selftest` synthétise une phrase de test et confirme que la voix fonctionne. Si Piper ne s'installe pas (souci de wheel sur Apple Silicon), Souffleur bascule sur `say` et te le dit, rien n'est bloqué.

## Utilisation

Une phrase en fichier WAV :

```bash
./run.sh line --text "Bienvenue dans la démonstration d'OPTIMa." --out voix.wav
```

Assembler une narration complète calée sur une vidéo, à partir d'un plan horodaté :

```bash
./run.sh assemble --plan plan.json --out narration.wav
```

Lister les voix, choisir un moteur ou une voix :

```bash
./run.sh voices
./run.sh --voice fr_FR-tom-medium line --text "Essai voix masculine." --out tom.wav
./run.sh --backend say --voice Amelie line --text "Voix québécoise." --out amelie.wav
```

## Le plan (JSON)

```json
{
  "voice": "fr_FR-siwis-medium",
  "backend": "piper",
  "duration": 185.0,
  "lines": [
    {"start": 2.0, "text": "Bienvenue dans OPTIMa, la GMAO d'ADTI."},
    {"start": 9.5, "text": "Créons une intervention de maintenance."}
  ]
}
```

- `start` : instant (secondes) où la réplique commence, dans le repère de la vidéo (t=0 = première image).
- `duration` : longueur totale visée du fichier (optionnel), pour finir sur un silence calé sur la fin de la vidéo.
- `voice` / `backend` : optionnels, sinon valeurs par défaut.

Les répliques ne se chevauchent jamais : si l'une est trop longue et déborde sur la suivante, la suivante est repoussée et le rapport de sortie le signale (`pushed: true`). C'est le signe qu'il faut raccourcir le texte ou espacer les étapes.

Le rapport JSON en sortie donne, pour chaque réplique, le début réel et la fin après synthèse : de quoi vérifier la synchro avec la vidéo.

## Voix Piper françaises

| Nom | Voix |
|---|---|
| fr_FR-siwis-medium | féminine, claire (défaut) |
| fr_FR-tom-medium | masculine |
| fr_FR-upmc-medium | féminine |
| fr_FR-gilles-low | masculine, plus légère |

## Réglages (variables d'environnement)

- `SOUFFLEUR_TTS` : `piper` (défaut) ou `say`. Mettre `piper` force Piper (pas de repli, échec dur si indisponible).
- `SOUFFLEUR_VOICE` : voix Piper par défaut.
- `SOUFFLEUR_SAY_VOICE` : voix macOS par défaut (défaut : Thomas).

## Vos données

Tout est local : le venv et les modèles Piper vivent dans `souffleur/.venv` et `~/Library/Application Support/Souffleur/voices`. Rien n'est envoyé nulle part.
