"""Serveur local Murmure : dictée et transcription de réunions.

Tout tourne en local sur la machine (aucune donnée n'est envoyée sur
internet, à part le téléchargement initial des modèles depuis Hugging Face).
"""

import logging
import shutil
import tempfile
from contextlib import asynccontextmanager
from pathlib import Path

import anyio
from fastapi import FastAPI, File, Form, HTTPException, UploadFile

from . import cleanup, config, meeting, transcription

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s"
)
logger = logging.getLogger("murmure")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Précharge Whisper en arrière-plan pour une première dictée rapide.
    async with anyio.create_task_group() as tg:
        tg.start_soon(anyio.to_thread.run_sync, transcription.warm_up)
        yield
        tg.cancel_scope.cancel()


app = FastAPI(title="Murmure", lifespan=lifespan)


async def _save_upload(upload: UploadFile, tmp_dir: str, label: str = "audio") -> str:
    suffix = Path(upload.filename or "audio.wav").suffix or ".wav"
    dest = Path(tmp_dir) / f"{label}{suffix}"

    def _copy() -> None:  # hors de la boucle asyncio : le fichier peut être gros
        with dest.open("wb") as f:
            shutil.copyfileobj(upload.file, f)

    await anyio.to_thread.run_sync(_copy)
    return str(dest)


@app.get("/health")
async def health() -> dict:
    return {"status": "ok", "model": config.WHISPER_MODEL, "language": config.LANGUAGE}


def _dictation_prompt() -> str:
    """Prompt de dictée, enrichi du vocabulaire personnalisé s'il existe."""
    prompt = config.DICTATION_PROMPT
    try:
        if config.VOCAB_FILE.exists():
            words = [
                line.strip()
                for line in config.VOCAB_FILE.read_text(encoding="utf-8").splitlines()
                if line.strip() and not line.strip().startswith("#")
            ]
            if words:
                prompt += " Vocabulaire : " + ", ".join(words[:80]) + "."
    except OSError:
        logger.warning("Vocabulaire illisible : %s", config.VOCAB_FILE)
    return prompt


def _append_history(text: str) -> None:
    """Ajoute la dictée à l'historique local (Markdown)."""
    if not config.HISTORY_ENABLED or not text:
        return
    import datetime as dt

    try:
        config.HISTORY_FILE.parent.mkdir(parents=True, exist_ok=True)
        is_new = not config.HISTORY_FILE.exists()
        with config.HISTORY_FILE.open("a", encoding="utf-8") as f:
            if is_new:
                f.write("# Historique des dictées Murmure\n\n")
            f.write(f"- **{dt.datetime.now():%d/%m/%Y %H:%M}** — {text}\n")
    except OSError:
        logger.warning("Impossible d'écrire l'historique : %s", config.HISTORY_FILE)


@app.post("/dictate")
async def dictate(
    audio: UploadFile = File(...),
    language: str | None = Form(None),
) -> dict:
    """Transcrit un court enregistrement de dictée et renvoie le texte nettoyé.

    `language` : absent = langue de la config ; "auto" = détection
    automatique ; sinon un code langue ("fr", "en"…).
    """
    with tempfile.TemporaryDirectory() as tmp:
        path = await _save_upload(audio, tmp)
        prompt = _dictation_prompt()
        try:
            result = await anyio.to_thread.run_sync(
                lambda: transcription.transcribe(
                    path, initial_prompt=prompt, language_override=language
                )
            )
        except Exception as exc:  # noqa: BLE001
            logger.exception("Échec de la dictée")
            raise HTTPException(status_code=500, detail=str(exc)) from exc
    text = cleanup.clean_dictation(result.get("text", ""))
    logger.info("Dictée : %r", text)
    _append_history(text)
    return {"text": text, "language": result.get("language")}


@app.post("/meeting")
async def meeting_endpoint(
    mic: UploadFile | None = File(None),
    system: UploadFile | None = File(None),
    mode: str = Form("in_person"),
    title: str = Form("Réunion"),
    mic_offset: float = Form(0.0),
    system_offset: float = Form(0.0),
    notes: str = Form(""),
) -> dict:
    """Transcrit une réunion avec identification des locuteurs.

    - mode=in_person : la piste `mic` contient tout le monde, elle est diarizée.
    - mode=remote    : `mic` = l'utilisateur, `system` = l'audio Teams/visio.
    Les offsets (secondes) recalent chaque piste sur l'horloge commune de
    l'enregistrement, les deux ne démarrant pas exactement en même temps.
    """
    if mic is None and system is None:
        raise HTTPException(status_code=400, detail="Aucune piste audio fournie.")
    if mode not in ("in_person", "remote"):
        raise HTTPException(status_code=400, detail=f"Mode inconnu : {mode}")

    with tempfile.TemporaryDirectory() as tmp:
        mic_path = await _save_upload(mic, tmp, "mic") if mic is not None else None
        system_path = (
            await _save_upload(system, tmp, "system") if system is not None else None
        )
        try:
            result = await anyio.to_thread.run_sync(
                lambda: meeting.process_meeting(
                    mic_path, system_path, mode, title,
                    mic_offset=mic_offset, system_offset=system_offset,
                    notes=notes,
                )
            )
        except Exception as exc:  # noqa: BLE001
            logger.exception("Échec du traitement de la réunion")
            raise HTTPException(status_code=500, detail=str(exc)) from exc
    return result


def run() -> None:
    import uvicorn

    uvicorn.run(app, host=config.HOST, port=config.PORT)


if __name__ == "__main__":
    run()
