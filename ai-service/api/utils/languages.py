"""ISO 639-1 code -> English language name, scoped to the onboarding language
list in flutter-app/lib/core/l10n/app_localizations.dart (AppLocales.metadata).
"""

from __future__ import annotations

_ISO_TO_LANGUAGE_NAME: dict[str, str] = {
    "vi": "Vietnamese",
    "en": "English",
    "ja": "Japanese",
    "ko": "Korean",
    "zh": "Chinese",
    "fr": "French",
    "es": "Spanish",
}


def iso_to_language_name(code: str) -> str:
    return _ISO_TO_LANGUAGE_NAME.get((code or "").strip().lower(), "Vietnamese")
