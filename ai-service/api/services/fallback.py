"""
Rule-Based Fallback System

Simple grammar checker for when AI models fail.
Uses pattern matching for common English errors.
"""

import re
from typing import Dict, List, Any, Tuple


class RuleBasedChecker:
    """
    Rule-based grammar checker.
    
    Provides basic grammar checking as fallback when Qwen/LLaMA fail.
    Uses regex patterns to detect common errors.
    """
    
    def __init__(self):
        """Initialize with common error patterns."""
        
        # Grammar error patterns
        # Format: (pattern, error_type, message, correction_hint)
        self.patterns: List[Tuple[str, str, str, str]] = [
            # Subject-Verb Agreement
            (
                r"\b(I|you|we|they)\s+is\b",
                "subject_verb_agreement",
                "Subject-verb disagreement: Use 'am' or 'are' with I/you/we/they",
                "Replace 'is' with 'am' (for I) or 'are' (for you/ we/they)"
            ),
            (
                r"\b(I|you|we|they)\s+(goes|does|has)\b",
                "subject_verb_agreement",
                "Subject-verb disagreement: Don't use singular verbs with I/you/we/they",
                "Use 'go', 'do', or 'have' instead of 'goes', 'does', or 'has'"
            ),
            (
                r"\b(he|she|it)\s+are\b",
                "subject_verb_agreement",
                "Subject-verb disagreement: Use 'is' with he/she/it",
                "Replace 'are' with 'is'"
            ),
            (
                r"\b(he|she|it)\s+(go|do|have)\b",
                "subject_verb_agreement",
                "Subject-verb disagreement: Use singular verbs with he/she/it",
                "Use 'goes', 'does', or 'has' instead"
            ),
            (
                r"\b(I|you|we|they)\s+was\b",
                "subject_verb_agreement",
                "Subject-verb disagreement in past tense",
                "Use 'were' instead of 'was' with you/we/they"
            ),
            
            
            # Tense Errors
            (
                r"(\byesterday.*\b(go|goes|come|comes|eat|eats)\b|\b(go|goes|come|comes|eat|eats).*yesterday\b)",
                "tense",
                "Wrong tense: Use past tense with 'yesterday'",
                "Use past tense (went, came, ate) with 'yesterday'"
            ),
            (
                r"(\btomorrow.*\b(went|gone|came|ate)\b|\b(went|gone|came|ate).*tomorrow\b)",
                "tense",
                "Wrong tense: Use future tense with 'tomorrow'",
                "Use 'will go/come/eat' for future actions"
            ),
            (
                r"(\blast (week|month|year).*\b(go|come|eat|play)\b|\b(go|come|eat|play).*last (week|month|year)\b)",
                "tense",
                "Wrong tense: Use past tense with 'last week/month/year'",
                "Use past tense (went, came, ate, played)"
            ),
            
            # Article Errors
            (
                r"\ba\s+[aeiouAEIOU]",
                "article",
                "Article error: Use 'an' before vowel sounds",
                "Replace 'a' with 'an' before vowels"
            ),
            (
                r"\ban\s+[bcdfghjklmnpqrstvwxyzBCDFGHJKLMNPQRSTVWXYZ]",
                "article",
                "Article error: Use 'a' before consonant sounds",
                "Replace 'an' with 'a' before consonants"
            ),
            
            # Common Word Confusions
            (
                r"\bthere\s+(is|are)\s+\d+\s+people\b",
                "word_choice",
                "Use 'their' for possession, 'there' for location",
                "Check if you mean 'Their are X people' (possession)"
            ),
            
            # Double Negatives
            (
                r"\bdon't\s+(never|nobody|nothing|nowhere|no\s+\w+)\b",
                "double_negative",
                "Double negative: Avoid using two negatives together",
                "Use 'don't ever' instead of 'don't never'"
            ),
            
            # Missing Auxiliary
            (
                r"\b(I|you|we|they|he|she|it)\s+not\s+(go|come|like|want)\b",
                "auxiliary",
                "Missing auxiliary verb",
                "Add 'do/does' before 'not' (e.g., 'I do not go')"
            ),
        ]
    
    def check_grammar(self, text: str) -> Dict[str, Any]:
        """
        Check grammar using pattern matching.
        
        Args:
            text: Input text to check
            
        Returns:
            Analysis dict compatible with Qwen output format
        """
        errors = []
        
        # Check all patterns
        for pattern, error_type, message, correction in self.patterns:
            matches = re.finditer(pattern, text, re.IGNORECASE)
            
            for match in matches:
                errors.append({
                    "type": error_type,
                    "message": message,
                    "correction": correction,
                    "position": match.start(),
                    "matched_text": match.group(),
                    "severity": "medium"
                })
        
        # Calculate fluency score (simple heuristic)
        # Starts at 0.7, reduces by 0.1 per error
        fluency = max(0.3, 0.7 - len(errors) * 0.1)
        
        # Estimate vocabulary level (simple word count heuristic)
        vocabulary_level = self._estimate_vocabulary_level(text)
        
        return {
            "fluency_score": fluency,
            "vocabulary_level": vocabulary_level,
            "grammar": {
                "errors": errors,
                "corrected": text,  # No auto-correction
                "total_errors": len(errors)
            },
            "tutor_response": self._generate_tutor_response(errors),
            "confidence": 0.6,  # Low confidence for rule-based
            "strategy_used": "rule_based_fallback"
        }
    
    def _estimate_vocabulary_level(self, text: str) -> str:
        """
        Estimate vocabulary level based on word complexity.
        
        Simple heuristic: longer words = higher level
        """
        words = text.split()
        
        if not words:
            return "A1"
        
        avg_word_length = sum(len(word) for word in words) / len(words)
        
        # Simple mapping
        if avg_word_length < 4:
            return "A1"
        elif avg_word_length < 5:
            return "A2"
        elif avg_word_length < 6:
            return "B1"
        elif avg_word_length < 7:
            return "B2"
        else:
            return "C1"
    
    def _generate_tutor_response(self, errors: List[Dict[str, Any]]) -> str:
        """
        Generate tutor response based on errors found.
        
        Args:
            errors: List of detected errors
            
        Returns:
            Friendly tutor message
        """
        if not errors:
            return "Good job! I didn't detect any obvious errors."
        
        if len(errors) == 1:
            error = errors[0]
            return f"I noticed a {error['type'].replace('_', ' ')} error. {error['correction']}"
        
        # Multiple errors
        error_types = list(set(e["type"] for e in errors))
        
        if len(error_types) == 1:
            return f"I found {len(errors)} {error_types[0].replace('_', ' ')} errors. Let's work on fixing these."
        else:
            return f"I found {len(errors)} errors across different areas. Let me help you improve!"


def get_fallback_checker() -> RuleBasedChecker:
    """
    Get RuleBasedChecker singleton.
    
    Returns:
        RuleBasedChecker instance
    """
    return RuleBasedChecker()
