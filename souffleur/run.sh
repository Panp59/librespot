#!/bin/bash
# Lance Souffleur (CLI de synthese vocale locale). Cree le venv au premier
# appel. Piper est installe en "meilleur effort" : s'il echoue (souci de
# wheel sur Apple Silicon...), Souffleur bascule sur la voix macOS "say",
# donc la production de narration n'est jamais bloquee.
# NB: strings ASCII uniquement, le /bin/bash 3.2 de macOS avale les
# caracteres Unicode colles a une variable.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

VENV_DIR="${SOUFFLEUR_VENV:-${SCRIPT_DIR}/.venv}"
STAMP="${VENV_DIR}/.dependances-ok"

if [ ! -x "${VENV_DIR}/bin/python" ] || [ ! -f "${STAMP}" ]; then
  echo "Installation de l'environnement Python dans ${VENV_DIR} ..."
  [ -x "${VENV_DIR}/bin/python" ] || python3 -m venv "${VENV_DIR}"
  "${VENV_DIR}/bin/pip" install --upgrade pip

  # numpy est indispensable (assemblage) : echec = arret.
  "${VENV_DIR}/bin/pip" install numpy

  # Piper + HuggingFace en meilleur effort.
  if "${VENV_DIR}/bin/pip" install piper-tts huggingface_hub; then
    echo "Piper installe : voix neuronale disponible."
  else
    echo "ATTENTION : Piper n'a pas pu etre installe."
    echo "Souffleur utilisera la voix macOS 'say' (repli integre)."
    "${VENV_DIR}/bin/pip" install huggingface_hub || true
  fi

  touch "${STAMP}"
  echo "Installation terminee."
fi

cd "${SCRIPT_DIR}"
exec "${VENV_DIR}/bin/python" -m souffleur "$@"
