"""Traitement des enregistrements de réunion :
transcription + diarization + export Markdown/JSON."""

import datetime as dt
import json
import logging
import re
from pathlib import Path

from . import config, diarization, transcription

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


def _transcribe_track(audio_path: str) -> list[dict]:
    result = transcription.transcribe(audio_path)
    return [
        {
            "start": float(seg["start"]),
            "end": float(seg["end"]),
            "text": seg["text"].strip(),
        }
        for seg in result.get("segments", [])
        if seg["text"].strip()
    ]


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
            sys_segments = _transcribe_track(system_path)
            turns = diarization.diarize(system_path)
            diarization.assign_speakers(sys_segments, turns)
            _friendly_speaker_names(sys_segments, prefix="Interlocuteur")
            _shift_segments(sys_segments, system_offset)
            segments.extend(sys_segments)
    else:  # in_person
        if not mic_path:
            raise ValueError("Piste micro manquante pour une réunion en présentiel.")
        segments = _transcribe_track(mic_path)
        turns = diarization.diarize(mic_path)
        diarization.assign_speakers(segments, turns)
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

    logger.info("Réunion exportée dans %s", out_dir)
    return {
        "markdown_path": str(md_path),
        "json_path": str(json_path),
        "output_dir": str(out_dir),
        "num_segments": len(segments),
        "speakers": sorted({s["speaker"] for s in segments}),
    }


def _to_markdown(title: str, when: dt.datetime, segments: list[dict]) -> str:
    lines = [f"# {title}", "", f"*Réunion du {when:%d/%m/%Y à %H:%M} — transcription Murmure*", ""]
    current_speaker = None
    for seg in segments:
        if seg["speaker"] != current_speaker:
            current_speaker = seg["speaker"]
            lines.append("")
            lines.append(f"**[{_fmt_ts(seg['start'])}] {current_speaker} :**")
        lines.append(seg["text"])
    lines.append("")
    return "\n".join(lines)
