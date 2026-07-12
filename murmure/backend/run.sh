#!/bin/bash
# Lance le backend Murmure. Fonctionne depuis le dépôt (venv local .venv)
# comme depuis le bundle Murmure.app (venv dans Application Support).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ffmpeg (Homebrew) doit être visible même quand l'app lance ce script
# sans environnement de shell.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if [ -n "${MURMURE_VENV:-}" ]; then
  VENV_DIR="$MURMURE_VENV"
elif [ -w "$SCRIPT_DIR" ]; then
  VENV_DIR="$SCRIPT_DIR/.venv"
else
  # Bundle .app : lecture seule, le venv vit dans Application Support.
  VENV_DIR="$HOME/Library/Application Support/Murmure/venv"
fi

if [ ! -x "$VENV_DIR/bin/python" ]; then
  echo "Création de l'environnement virtuel dans $VENV_DIR…"
  mkdir -p "$(dirname "$VENV_DIR")"
  python3 -m venv "$VENV_DIR"
  "$VENV_DIR/bin/pip" install --upgrade pip
  "$VENV_DIR/bin/pip" install -r "$SCRIPT_DIR/requirements.txt"
fi

cd "$SCRIPT_DIR"
exec "$VENV_DIR/bin/python" -m murmure_backend.main
