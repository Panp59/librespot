"""Configuration du backend Murmure, via variables d'environnement."""

import os
from pathlib import Path

# Modèle Whisper (repo Hugging Face au format MLX).
# large-v3-turbo : excellent compromis vitesse/qualité sur Apple Silicon.
# Alternatives : mlx-community/whisper-large-v3-mlx (qualité max, plus lent).
WHISPER_MODEL = os.environ.get(
    "MURMURE_MODEL", "mlx-community/whisper-large-v3-turbo"
)

# Langue par défaut ("fr"). Mettre "auto" pour la détection automatique.
LANGUAGE = os.environ.get("MURMURE_LANGUAGE", "fr")

# Pipeline de diarization pyannote (modèle gated : accepter les conditions
# sur https://huggingface.co/pyannote/speaker-diarization-3.1 puis
# `huggingface-cli login` ou exporter HF_TOKEN).
DIARIZATION_MODEL = os.environ.get(
    "MURMURE_DIARIZATION_MODEL", "pyannote/speaker-diarization-3.1"
)
HF_TOKEN = os.environ.get("HF_TOKEN") or os.environ.get("HUGGING_FACE_HUB_TOKEN")

# Dossier de sortie des comptes-rendus de réunion.
OUTPUT_DIR = Path(
    os.environ.get("MURMURE_OUTPUT_DIR", Path.home() / "Documents" / "Murmure")
)

HOST = os.environ.get("MURMURE_HOST", "127.0.0.1")
PORT = int(os.environ.get("MURMURE_PORT", "8765"))

# Prompt initial donné à Whisper pour la dictée : améliore la ponctuation
# et le style en français.
DICTATION_PROMPT = os.environ.get(
    "MURMURE_DICTATION_PROMPT",
    "Voici une dictée en français, correctement ponctuée, sans hésitations.",
)

# Vocabulaire personnalisé (noms propres, jargon) : un mot ou une expression
# par ligne, injectés dans le prompt Whisper pour améliorer leur
# reconnaissance. Le fichier est relu à chaque dictée.
VOCAB_FILE = Path(
    os.environ.get("MURMURE_VOCAB_FILE", OUTPUT_DIR / "vocabulaire.txt")
)

# Historique local des dictées (Markdown). Mettre "0" pour désactiver.
HISTORY_ENABLED = os.environ.get("MURMURE_HISTORY", "1") != "0"
HISTORY_FILE = Path(
    os.environ.get("MURMURE_HISTORY_FILE", OUTPUT_DIR / "Dictées.md")
)
