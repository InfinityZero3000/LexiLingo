"""ARPAbet (CMUdict) to IPA, the notation `VocabularyItem.pronunciation` stores."""

from __future__ import annotations

import re

# General American, phonemic: no stress marks (they need syllabification and a
# wrong mark is worse than none). The stress digit is still needed for the two
# vowels it changes: AH0 is a schwa but AH1/2 is /ʌ/, ER0 is /ɚ/ but ER1/2 is /ɝ/.
_PHONEME = re.compile(r"^([A-Z]+)([012])?$")
_ARPABET_TO_IPA: dict[str, str] = {
    "AA": "ɑ", "AE": "æ", "AO": "ɔ", "AW": "aʊ", "AY": "aɪ",
    "B": "b", "CH": "tʃ", "D": "d", "DH": "ð", "EH": "ɛ",
    "EY": "eɪ", "F": "f", "G": "ɡ", "HH": "h", "IH": "ɪ", "IY": "i",
    "JH": "dʒ", "K": "k", "L": "l", "M": "m", "N": "n", "NG": "ŋ",
    "OW": "oʊ", "OY": "ɔɪ", "P": "p", "R": "r", "S": "s", "SH": "ʃ",
    "T": "t", "TH": "θ", "UH": "ʊ", "UW": "u", "V": "v", "W": "w",
    "Y": "j", "Z": "z", "ZH": "ʒ",
}
# (unstressed, stressed); a bare vowel with no digit is read as unstressed.
_STRESS_DEPENDENT: dict[str, tuple[str, str]] = {"AH": ("ə", "ʌ"), "ER": ("ɚ", "ɝ")}
_MAX_LENGTH = 100


def _phoneme_to_ipa(token: str) -> str | None:
    match = _PHONEME.match(token)
    if match is None:
        return None
    base, stress = match.groups()
    if base in _STRESS_DEPENDENT:
        unstressed, stressed = _STRESS_DEPENDENT[base]
        return stressed if stress in ("1", "2") else unstressed
    return _ARPABET_TO_IPA.get(base)


def arpabet_to_ipa(arpabet: str) -> str | None:
    """`HH AH0 L OW1` -> `/həloʊ/`; None when any phoneme is unknown."""
    phonemes = [_phoneme_to_ipa(token) for token in arpabet.split()]
    if not phonemes or None in phonemes:
        return None
    ipa = f"/{''.join(p for p in phonemes if p)}/"
    return ipa if len(ipa) <= _MAX_LENGTH else None
