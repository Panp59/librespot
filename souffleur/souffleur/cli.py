"""Interface en ligne de commande de Souffleur.

  python -m souffleur line --text "Bonjour" --out voix.wav
  python -m souffleur assemble --plan plan.json --out narration.wav
  python -m souffleur voices
  python -m souffleur selftest
"""

import argparse
import json
import logging
import sys
from pathlib import Path

from . import assemble as assemble_mod
from . import config, tts


def _cmd_line(args) -> int:
    path = tts.to_wav(args.text, Path(args.out), backend=args.backend, voice=args.voice)
    print(json.dumps({"output": str(path)}, ensure_ascii=False))
    return 0


def _cmd_assemble(args) -> int:
    plan = json.loads(Path(args.plan).read_text(encoding="utf-8"))
    if args.backend:
        plan["backend"] = args.backend
    if args.voice:
        plan["voice"] = args.voice
    report = assemble_mod.assemble(plan, Path(args.out))
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if report["pushed_any"]:
        print(
            "Attention : certaines répliques ont été repoussées (texte trop "
            "long pour l'intervalle). Raccourcis-les ou espace les étapes.",
            file=sys.stderr,
        )
    return 0


def _cmd_voices(_args) -> int:
    print("Voix Piper (neuronal, local) :")
    for name in config.PIPER_VOICES:
        default = " (défaut)" if name == config.DEFAULT_PIPER_VOICE else ""
        print(f"  {name}{default}")
    print("\nVoix macOS « say » : liste complète via `say -v ?`")
    print(f"  défaut : {config.DEFAULT_SAY_VOICE}")
    return 0


def _cmd_selftest(args) -> int:
    """Vérifie qu'une phrase se synthétise et s'écrit."""
    out = Path(args.out or (config.DATA_DIR / "selftest.wav"))
    try:
        tts.to_wav(
            "Ceci est un test de Souffleur. La voix fonctionne.",
            out, backend=args.backend, voice=args.voice,
        )
    except Exception as exc:  # noqa: BLE001
        print(json.dumps({"ok": False, "error": str(exc)}, ensure_ascii=False))
        return 1
    print(json.dumps({"ok": True, "output": str(out)}, ensure_ascii=False))
    return 0


def main(argv=None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    parser = argparse.ArgumentParser(prog="souffleur", description="Synthèse vocale locale FR.")
    parser.add_argument("--backend", choices=["piper", "say"], default=None,
                        help="Moteur de synthèse (défaut : piper, repli say).")
    parser.add_argument("--voice", default=None, help="Voix (nom Piper ou nom say).")
    sub = parser.add_subparsers(dest="command", required=True)

    p_line = sub.add_parser("line", help="Synthétiser une phrase en WAV.")
    p_line.add_argument("--text", required=True)
    p_line.add_argument("--out", required=True)
    p_line.set_defaults(func=_cmd_line)

    p_assemble = sub.add_parser("assemble", help="Assembler un plan horodaté en narration.wav.")
    p_assemble.add_argument("--plan", required=True, help="Fichier JSON du plan.")
    p_assemble.add_argument("--out", required=True)
    p_assemble.set_defaults(func=_cmd_assemble)

    p_voices = sub.add_parser("voices", help="Lister les voix disponibles.")
    p_voices.set_defaults(func=_cmd_voices)

    p_selftest = sub.add_parser("selftest", help="Tester la synthèse de bout en bout.")
    p_selftest.add_argument("--out", default=None)
    p_selftest.set_defaults(func=_cmd_selftest)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
