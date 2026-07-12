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

# Le fichier témoin n'est posé qu'après une installation COMPLÈTE : si un
# premier lancement a été interrompu en plein pip install, on reprend
# l'installation au lieu de démarrer avec un venv à moitié rempli.
STAMP="$VENV_DIR/.dependances-ok"
if [ ! -x "$VENV_DIR/bin/python" ] || [ ! -f "$STAMP" ]; then
  echo "Installation de l'environnement Python dans $VENV_DIR…"
  mkdir -p "$(dirname "$VENV_DIR")"
  [ -x "$VENV_DIR/bin/python" ] || python3 -m venv "$VENV_DIR"
  "$VENV_DIR/bin/pip" install --upgrade pip
  "$VENV_DIR/bin/pip" install -r "$SCRIPT_DIR/requirements.txt"
  touch "$STAMP"
  echo "Installation terminée."
fi

cd "$SCRIPT_DIR"
exec "$VENV_DIR/bin/python" -m murmure_backend.main
