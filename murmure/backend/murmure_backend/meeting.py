"""Traitement des enregistrements de réunion :
transcription + diarization + export Markdown/JSON."""

import datetime as dt
import json
import logging
import re
from pathlib import Path

from . import config, diarization, summary, transcription

logger = logging.getLogger(__name__)


def _fmt_ts(seconds: float) -> str:
    s = int(seconds)
    return f"{s // 3600:02d}:{(s % 3600) // 60:02d}:{s % 60:02d}"


def _slugify(title: str) -> str:
    slug = re.sub(r"[^\w\s-]", "", title, flags=re.UNICODE).strip()
    slug = re.sub(r"[\s_-]+", "-", slug)
    return slug or "reunion"


def _friendly_speaker_names(segments: list[dict], prefix: str = "Intervenant") -> None:
    """Remplace SPEAKER_00, SPEAKER_01… par Intervenant 1, 2… dans l'ordre
    de première prise de parole."""
    mapping: dict[str, str] = {}
    for seg in sorted(segments, key=lambda s: s["start"]):
        raw = seg["speaker"]
        if raw.startswith("SPEAKER_") and raw not in mapping:
            mapping[raw] = f"{prefix} {len(mapping) + 1}"
    for seg in segments:
        seg["speaker"] = mapping.get(seg["speaker"], seg["speaker"])


def _transcribe_track(audio_path: str, *, with_words: bool = False) -> list[dict]:
    result = transcription.transcribe(audio_path, word_timestamps=with_words)
    segments = []
    for seg in result.get("segments", []):
        if not seg["text"].strip():
            continue
        entry = {
            "start": float(seg["start"]),
            "end": float(seg["end"]),
            "text": seg["text"].strip(),
        }
        if with_words:
            entry["words"] = [
                {
                    "start": float(w["start"]),
                    "end": float(w["end"]),
                    "word": w["word"],
                }
                for w in seg.get("words", [])
            ]
        segments.append(entry)
    return segments


def _split_by_speaker(segments: list[dict], turns: list[dict]) -> list[dict]:
    """Attribution fine des locuteurs : chaque MOT est rattaché au tour de
    parole qui le contient (un segment Whisper peut couvrir deux voix dans
    une conversation), puis les mots consécutifs du même locuteur sont
    regroupés en répliques."""
    if not turns:
        diarization.assign_speakers(segments, turns)
        for seg in segments:
            seg.pop("words", None)
        return segments

    def speaker_at(mid: float) -> str:
        for turn in turns:
            if turn["start"] <= mid <= turn["end"]:
                return turn["speaker"]
        nearest = min(
            turns,
            key=lambda t: min(abs(t["start"] - mid), abs(t["end"] - mid)),
        )
        return nearest["speaker"]

    # Aplatis tous les mots ; un segment sans mots devient un « mot » unique.
    words: list[dict] = []
    for seg in segments:
        if seg.get("words"):
            words.extend(seg["words"])
        else:
            words.append({"start": seg["start"], "end": seg["end"], "word": " " + seg["text"]})

    result: list[dict] = []
    for word in words:
        mid = (word["start"] + word["end"]) / 2
        speaker = speaker_at(mid)
        # Nouvelle réplique si le locuteur change ou après un long silence.
        if result and result[-1]["speaker"] == speaker and word["start"] - result[-1]["end"] < 2.0:
            result[-1]["end"] = word["end"]
            result[-1]["text"] += word["word"]
        else:
            result.append({
                "start": word["start"],
                "end": word["end"],
                "text": word["word"],
                "speaker": speaker,
            })
    for seg in result:
        seg["text"] = seg["text"].strip()
    return [seg for seg in result if seg["text"]]


def _shift_segments(segments: list[dict], offset: float) -> None:
    """Recale une piste sur l'horloge commune de l'enregistrement."""
    if offset:
        for seg in segments:
            seg["start"] += offset
            seg["end"] += offset


