"""Diarization locale (qui parle quand) avec pyannote.audio."""

import logging
import threading

from . import config

logger = logging.getLogger(__name__)

_pipeline = None
_lock = threading.Lock()


def _get_pipeline():
    global _pipeline
    with _lock:
        if _pipeline is None:
            import torch
            from pyannote.audio import Pipeline

            logger.info("Chargement du pipeline de diarization %s…", config.DIARIZATION_MODEL)
            try:
                _pipeline = Pipeline.from_pretrained(
                    config.DIARIZATION_MODEL, token=config.HF_TOKEN
                )
            except TypeError:
                # Anciennes versions de pyannote/huggingface_hub.
                _pipeline = Pipeline.from_pretrained(
                    config.DIARIZATION_MODEL, use_auth_token=config.HF_TOKEN
                )
            if _pipeline is None:
                raise RuntimeError(
                    "Impossible de charger le pipeline pyannote. Vérifie que tu as "
                    "accepté les conditions du modèle sur Hugging Face et que tu es "
                    "connecté (huggingface-cli login) ou que HF_TOKEN est défini."
                )
            # CPU par défaut : sur Apple Silicon, le backend MPS de PyTorch
            # produit des embeddings de voix dégradés avec pyannote, et le
            # clustering fusionne alors tous les locuteurs en un seul.
            # MURMURE_DIARIZATION_DEVICE=mps pour retenter le GPU.
            import os

            device = os.environ.get("MURMURE_DIARIZATION_DEVICE", "cpu").lower()
            if device == "mps":
                try:
                    _pipeline.to(torch.device("mps"))
                    logger.info("Diarization sur GPU (MPS), à la demande.")
                except Exception:
                    logger.info("MPS indisponible, diarization sur CPU.")
            else:
                logger.info(
                    "Diarization sur CPU (fiable ; MURMURE_DIARIZATION_DEVICE=mps "
                    "pour essayer le GPU)."
                )
        return _pipeline


def diarize(audio_path: str) -> list[dict]:
    """Retourne une liste de tours de parole :
    [{"start": float, "end": float, "speaker": "SPEAKER_00"}, ...]"""
    pipeline = _get_pipeline()
    logger.info("Diarization de %s…", audio_path)
    result = pipeline(audio_path)
    # pyannote 3.x renvoie une Annotation ; pyannote 4.x l'enveloppe dans
    # un DiarizeOutput (champ speaker_diarization).
    if hasattr(result, "itertracks"):
        annotation = result
    elif hasattr(result, "speaker_diarization"):
        annotation = result.speaker_diarization
    else:
        raise RuntimeError(
            f"Résultat de diarization inattendu : {type(result).__name__}"
        )
    turns = [
        {"start": float(turn.start), "end": float(turn.end), "speaker": str(speaker)}
        for turn, _, speaker in annotation.itertracks(yield_label=True)
    ]
    logger.info("Diarization terminée : %d tours, %d locuteurs",
                len(turns), len({t["speaker"] for t in turns}))
    return turns


def assign_speakers(segments: list[dict], turns: list[dict],
                    default: str = "Inconnu") -> None:
    """Attribue à chaque segment Whisper le locuteur dont le tour de parole
    recouvre le plus le segment (modifie `segments` en place)."""

    def overlap(seg: dict, turn: dict) -> float:
        return max(0.0, min(seg["end"], turn["end"]) - max(seg["start"], turn["start"]))

    for seg in segments:
        best, best_ov = default, 0.0
        for turn in turns:
            ov = overlap(seg, turn)
            if ov > best_ov:
                best, best_ov = turn["speaker"], ov
        seg["speaker"] = best
