"""Assemble une liste de répliques horodatées en un seul narration.wav,
calé sur le début de la vidéo (silences aux bons endroits).

Plan attendu (JSON) :
{
  "voice": "fr_FR-siwis-medium",   # optionnel, sinon défaut
  "backend": "piper",              # optionnel : "piper" | "say"
  "duration": 185.0,               # optionnel : longueur totale visée (s)
  "lines": [
    {"start": 2.0, "text": "Bienvenue dans OPTIMa."},
    {"start": 9.5, "text": "Creons une intervention."}
  ]
}

Les répliques ne se chevauchent jamais : si l'une déborde sur la suivante,
la suivante est repoussée juste après (et le rapport le signale, pour que
l'appelant sache que la narration prend du retard sur la vidéo).
"""

import logging
import wave
from pathlib import Path

from . import config, tts

logger = logging.getLogger(__name__)


def _resample_int16(pcm: bytes, src_sr: int, dst_sr: int):
    """Rééchantillonnage linéaire simple (aucune dépendance lourde)."""
    import numpy as np

    # Tronque à un nombre pair d'octets : frombuffer exige un multiple de la
    # taille d'un échantillon (2 octets).
    audio = np.frombuffer(pcm[: len(pcm) & ~1], dtype="<i2")
    if src_sr == dst_sr or audio.size == 0:
        return audio.astype("<i2")
    duration = audio.size / src_sr
    dst_count = int(round(duration * dst_sr))
    if dst_count <= 0:
        return np.zeros(0, dtype="<i2")
    src_idx = np.linspace(0, audio.size - 1, dst_count)
    resampled = np.interp(src_idx, np.arange(audio.size), audio.astype(np.float64))
    return np.clip(resampled, -32768, 32767).astype("<i2")


def assemble(plan: dict, out_path: Path) -> dict:
    import numpy as np

    sr = config.SAMPLE_RATE
    backend = plan.get("backend")
    voice = plan.get("voice")
    # On garde l'index d'origine (avant tri) pour que le rapport reste
    # rattachable aux répliques telles que fournies par l'appelant.
    lines = sorted(
        enumerate(plan.get("lines", [])),
        key=lambda item: float(item[1].get("start", 0)),
    )

    clips = []  # (start_sample, np.int16)
    cursor = 0  # premier échantillon libre
    report_lines = []
    pushed_any = False

    for index, line in lines:
        text = (line.get("text") or "").strip()
        if not text:
            continue
        requested = float(line.get("start", 0))
        requested_sample = max(0, int(round(requested * sr)))

        src_sr, pcm = tts.samples(text, backend=backend, voice=voice)
        audio = _resample_int16(pcm, src_sr, sr)

        begin = max(requested_sample, cursor)
        pushed = begin > requested_sample
        pushed_any = pushed_any or pushed
        clips.append((begin, audio))
        cursor = begin + audio.size

        report_lines.append({
            "index": index,
            "requested_start": round(requested, 3),
            "actual_start": round(begin / sr, 3),
            "end": round((begin + audio.size) / sr, 3),
            "pushed": pushed,
            "text": text,
        })
        if pushed:
            logger.warning(
                "Réplique %d repoussée de %.2fs (la précédente déborde) : « %s »",
                index, (begin - requested_sample) / sr, text[:60],
            )

    total_samples = cursor
    if plan.get("duration"):
        total_samples = max(total_samples, int(round(float(plan["duration"]) * sr)))

    canvas = np.zeros(max(total_samples, 1), dtype="<i2")
    for begin, audio in clips:
        end = begin + audio.size
        if end > canvas.size:
            canvas = np.concatenate([canvas, np.zeros(end - canvas.size, dtype="<i2")])
        canvas[begin:end] = audio

    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(out_path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes(canvas.tobytes())

    return {
        "output": str(out_path),
        "duration": round(canvas.size / sr, 3),
        "sample_rate": sr,
        "lines": report_lines,
        "pushed_any": pushed_any,
    }
