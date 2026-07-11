"""Compte-rendu de réunion façon Granola, généré par un LLM local (Ollama).

À partir de la transcription diarizée, produit un Markdown structuré :
résumé, décisions, actions, points ouverts. Tout reste sur la machine.
"""

import logging
import re

import httpx

from . import config

logger = logging.getLogger(__name__)

# Au-delà de cette taille, la transcription est résumée en plusieurs passes
# (résumés partiels puis synthèse) pour tenir dans le contexte du modèle.
_CHUNK_CHARS = 20_000

_SYSTEM_PROMPT = (
    "Tu es un assistant qui rédige des comptes-rendus de réunion en français, "
    "précis et factuels. Tu t'appuies UNIQUEMENT sur la transcription fournie : "
    "tu n'inventes jamais d'information, de décision ni de nom. Si un point est "
    "ambigu, tu le signales comme tel."
)

_FINAL_PROMPT = """Voici la transcription d'une réunion intitulée « {title} », \
avec l'identité des intervenants et les horodatages.

Rédige le compte-rendu en Markdown avec exactement ces sections :

## Résumé
3 à 6 phrases : contexte, sujets abordés, conclusion générale.

## Décisions
Liste à puces des décisions actées. Écris « _Aucune décision explicite._ » si besoin.

## Actions
Liste à puces au format « **Qui** : quoi (échéance si mentionnée) ». \
Attribue chaque action à un intervenant seulement si c'est clair dans la \
transcription. Écris « _Aucune action identifiée._ » si besoin.

## Points ouverts
Questions restées sans réponse, sujets à retraiter, désaccords.

Ne recopie pas la transcription, ne commente pas ta démarche, réponds \
uniquement avec le compte-rendu.

Transcription :

{transcript}"""

_PARTIAL_PROMPT = """Voici un extrait (partie {index}/{total}) de la transcription \
d'une réunion intitulée « {title} ».

Résume fidèlement cet extrait en 10 lignes maximum : sujets abordés, \
décisions, actions évoquées (avec qui), questions ouvertes. Conserve les noms \
des intervenants. Réponds uniquement avec le résumé.

Extrait :

{transcript}"""

_MERGE_PROMPT = """Voici les résumés successifs des différentes parties d'une \
réunion intitulée « {title} », dans l'ordre chronologique.

À partir de ces résumés, rédige le compte-rendu final en Markdown avec \
exactement ces sections : « ## Résumé » (3 à 6 phrases), « ## Décisions », \
« ## Actions » (format « **Qui** : quoi »), « ## Points ouverts ». \
N'invente rien. Réponds uniquement avec le compte-rendu.

Résumés :

{transcript}"""


def _fmt_ts(seconds: float) -> str:
    s = int(seconds)
    return f"{s // 3600:02d}:{(s % 3600) // 60:02d}:{s % 60:02d}"


def format_transcript(segments: list[dict]) -> str:
    """Transcription compacte « [hh:mm:ss] Intervenant : texte »."""
    return "\n".join(
        f"[{_fmt_ts(seg['start'])}] {seg.get('speaker', '?')} : {seg['text']}"
        for seg in segments
    )


def _split_chunks(transcript: str) -> list[str]:
    if len(transcript) <= _CHUNK_CHARS:
        return [transcript]
    chunks: list[str] = []
    current: list[str] = []
    size = 0
    for line in transcript.splitlines():
        if size + len(line) > _CHUNK_CHARS and current:
            chunks.append("\n".join(current))
            current, size = [], 0
        current.append(line)
        size += len(line) + 1
    if current:
        chunks.append("\n".join(current))
    return chunks


def _strip_thinking(text: str) -> str:
    """Retire les blocs de raisonnement (<think>…</think>) que certains
    modèles (Qwen…) préfixent à leur réponse."""
    return re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL).strip()


def _call_ollama(prompt: str) -> str:
    response = httpx.post(
        f"{config.OLLAMA_URL.rstrip('/')}/api/chat",
        json={
            "model": config.SUMMARY_MODEL,
            "messages": [
                {"role": "system", "content": _SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ],
            "stream": False,
            "options": {"temperature": 0.3},
        },
        timeout=600.0,
    )
    response.raise_for_status()
    return _strip_thinking(response.json()["message"]["content"])


def generate(title: str, segments: list[dict]) -> str:
    """Génère le compte-rendu Markdown. Lève une exception si Ollama est
    injoignable ou si le modèle n'est pas disponible (l'appelant décide
    d'en faire une erreur bloquante ou non)."""
    transcript = format_transcript(segments)
    if not transcript.strip():
        raise ValueError("Transcription vide, rien à résumer.")

    chunks = _split_chunks(transcript)
    logger.info(
        "Compte-rendu via %s (%d caractères, %d partie(s))…",
        config.SUMMARY_MODEL, len(transcript), len(chunks),
    )

    if len(chunks) == 1:
        return _call_ollama(_FINAL_PROMPT.format(title=title, transcript=chunks[0]))

    partials = [
        _call_ollama(_PARTIAL_PROMPT.format(
            index=i + 1, total=len(chunks), title=title, transcript=chunk
        ))
        for i, chunk in enumerate(chunks)
    ]
    return _call_ollama(_MERGE_PROMPT.format(
        title=title, transcript="\n\n---\n\n".join(partials)
    ))