def process_meeting(
    mic_path: str | None,
    system_path: str | None,
    mode: str,
    title: str,
    *,
    mic_offset: float = 0.0,
    system_offset: float = 0.0,
    notes: str = "",
) -> dict:
    """Traite une réunion et écrit les fichiers de sortie.

    mode "in_person" : une seule piste micro, diarizée (qui a dit quoi).
    mode "remote"    : piste micro = l'utilisateur ("Moi"),
                       piste système (Teams…) diarizée pour les interlocuteurs.
    """
    segments: list[dict] = []

    if mode == "remote":
        if mic_path:
            mic_segments = _transcribe_track(mic_path)
            for seg in mic_segments:
                seg["speaker"] = "Moi"
            _shift_segments(mic_segments, mic_offset)
            segments.extend(mic_segments)
        if system_path:
            sys_segments = _transcribe_track(system_path, with_words=True)
            turns = diarization.diarize(system_path)
            sys_segments = _split_by_speaker(sys_segments, turns)
            _friendly_speaker_names(sys_segments, prefix="Interlocuteur")
            _shift_segments(sys_segments, system_offset)
            segments.extend(sys_segments)
    else:  # in_person
        if not mic_path:
            raise ValueError("Piste micro manquante pour une réunion en présentiel.")
        segments = _transcribe_track(mic_path, with_words=True)
        turns = diarization.diarize(mic_path)
        segments = _split_by_speaker(segments, turns)
        _friendly_speaker_names(segments)

    segments.sort(key=lambda s: s["start"])

    # Écriture des fichiers de sortie.
    now = dt.datetime.now()
    out_dir = config.OUTPUT_DIR / "Réunions" / f"{now:%Y-%m-%d %H%M} {_slugify(title)}"
    out_dir.mkdir(parents=True, exist_ok=True)

    json_path = out_dir / "transcription.json"
    json_path.write_text(
        json.dumps(
            {"title": title, "date": now.isoformat(), "mode": mode, "segments": segments},
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )

    md_path = out_dir / "transcription.md"
    md_path.write_text(_to_markdown(title, now, segments), encoding="utf-8")

    notes = notes.strip()
    if notes:
        (out_dir / "notes.md").write_text(
            f"# Notes de réunion : {title}\n\n{notes}\n", encoding="utf-8"
        )

    # Compte-rendu façon Granola (LLM local via Ollama). Jamais bloquant :
    # si Ollama est éteint, la transcription reste disponible.
    summary_path: Path | None = None
    summary_error: str | None = None
    if config.SUMMARY_ENABLED and segments:
        try:
            summary_md = summary.generate(title, segments, notes=notes)
            summary_path = out_dir / "compte-rendu.md"
            summary_path.write_text(
                f"# Compte-rendu : {title}\n\n"
                f"*Réunion du {now:%d/%m/%Y à %H:%M}. Généré localement par "
                f"Murmure ({config.SUMMARY_MODEL}).*\n\n"
                f"{summary_md}\n\n---\n\n"
                f"Transcription complète : [transcription.md](transcription.md)\n",
                encoding="utf-8",
            )
        except Exception as exc:  # noqa: BLE001
            summary_error = str(exc)
            logger.warning(
                "Compte-rendu indisponible (Ollama lancé ? modèle %s tiré ?) : %s",
                config.SUMMARY_MODEL, exc,
            )

    logger.info("Réunion exportée dans %s", out_dir)
    return {
        "markdown_path": str(md_path),
        "json_path": str(json_path),
        "summary_path": str(summary_path) if summary_path else None,
        "summary_error": summary_error,
        "output_dir": str(out_dir),
        "num_segments": len(segments),
        "speakers": sorted({s["speaker"] for s in segments}),
    }


def _to_markdown(title: str, when: dt.datetime, segments: list[dict]) -> str:
    lines = [f"# {title}", "", f"*Réunion du {when:%d/%m/%Y à %H:%M}. Transcription Murmure.*", ""]
    current_speaker = None
    for seg in segments:
        if seg["speaker"] != current_speaker:
            current_speaker = seg["speaker"]
            lines.append("")
            lines.append(f"**[{_fmt_ts(seg['start'])}] {current_speaker} :**")
        lines.append(seg["text"])
    lines.append("")
    return "\n".join(lines)
