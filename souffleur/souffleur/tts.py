"""Moteurs de synthèse vocale : Piper (neuronal, local) et say (macOS).

Chaque moteur produit un WAV mono int16. Le moteur `piper` télécharge sa
voix une seule fois (HuggingFace), puis tout est local. En cas d'échec de
Piper (installation ou synthèse), on bascule automatiquement sur `say` pour
ne jamais bloquer la production d'une démo, sauf si SOUFFLEUR_TTS=piper
force explicitement Piper.
"""

import logging
import subprocess
import tempfile
import wave
from pathlib import Path

from . import config

logger = logging.getLogger(__name__)

_piper_voice_cache: dict[str, object] = {}


# --------------------------------------------------------------------------
# Piper
# --------------------------------------------------------------------------

def _piper_model_paths(voice: str) -> tuple[Path, Path]:
    """Retourne (onnx, onnx.json), en les tirant de HuggingFace si absents."""
    if voice not in config.PIPER_VOICES:
        raise ValueError(
            f"Voix Piper inconnue : {voice}. Voix connues : "
            + ", ".join(config.PIPER_VOICES)
        )
    from huggingface_hub import hf_hub_download

    stem = config.PIPER_VOICES[voice]
    config.VOICES_DIR.mkdir(parents=True, exist_ok=True)
    onnx = hf_hub_download(
        repo_id=config.PIPER_REPO, filename=f"{stem}.onnx",
        cache_dir=str(config.VOICES_DIR),
    )
    conf = hf_hub_download(
        repo_id=config.PIPER_REPO, filename=f"{stem}.onnx.json",
        cache_dir=str(config.VOICES_DIR),
    )
    return Path(onnx), Path(conf)


def _load_piper_voice(voice: str):
    if voice in _piper_voice_cache:
        return _piper_voice_cache[voice]
    from piper import PiperVoice

    onnx, conf = _piper_model_paths(voice)
    loaded = PiperVoice.load(str(onnx), config_path=str(conf))
    _piper_voice_cache[voice] = loaded
    return loaded


def _piper_samples(text: str, voice: str) -> tuple[int, bytes]:
    """Retourne (fréquence, octets int16 mono). Robuste aux variantes d'API
    de piper-tts (1.2.x flux brut / synthesize(text, wav) ; 1.3.x AudioChunk)."""
    v = _load_piper_voice(voice)
    default_sr = getattr(getattr(v, "config", None), "sample_rate", config.SAMPLE_RATE)

    # piper-tts >= 1.3 : synthesize(text) -> itérable d'AudioChunk.
    if hasattr(v, "synthesize"):
        try:
            chunks = list(v.synthesize(text))
        except TypeError:
            chunks = None  # ancienne signature synthesize(text, wav)
        if chunks:
            first = chunks[0]
            if hasattr(first, "audio_int16_bytes"):
                sr = getattr(first, "sample_rate", default_sr)
                return sr, b"".join(c.audio_int16_bytes for c in chunks)
            if hasattr(first, "audio_float_array"):
                import numpy as np

                sr = getattr(first, "sample_rate", default_sr)
                arr = np.concatenate([c.audio_float_array for c in chunks])
                pcm = (np.clip(arr, -1.0, 1.0) * 32767).astype("<i2")
                return sr, pcm.tobytes()

    # piper-tts 1.2.x : flux brut int16.
    if hasattr(v, "synthesize_stream_raw"):
        return default_sr, b"".join(v.synthesize_stream_raw(text))

    # piper-tts 1.2.x : synthesize(text, wave_write).
    import io

    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(default_sr)
        v.synthesize(text, wf)
    buffer.seek(0)
    with wave.open(buffer, "rb") as wf:
        return wf.getframerate(), wf.readframes(wf.getnframes())


# --------------------------------------------------------------------------
# say (macOS)
# --------------------------------------------------------------------------

def _say_samples(text: str, voice: str) -> tuple[int, bytes]:
    """Utilise say + afconvert (tous deux intégrés à macOS). Ramène au
    passage à la fréquence commune et en mono."""
    with tempfile.TemporaryDirectory() as tmp:
        aiff = Path(tmp) / "voix.aiff"
        wav = Path(tmp) / "voix.wav"
        say_cmd = ["/usr/bin/say", "-o", str(aiff)]
        if voice:
            say_cmd += ["-v", voice]
        say_cmd.append(text)
        subprocess.run(say_cmd, check=True, capture_output=True)
        subprocess.run(
            ["/usr/bin/afconvert", str(aiff), str(wav),
             "-d", f"LEI16@{config.SAMPLE_RATE}", "-f", "WAVE", "-c", "1"],
            check=True, capture_output=True,
        )
        with wave.open(str(wav), "rb") as wf:
            return wf.getframerate(), wf.readframes(wf.getnframes())


# --------------------------------------------------------------------------
# API publique
# --------------------------------------------------------------------------

def samples(text: str, *, backend: str | None = None, voice: str | None = None
            ) -> tuple[int, bytes]:
    """Synthétise une réplique. Retourne (fréquence, octets PCM int16 mono).

    backend "piper" (défaut) bascule sur "say" en cas d'échec, sauf si
    SOUFFLEUR_TTS=piper est explicitement demandé (échec dur alors)."""
    backend = (backend or config.DEFAULT_BACKEND).lower()
    text = text.strip()
    if not text:
        return config.SAMPLE_RATE, b""

    if backend == "say":
        return _say_samples(text, voice or config.DEFAULT_SAY_VOICE)

    # backend piper
    try:
        return _piper_samples(text, voice or config.DEFAULT_PIPER_VOICE)
    except Exception as exc:  # noqa: BLE001
        import os

        if os.environ.get("SOUFFLEUR_TTS", "").lower() == "piper":
            raise
        logger.warning(
            "Piper indisponible (%s), repli sur la voix macOS « say ». "
            "Installe Piper pour une voix plus naturelle.", exc,
        )
        return _say_samples(text, config.DEFAULT_SAY_VOICE)


def to_wav(text: str, out_path: Path, *, backend: str | None = None,
           voice: str | None = None) -> Path:
    """Écrit une réplique dans un fichier WAV."""
    sr, pcm = samples(text, backend=backend, voice=voice)
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(out_path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes(pcm)
    return out_path
