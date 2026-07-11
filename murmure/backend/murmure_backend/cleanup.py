"""Nettoyage léger du texte dicté (hésitations, espaces, ponctuation FR)."""

import re

# Hésitations courantes que Whisper laisse parfois passer.
_FILLERS = re.compile(
    r"\b(euh+|heu+|hum+|hmm+|mmh+|bah euh)\b[ ,]*",
    re.IGNORECASE,
)

_MULTI_SPACE = re.compile(r"[ \t]{2,}")
_SPACE_BEFORE_PUNCT = re.compile(r" +([,.])")


def clean_dictation(text: str) -> str:
    text = text.strip()
    text = _FILLERS.sub("", text)
    text = _MULTI_SPACE.sub(" ", text)
    text = _SPACE_BEFORE_PUNCT.sub(r"\1", text)
    text = text.strip()
    if text and text[0].islower():
        text = text[0].upper() + text[1:]
    return text
