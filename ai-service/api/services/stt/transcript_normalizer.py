"""Conservative transcript normalization."""

import re


def normalize_transcript(
    text: str, preserve_exact: bool = False
) -> tuple[str, list[str]]:
    original = text
    text = re.sub(r"\s+", " ", text).strip()
    rules = ["trim"] if text != original else []
    if text and not preserve_exact and text[-1] not in ".?!":
        text += "."
        rules.append("punctuation")
    return text, rules
