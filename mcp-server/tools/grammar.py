"""
Grammar Evaluation Tool
Rule-based + LLM fallback for grammar checking
"""

import logging
from typing import Any, Dict, List
import re

logger = logging.getLogger(__name__)

# Simple rule-based grammar patterns
GRAMMAR_RULES = [
    {
        "pattern": r"\b(have|has)\s+(went|done|been)\b",
        "error_type": "tense",
        "message": "Incorrect use of present perfect. Use 'have/has gone/done/been'",
        "example": "I have gone (not 'have went')",
    },
    {
        "pattern": r"\b(is|are|was|were)\s+\w+ing\s+to\b",
        "error_type": "tense",
        "message": "Use 'going to' for future plans, not 'is/are -ing to'",
        "example": "I am going to school (not 'I am going to go to school')",
    },
    {
        "pattern": r"\b(a)\s+[aeiou]",
        "error_type": "article",
        "message": "Use 'an' before vowel sounds",
        "example": "an apple (not 'a apple')",
    },
    {
        "pattern": r"\b(much)\s+(books|people|students)\b",
        "error_type": "quantifier",
        "message": "Use 'many' with countable nouns, not 'much'",
        "example": "many books (not 'much books')",
    },
]


def check_with_rules(sentence: str) -> List[Dict[str, Any]]:
    """Check sentence against rule-based patterns"""
    errors = []
    
    for rule in GRAMMAR_RULES:
        matches = re.finditer(rule["pattern"], sentence, re.IGNORECASE)
        for match in matches:
            errors.append({
                "type": rule["error_type"],
                "error": match.group(0),
                "message": rule["message"],
                "example": rule["example"],
                "start": match.start(),
                "end": match.end(),
            })
    
    return errors


async def check_with_llm(sentence: str, user_level: str = None) -> Dict[str, Any]:
    """Fallback to LLM for complex grammar checking"""
    try:
        from handlers.qwen import QwenHandler
        
        qwen = QwenHandler()
        await qwen.load()
        
        prompt = f"""Analyze the following sentence for grammar errors:
Sentence: "{sentence}"
{"User level: " + user_level if user_level else ""}

Provide:
1. List of errors (if any)
2. Corrections
3. Brief explanation

Format as JSON."""
        
        response = await qwen.chat(
            message=prompt,
            context={"task": "grammar_check"},
        )
        
        return {
            "llm_response": response.get("text", ""),
            "method": "llm",
        }
    
    except Exception as e:
        logger.error(f"LLM grammar check error: {e}")
        return {
            "error": str(e),
            "method": "llm",
        }


async def execute(args: Dict[str, Any]) -> Dict[str, Any]:
    """
    Execute grammar evaluation
    
    Args:
        sentence: Sentence to evaluate
        detailed: Include detailed explanations
        user_level: User's CEFR level
    
    Returns:
        errors: List of detected errors
        corrections: Suggested corrections
        explanations: Detailed explanations
        method: "rules" or "llm"
    """
    sentence = args.get("sentence", "")
    detailed = args.get("detailed", True)
    user_level = args.get("user_level")
    
    if not sentence:
        return {"error": "Sentence is required"}
    
    logger.info(f"Grammar check: sentence_len={len(sentence)}, detailed={detailed}")
    
    try:
        # First, try rule-based checking
        rule_errors = check_with_rules(sentence)
        
        # If no errors found or detailed analysis requested, use LLM
        if not rule_errors or detailed:
            llm_result = await check_with_llm(sentence, user_level)
            
            return {
                "rule_based_errors": rule_errors,
                "llm_analysis": llm_result,
                "method": "hybrid",
                "sentence": sentence,
            }
        
        else:
            return {
                "errors": rule_errors,
                "method": "rules",
                "sentence": sentence,
            }
    
    except Exception as e:
        logger.error(f"Grammar evaluation error: {e}", exc_info=True)
        return {
            "error": str(e),
            "sentence": sentence,
        }
