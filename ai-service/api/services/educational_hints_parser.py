"""
Educational Hints Parser (Enhanced v2.0)

Parses AI responses to extract educational hints:
- Grammar corrections with explanations
- Vocabulary hints with contextual definitions
- Pronunciation tips
- Encouragement messages

Supports both:
- Bracket-based format: [💡 Tip: ...] and [📘 ...]
- JSON-structured output
"""

import re
import json
import logging
from typing import Optional, List, Tuple
from dataclasses import dataclass, field
from enum import Enum

logger = logging.getLogger(__name__)


class GrammarErrorType(str, Enum):
    """Types of grammar errors"""
    SUBJECT_VERB = "subject_verb_agreement"
    TENSE = "tense_error"
    ARTICLE = "article_error"
    PREPOSITION = "preposition_error"
    PLURAL = "plural_error"
    WORD_ORDER = "word_order"
    PRONOUN = "pronoun_error"
    OTHER = "other"


@dataclass
class GrammarCorrection:
    """A grammar correction with explanation"""
    original: str
    corrected: str
    explanation: str
    error_type: GrammarErrorType = GrammarErrorType.OTHER
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
                    "error_type": gc.error_type.value,
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
    Parser for extracting educational hints from AI responses.
    
    Supports two formats:
    1. Bracket format: [💡 Tip: ...] and [📘 ...]
    2. JSON format: structured JSON output
    """
    
    # Regex patterns for bracket format
    TIP_PATTERN = re.compile(
        r'\[💡\s*(?:Tip|Mẹo)?:?\s*([^\]]+)\]',
        re.IGNORECASE | re.UNICODE
    )
    
    VOCAB_PATTERN = re.compile(
        r"\[📘\s*['\"]?([^'\"]+)['\"]?\s*(?:means?|nghĩa là)?\s*([^\]]+)\]",
        re.IGNORECASE | re.UNICODE
    )
    
    # Alternative vocab pattern for simpler format
    VOCAB_PATTERN_SIMPLE = re.compile(
        r"\[📘\s*([^\]]+)\]",
        re.IGNORECASE | re.UNICODE
    )
    
    # Grammar error type detection patterns
    GRAMMAR_TYPE_PATTERNS = {
        GrammarErrorType.SUBJECT_VERB: [
            r"subject.?verb", r"she/he/it", r"has\s+not\s+have",
            r"is\s+not\s+are", r"was\s+not\s+were"
        ],
        GrammarErrorType.TENSE: [
            r"past\s+tense", r"present\s+tense", r"future",
            r"went\s+not\s+go", r"did\s+not\s+do"
        ],
        GrammarErrorType.ARTICLE: [
            r"article", r"a/an", r"the", r"uncountable",
            r"no\s+article", r"definite\s+article"
        ],
        GrammarErrorType.PREPOSITION: [
            r"preposition", r"at/in/on", r"to\s+not\s+at",
            r"arrive\s+at", r"depend\s+on"
        ],
        GrammarErrorType.PLURAL: [
            r"plural", r"singular", r"many/much",
            r"few/little", r"countable"
        ],
    }
    
    @classmethod
    def parse(cls, response: str) -> Tuple[str, Optional[EducationalHints]]:
        """
        Parse AI response to extract educational hints.
        
        Args:
            response: The AI response text
            
        Returns:
            Tuple of (clean_response, educational_hints)
            - clean_response: Response with hints removed
            - educational_hints: Extracted hints or None
        """
        # Try JSON parsing first
        hints = cls._try_parse_json(response)
        if hints:
            # Extract clean response from JSON
            try:
                data = json.loads(response)
                clean = data.get("character_response", response)
                return clean, hints
            except json.JSONDecodeError:
                pass
        
        # Fall back to bracket parsing
        hints = cls._parse_brackets(response)
        clean_response = cls._remove_brackets(response)
        
        return clean_response, hints if hints and hints.has_hints() else None
    
    @classmethod
    def _try_parse_json(cls, response: str) -> Optional[EducationalHints]:
        """Try to parse response as JSON-structured output."""
        try:
            # Look for JSON block in response
            json_match = re.search(r'```json\s*(\{.*?\})\s*```', response, re.DOTALL)
            if json_match:
                data = json.loads(json_match.group(1))
            else:
                # Try direct JSON parse
                data = json.loads(response)
            
            if not isinstance(data, dict):
                return None
            
            hints = EducationalHints()
            
            # Parse grammar corrections
            ed_hints = data.get("educational_hints", {})
            for gc in ed_hints.get("grammar_corrections", []):
                hints.grammar_corrections.append(GrammarCorrection(
                    original=gc.get("error", ""),
                    corrected=gc.get("correction", ""),
                    explanation=gc.get("explanation", ""),
                    error_type=cls._detect_error_type(gc.get("rule", "")),
                    rule=gc.get("rule"),
                ))
            
            # Parse vocabulary hints
            for vh in ed_hints.get("vocabulary_hints", []):
                hints.vocabulary_hints.append(VocabularyHint(
                    term=vh.get("term", ""),
                    definition=vh.get("definition", ""),
                    example=vh.get("example"),
                    pronunciation=vh.get("pronunciation"),
                ))
            
            hints.detected_errors = data.get("detected_errors", [])
            hints.encouragement = data.get("encouragement")
            
            return hints if hints.has_hints() else None
            
        except (json.JSONDecodeError, TypeError, KeyError):
            return None
    
    @classmethod
    def _parse_brackets(cls, response: str) -> EducationalHints:
        """Parse bracket-format hints from response."""
        hints = EducationalHints()
        
        # Extract grammar tips
        for match in cls.TIP_PATTERN.finditer(response):
            tip_text = match.group(1).strip()
            
            # Try to extract original/corrected from tip
            correction = cls._parse_tip_text(tip_text)
            hints.grammar_corrections.append(correction)
        
        # Extract vocabulary hints (full pattern)
        for match in cls.VOCAB_PATTERN.finditer(response):
            term = match.group(1).strip().strip("'\"")
            definition_part = match.group(2).strip()
            
            # Try to extract example from definition
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
        
        # Try simple vocab pattern if no matches
        if not hints.vocabulary_hints:
            for match in cls.VOCAB_PATTERN_SIMPLE.finditer(response):
                full_text = match.group(1).strip()
                
                # Try to parse "word means definition" format
                parts = re.split(r'\s+means?\s+|\s+nghĩa là\s+', full_text, maxsplit=1)
                if len(parts) == 2:
                    hints.vocabulary_hints.append(VocabularyHint(
                        term=parts[0].strip().strip("'\""),
                        definition=parts[1].strip(),
                    ))
        
        return hints
    
    @classmethod
    def _parse_tip_text(cls, tip_text: str) -> GrammarCorrection:
        """Parse a tip text to extract correction details."""
        original = ""
        corrected = ""
        explanation = tip_text
        
        # Try patterns like "We say X not Y" or "Use X instead of Y"
        patterns = [
            r"(?:We say|Use)\s+['\"]?(\w+)['\"]?\s+(?:not|instead of)\s+['\"]?(\w+)['\"]?",
            r"['\"]?(\w+)['\"]?\s+(?:not)\s+['\"]?(\w+)['\"]?",
        ]
        
        for pattern in patterns:
            match = re.search(pattern, tip_text, re.IGNORECASE)
            if match:
                corrected = match.group(1)
                original = match.group(2)
                break
        
        # Detect error type
        error_type = cls._detect_error_type(tip_text)
        
        return GrammarCorrection(
            original=original,
            corrected=corrected,
            explanation=explanation,
            error_type=error_type,
        )
    
    @classmethod
    def _detect_error_type(cls, text: str) -> GrammarErrorType:
        """Detect the type of grammar error from explanation text."""
        text_lower = text.lower()
        
        for error_type, patterns in cls.GRAMMAR_TYPE_PATTERNS.items():
            for pattern in patterns:
                if re.search(pattern, text_lower):
                    return error_type
        
        return GrammarErrorType.OTHER
    
    @classmethod
    def _remove_brackets(cls, response: str) -> str:
        """Remove educational hint brackets from response."""
        # Remove tip brackets
        clean = cls.TIP_PATTERN.sub('', response)
        
        # Remove vocab brackets
        clean = cls.VOCAB_PATTERN.sub('', clean)
        clean = cls.VOCAB_PATTERN_SIMPLE.sub('', clean)
        
        # Clean up extra whitespace
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
                "title": f"Grammar: {gc.error_type.value.replace('_', ' ').title()}",
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
