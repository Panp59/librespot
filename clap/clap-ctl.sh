#!/bin/bash
# Pilote Clap via son API de controle locale (menu Clap > "Controle par le
# CLI"). Lit le port et le jeton dans control.json.
#
#   ./clap-ctl.sh status
#   ./clap-ctl.sh start screen
#   ./clap-ctl.sh start window OPTIMa
#   ./clap-ctl.sh start window OPTIMa --webcam
#   ./clap-ctl.sh stop
#
# NB: strings ASCII uniquement.
set -euo pipefail

INFO="${HOME}/Library/Application Support/Clap/control.json"
if [ ! -f "${INFO}" ]; then
  echo "Controle Clap eteint. Active-le dans le menu Clap > Controle par le CLI." >&2
  exit 1
fi

PORT="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["port"])' "${INFO}")"
TOKEN="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["token"])' "${INFO}")"
BASE="http://127.0.0.1:${PORT}"
AUTH="X-Clap-Token: ${TOKEN}"

CMD="${1:-status}"
case "${CMD}" in
  status)
    curl -s -H "${AUTH}" "${BASE}/status"
    ;;
  start)
    TARGET="${2:-screen}"
    WEBCAM="false"
    MATCH=""
    shift 2 || true
    for arg in "$@"; do
      if [ "${arg}" = "--webcam" ]; then WEBCAM="true"; else MATCH="${arg}"; fi
    done
    if [ "${TARGET}" = "window" ]; then
      BODY="{\"target\":\"window\",\"match\":\"${MATCH}\",\"webcam\":${WEBCAM}}"
    else
      BODY="{\"target\":\"screen\",\"webcam\":${WEBCAM}}"
    fi
    curl -s -H "${AUTH}" -H "Content-Type: application/json" -d "${BODY}" "${BASE}/start"
    ;;
  stop)
    curl -s -H "${AUTH}" -X POST "${BASE}/stop"
    ;;
  *)
    echo "Commandes : status | start [screen|window <match>] [--webcam] | stop" >&2
    exit 1
    ;;
esac
echo
