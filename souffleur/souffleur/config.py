"""Configuration de Souffleur (surchargée par variables d'environnement)."""

import os
from pathlib import Path

# Fréquence d'échantillonnage commune à toute la narration assemblée.
# Chaque clip est ramené à cette valeur, quel que soit le moteur.
SAMPLE_RATE = 22_050

DATA_DIR = Path.home() / "Library" / "Application Support" / "Souffleur"
VOICES_DIR = DATA_DIR / "voices"

# Moteur par défaut : "piper" (naturel) ou "say" (repli macOS).
DEFAULT_BACKEND = os.environ.get("SOUFFLEUR_TTS", "piper").lower()
DEFAULT_PIPER_VOICE = os.environ.get("SOUFFLEUR_VOICE", "fr_FR-siwis-medium")
# Voix macOS française par défaut (say -v ?).
DEFAULT_SAY_VOICE = os.environ.get("SOUFFLEUR_SAY_VOICE", "Thomas")

# Voix Piper connues, chemin (sans extension) dans le dépôt HuggingFace
# rhasspy/piper-voices. Le .onnx et le .onnx.json sont tirés à la demande.
PIPER_VOICES = {
    "fr_FR-siwis-medium": "fr/fr_FR/siwis/medium/fr_FR-siwis-medium",
    "fr_FR-tom-medium": "fr/fr_FR/tom/medium/fr_FR-tom-medium",
    "fr_FR-upmc-medium": "fr/fr_FR/upmc/medium/fr_FR-upmc-medium",
    "fr_FR-gilles-low": "fr/fr_FR/gilles/low/fr_FR-gilles-low",
}

PIPER_REPO = "rhasspy/piper-voices"
