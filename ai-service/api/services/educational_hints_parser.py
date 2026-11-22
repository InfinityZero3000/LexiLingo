"""
Educational Hints Parser

Extracts vocabulary hints from AI responses and strips hint markers from the
text the learner sees. Grammar corrections are NOT read from the model's prose:
the only source is the TRACE-CAG diagnosis, accepted by
``corrections_from_diagnosis`` only when its span really occurs in the
learner's own message.
"""

import re
import json
import logging
import unicodedata
from typing import Any, Optional, List, Tuple
from dataclasses import dataclass, field

logger = logging.getLogger(__name__)


@dataclass
class GrammarCorrection:
    """A grammar correction with explanation; ``label`` is a closed DIAGNOSIS_LABELS code."""
    original: str
    corrected: str
    explanation: str
    label: str = "other"
    rule: Optional[str] = None


@dataclass
class VocabularyHint:
    """A vocabulary hint with contextual definition"""
    term: str
    definition: str
    example: Optional[str] = None
    pronunciation: Optional[str] = None
    part_of_speech: Optional[str] = None


@dataclass
class EducationalHints:
    """Container for all educational hints in a response"""
    grammar_corrections: List[GrammarCorrection] = field(default_factory=list)
    vocabulary_hints: List[VocabularyHint] = field(default_factory=list)
    encouragement: Optional[str] = None
    detected_errors: List[str] = field(default_factory=list)

    def has_hints(self) -> bool:
        """Check if there are any hints."""
        return bool(self.grammar_corrections or self.vocabulary_hints)

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization."""
        return {
            "grammar_corrections": [
                {
                    "original": gc.original,
                    "corrected": gc.corrected,
                    "explanation": gc.explanation,
                    # `error_type` keeps the key older clients read.
                    "error_type": gc.label,
                    "label": gc.label,
                    "rule": gc.rule,
                }
                for gc in self.grammar_corrections
            ],
            "vocabulary_hints": [
                {
                    "term": vh.term,
                    "definition": vh.definition,
                    "example": vh.example,
                    "pronunciation": vh.pronunciation,
                    "part_of_speech": vh.part_of_speech,
                }
                for vh in self.vocabulary_hints
            ],
            "encouragement": self.encouragement,
            "detected_errors": self.detected_errors,
        }


class EducationalHintsParser:
    """
    Parser for extracting vocabulary hints from AI responses.

    Reads [📘 ...] brackets or a JSON block. [💡 Tip] brackets are removed from
    the visible text but never become corrections.
    """

    # The model doesn't always emit the exact emoji from the prompt (e.g. 📜 instead
    # of 📘), so match on the marker keyword instead of a hardcoded emoji glyph.
    _EMOJI_PREFIX = r'[^\w\[\]]{0,2}\s*'

    TIP_PATTERN = re.compile(
        r'\[' + _EMOJI_PREFIX + r'(?:Tip|Mẹo):?\s*([^\]]+)\]',
        re.IGNORECASE | re.UNICODE
    )

    VOCAB_PATTERN = re.compile(
        r"\[" + _EMOJI_PREFIX + r"['\"]?([^'\"\[\]]+)['\"]?\s*(?:means?|nghĩa là)\s*([^\]]+)\]",
        re.IGNORECASE | re.UNICODE
    )

    # Excludes Tip brackets so a generic emoji doesn't get miscategorized as vocab.
    VOCAB_PATTERN_SIMPLE = re.compile(
        r"\[" + _EMOJI_PREFIX + r"(?!(?:Tip|Mẹo)\b)([^\]]+)\]",
        re.IGNORECASE | re.UNICODE
    )

    @staticmethod
    def _norm(text: Any) -> str:
        return " ".join(unicodedata.normalize("NFKC", str(text or "")).casefold().split())

    @classmethod
    def corrections_from_diagnosis(
        cls,
        hints: Optional[EducationalHints],
        errors: Optional[List[dict]],
        user_text: str,
    ) -> Tuple[Optional[EducationalHints], List[dict]]:
        """
        Turn diagnosis errors into correction cards, keeping only those the
        learner's own message backs up: the span occurs in ``user_text`` and the
        correction differs from it. Returns ``(hints, accepted_errors)`` so the
        caller records exactly what was shown.
        """
        if not errors:
            return hints, []
        from api.services.trace_cag.nodes_v2 import (
            DIAGNOSIS_LABELS,
            DIAGNOSIS_LABEL_ALIASES,
            normalize_diagnosis_label,
        )

        text = cls._norm(user_text)
        accepted: List[dict] = []
        added: List[GrammarCorrection] = []
        seen: set = set()
        for err in errors:
            span = str(err.get("span") or "").strip()
            corrected = str(err.get("correction") or "").strip()
            span_n, corrected_n = cls._norm(span), cls._norm(corrected)
            if not span_n or not corrected_n or span_n == corrected_n:
                continue
            if span_n not in text or (span_n, corrected_n) in seen:
                continue
            # Two cards for one slip ("has"->"have" and "I has"->"I have had") read as
            # two mistakes; the diagnosis lists the most important first, so keep that one.
            if any(span_n in other or other in span_n for other, _ in seen):
                continue
            raw = normalize_diagnosis_label(err.get("type"))
            label = DIAGNOSIS_LABEL_ALIASES.get(raw, raw)
            if label not in DIAGNOSIS_LABELS:
                label = "other"
            seen.add((span_n, corrected_n))
            accepted.append(err)
            added.append(GrammarCorrection(
                original=span,
                corrected=corrected,
                explanation=str(err.get("explanation") or "").strip(),
                label=label,
                rule=raw or None,
            ))

        if not added:
            return hints, accepted
        if hints is None:
            hints = EducationalHints()
        hints.grammar_corrections.extend(added)
        return hints, accepted

    @classmethod
    def parse(cls, response: str) -> Tuple[str, Optional[EducationalHints]]:
        """
        Parse AI response to extract vocabulary hints.

        Returns (clean_response, hints). The clean response has hint markers
        removed.
        """
        hints = cls._try_parse_json(response)
        if hints:
            try:
                data = json.loads(response)
                clean = data.get("character_response", response)
                return clean, hints
            except json.JSONDecodeError:
                pass

        hints = cls._parse_brackets(response)
        clean_response = cls._remove_brackets(response)

        return clean_response, hints if hints and hints.has_hints() else None

    @classmethod
    def _try_parse_json(cls, response: str) -> Optional[EducationalHints]:
        """Try to parse response as JSON-structured output (vocabulary only)."""
        try:
            json_match = re.search(r'```json\s*(\{.*?\})\s*```', response, re.DOTALL)
            if json_match:
                data = json.loads(json_match.group(1))
            else:
                data = json.loads(response)

            if not isinstance(data, dict):
                return None

            hints = EducationalHints()
            ed_hints = data.get("educational_hints", {})
            for vh in ed_hints.get("vocabulary_hints", []):
                hints.vocabulary_hints.append(VocabularyHint(
                    term=vh.get("term", ""),
                    definition=vh.get("definition", ""),
                    example=vh.get("example"),
                    pronunciation=vh.get("pronunciation"),
                ))

            hints.encouragement = data.get("encouragement")

            return hints if hints.has_hints() else None

        except (json.JSONDecodeError, TypeError, KeyError, AttributeError):
            return None

    @classmethod
    def _parse_brackets(cls, response: str) -> EducationalHints:
        """Parse bracket-format vocabulary hints from response."""
        hints = EducationalHints()

        for match in cls.VOCAB_PATTERN.finditer(response):
            term = match.group(1).strip().strip("'\"")
            definition_part = match.group(2).strip()

            example = None
            if "Example:" in definition_part or "Ví dụ:" in definition_part:
                parts = re.split(r'Example:|Ví dụ:', definition_part, maxsplit=1)
                definition_part = parts[0].strip().rstrip('.')
                if len(parts) > 1:
                    example = parts[1].strip().strip('"\'')

            hints.vocabulary_hints.append(VocabularyHint(
                term=term,
                definition=definition_part,
                example=example,
            ))

        if not hints.vocabulary_hints:
            for match in cls.VOCAB_PATTERN_SIMPLE.finditer(response):
                full_text = match.group(1).strip()

                parts = re.split(r'\s+means?\s+|\s+nghĩa là\s+', full_text, maxsplit=1)
                if len(parts) == 2:
                    hints.vocabulary_hints.append(VocabularyHint(
                        term=parts[0].strip().strip("'\""),
                        definition=parts[1].strip(),
                    ))

        return hints

    @classmethod
    def _remove_brackets(cls, response: str) -> str:
        """Remove educational hint brackets from response."""
        clean = cls.TIP_PATTERN.sub('', response)

        clean = cls.VOCAB_PATTERN.sub('', clean)
        clean = cls.VOCAB_PATTERN_SIMPLE.sub('', clean)

        clean = re.sub(r'\s{2,}', ' ', clean)
        clean = re.sub(r'\s+([.,!?])', r'\1', clean)

        return clean.strip()

    @classmethod
    def format_for_display(cls, hints: EducationalHints) -> dict:
        """
        Format hints for frontend display.

        Returns a dictionary optimized for UI rendering.
        """
        result = {
            "has_grammar": bool(hints.grammar_corrections),
            "has_vocabulary": bool(hints.vocabulary_hints),
            "grammar_cards": [],
            "vocabulary_cards": [],
        }

        for gc in hints.grammar_corrections:
            result["grammar_cards"].append({
                "icon": "💡",
                "title": f"Grammar: {gc.label.replace('_', ' ').title()}",
                "content": gc.explanation,
                "before": gc.original,
                "after": gc.corrected,
            })

        for vh in hints.vocabulary_hints:
            result["vocabulary_cards"].append({
                "icon": "📘",
                "title": vh.term,
                "definition": vh.definition,
                "example": vh.example,
                "pronunciation": vh.pronunciation,
            })

        if hints.encouragement:
            result["encouragement"] = hints.encouragement

        return result
