#!/bin/bash
# Lance le backend Murmure. Fonctionne depuis le depot (venv local .venv)
# comme depuis le bundle Murmure.app (venv dans Application Support).
# NB: strings ASCII uniquement, le /bin/bash 3.2 de macOS avale les
# caracteres Unicode colles a une variable.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ffmpeg (Homebrew) doit etre visible meme quand l'app lance ce script
# sans environnement de shell.
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"

if [ -n "${MURMURE_VENV:-}" ]; then
  VENV_DIR="${MURMURE_VENV}"
else
  case "${SCRIPT_DIR}" in
    *".app/Contents/"*)
      # Dans le bundle .app : le venv vit dans Application Support pour
      # SURVIVRE aux mises a jour de l'app (remplacer Murmure.app ne doit
      # pas detruire l'environnement Python installe).
      VENV_DIR="${HOME}/Library/Application Support/Murmure/venv"
      ;;
    *)
      VENV_DIR="${SCRIPT_DIR}/.venv"
      ;;
  esac
fi

# Le fichier temoin n'est pose qu'apres une installation COMPLETE : si un
# premier lancement a ete interrompu en plein pip install, on reprend
# l'installation au lieu de demarrer avec un venv a moitie rempli.
STAMP="${VENV_DIR}/.dependances-ok"
if [ ! -x "${VENV_DIR}/bin/python" ] || [ ! -f "${STAMP}" ]; then
  echo "Installation de l'environnement Python dans ${VENV_DIR} ..."
  mkdir -p "$(dirname "${VENV_DIR}")"
  [ -x "${VENV_DIR}/bin/python" ] || python3 -m venv "${VENV_DIR}"
  "${VENV_DIR}/bin/pip" install --upgrade pip
  "${VENV_DIR}/bin/pip" install -r "${SCRIPT_DIR}/requirements.txt"
  touch "${STAMP}"
  echo "Installation terminee."
fi

cd "${SCRIPT_DIR}"
exec "${VENV_DIR}/bin/python" -m murmure_backend.main
