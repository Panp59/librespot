"""Transcription locale avec mlx-whisper (accéléré Metal sur Apple Silicon)."""

import logging
import threading

from . import config

logger = logging.getLogger(__name__)

# mlx_whisper garde le modèle en cache après le premier appel, mais on
# sérialise les transcriptions : le GPU Metal n'aime pas les accès concurrents.
_lock = threading.Lock()


def _language() -> str | None:
    lang = config.LANGUAGE.strip().lower()
    return None if lang in ("", "auto") else lang


def transcribe(
    audio_path: str,
    *,
    initial_prompt: str | None = None,
    language_override: str | None = None,
    word_timestamps: bool = False,
) -> dict:
    """Transcrit un fichier audio. Retourne le dict mlx-whisper
    ({"text": ..., "segments": [{"start", "end", "text"}, ...]}).

    language_override : None = langue de la config ; "auto" = détection
    automatique forcée ; sinon un code langue ("fr", "en"…).
    """
    import mlx_whisper  # import paresseux : long au premier chargement

    if language_override is None:
        language = _language()
    elif language_override.strip().lower() in ("auto", ""):
        language = None
    else:
        language = language_override.strip().lower()

    with _lock:
        logger.info("Transcription de %s (modèle %s)", audio_path, config.WHISPER_MODEL)
        result = mlx_whisper.transcribe(
            audio_path,
            path_or_hf_repo=config.WHISPER_MODEL,
            language=language,
            initial_prompt=initial_prompt,
            condition_on_previous_text=True,
            word_timestamps=word_timestamps,
        )
    logger.info("Transcription terminée (%d segments)", len(result.get("segments", [])))
    return result


def warm_up() -> None:
    """Précharge le modèle pour que la première dictée soit instantanée."""
    import tempfile
    import wave

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        with wave.open(f, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(16000)
            w.writeframes(b"\x00\x00" * 16000)  # 1 s de silence
        path = f.name
    try:
        transcribe(path)
        logger.info("Modèle Whisper préchargé.")
    except Exception:
        logger.exception("Échec du préchargement du modèle Whisper")
