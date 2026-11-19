"""AI draft of a whole topic from a title: what an admin would otherwise write field by field.

One model call, checked for shape and filler, then handed back for the admin to
review. Nothing here saves a story, and nothing runs the per-sentence grammar
gate the bulk enrichment script uses: that costs ~40 calls a topic and Groq's
daily budget is shared with live chat. The admin is the gate.
"""

from __future__ import annotations

import json
import logging
import os
from typing import Any, Awaitable, Callable

from api.services.story_filler import (
    is_placeholder_definition,
    is_template_grammar_explanation,
    is_template_grammar_usage,
    is_template_vocab_example,
)
from api.services.topic_meta import TOPIC_CATEGORIES, infer_topic_meta

logger = logging.getLogger(__name__)

GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
PARTS_OF_SPEECH = {
    "noun", "noun phrase", "verb", "verb phrase", "phrasal verb",
    "adjective", "adverb", "preposition", "expression",
}
VOCAB_RANGE = (6, 10)
GRAMMAR_RANGE = (2, 3)

LLM = Callable[[str], Awaitable[Any]]


class DraftError(Exception):
    """The draft could not be produced; the message says why, for the admin."""


def build_draft_prompt(
    title_en: str, level: str, category: str, notes: str, problems: list[str] | None = None
) -> str:
    retry = ""
    if problems:
        listed = "\n".join(f"- {p}" for p in problems[:10])
        retry = f"\nYour previous answer was rejected for these reasons, fix every one:\n{listed}\n"
    extra = f"\nThe admin's notes (follow them): {notes.strip()}\n" if notes and notes.strip() else ""
    return f"""You design a role-play English conversation topic for a language-learning app.

Topic: {title_en}
CEFR level of the learner: {level}
Category: {category}{extra}
Return one JSON object:
{{
  "title_vi": "natural Vietnamese title for this topic, with diacritics",
  "role_persona": {{"name": "...", "role": "...", "personality": "...", "speaking_style": "...", "background": "..."}},
  "context_description": {{"setting": "...", "scenario": "...", "objectives": ["...", "...", "..."]}},
  "opening_prompt": "...",
  "suggested_prompts": ["...", "...", "..."],
  "vocabulary_list": [{{"term": "...", "definition": "...", "example_in_story": "...", "part_of_speech": "..."}}],
  "grammar_points": [{{"grammar_structure": "...", "explanation": "...", "usage_in_story": "...", "examples": ["...", "..."]}}],
  "estimated_minutes": 15
}}

Rules:
- role_persona is the person the learner talks to, a believable character for this situation (a first name and a job), not "a tutor" or "an assistant". personality and speaking_style are short phrases suited to {level}.
- context_description.scenario is 1-2 concrete sentences about what is happening; objectives are 3 or 4 things the learner should manage to do in the conversation.
- opening_prompt is the persona's first line (1-2 sentences, {level} language), ending with a question that invites the learner to speak.
- suggested_prompts: exactly 3 different first-person sentences the LEARNER might say, each complete, grammatical, at most 14 words, with correct articles.
- vocabulary_list: {VOCAB_RANGE[0]} to {VOCAB_RANGE[1]} terms the conversation really needs, appropriate for {level}. "definition" is a real definition, at most 15 words. The "term" is the base form without "to" (write "pull off", not "to pull off"). "example_in_story" is a natural sentence that uses the term; a verb may be inflected there ("pulled off"). "part_of_speech" is one of: {", ".join(sorted(PARTS_OF_SPEECH))}.
- grammar_points: {GRAMMAR_RANGE[0]} or {GRAMMAR_RANGE[1]} structures this situation practises, for {level}. "explanation" is one clear sentence (at most 25 words); "examples" are 2 correct sentences set in this situation.
- estimated_minutes is an integer from 8 to 25.
- Every English sentence must be free of grammar mistakes. Never write "a useful expression" or restate the scenario as a definition.{retry}"""


def _text(value: Any) -> str:
    return value.strip() if isinstance(value, str) else ""


def _words(text: str) -> int:
    return len(text.split())


def _base_term(term: str) -> str:
    """A verb entry is stored without its "to": "to pull off" -> "pull off"."""
    return term[3:].strip() if term.lower().startswith("to ") else term


def _contains_term(example: str, term: str) -> bool:
    """The example uses the term, possibly inflected ("pull off" ~ "pulled off", "coordinate" ~ "coordinated")."""
    text = example.lower()
    for word in term.lower().split():
        stem = word if len(word) < 5 else word[: max(4, len(word) - 2)]
        if stem not in text:
            return False
    return True


def validate_draft(raw: Any, title_en: str, level: str, category: str) -> tuple[dict[str, Any], list[str]]:
    """(draft, warnings). Raises DraftError listing every structural problem."""
    problems: list[str] = []
    warnings: list[str] = []
    if not isinstance(raw, dict):
        raise DraftError("the model did not return a JSON object")

    persona_in = raw.get("role_persona") if isinstance(raw.get("role_persona"), dict) else {}
    persona = {k: _text(persona_in.get(k)) for k in ("name", "role", "personality", "speaking_style", "background")}
    for key, value in persona.items():
        if not value:
            problems.append(f"role_persona.{key} is empty")

    ctx_in = raw.get("context_description") if isinstance(raw.get("context_description"), dict) else {}
    objectives = [_text(o) for o in ctx_in.get("objectives") or [] if _text(o)]
    context = {"setting": _text(ctx_in.get("setting")), "scenario": _text(ctx_in.get("scenario")), "objectives": objectives}
    if not context["setting"] or not context["scenario"]:
        problems.append("context_description needs a setting and a scenario")
    if not 3 <= len(objectives) <= 5:
        problems.append("context_description.objectives must have 3 to 5 entries")

    opening = _text(raw.get("opening_prompt"))
    if not opening:
        problems.append("opening_prompt is empty")

    prompts = [_text(p) for p in raw.get("suggested_prompts") or [] if _text(p)]
    if len(prompts) != 3:
        problems.append("suggested_prompts must be exactly 3 sentences")
    elif len({p.lower().rstrip(".!? ") for p in prompts}) != 3:
        problems.append("suggested_prompts must be 3 different sentences")
    for p in prompts:
        if _words(p) > 14:
            problems.append(f"suggested prompt too long: {p!r}")

    vocabulary: list[dict[str, Any]] = []
    seen_terms: set[str] = set()
    for item in raw.get("vocabulary_list") or []:
        if not isinstance(item, dict):
            continue
        term = _base_term(_text(item.get("term")))
        definition, example = _text(item.get("definition")), _text(item.get("example_in_story"))
        if not term or term.lower() in seen_terms:
            continue
        seen_terms.add(term.lower())
        if is_placeholder_definition(definition) or not 2 <= _words(definition) <= 15:
            problems.append(f"definition of {term!r} must be a real definition of 2-15 words")
            continue
        if is_template_vocab_example(example) or not _contains_term(example, term):
            problems.append(f"example of {term!r} must be a real sentence containing the term")
            continue
        pos = _text(item.get("part_of_speech")).lower()
        vocabulary.append({
            "term": term, "definition": definition, "example_in_story": example,
            "part_of_speech": pos if pos in PARTS_OF_SPEECH else "noun",
        })
    if len(vocabulary) < VOCAB_RANGE[0]:
        problems.append(f"vocabulary_list needs at least {VOCAB_RANGE[0]} valid terms, got {len(vocabulary)}")
    vocabulary = vocabulary[: VOCAB_RANGE[1]]

    grammar: list[dict[str, Any]] = []
    for item in raw.get("grammar_points") or []:
        if not isinstance(item, dict):
            continue
        structure, explanation = _text(item.get("grammar_structure")), _text(item.get("explanation"))
        examples = [_text(e) for e in item.get("examples") or [] if _text(e)]
        usage = _text(item.get("usage_in_story"))
        if not structure or not explanation or len(examples) < 2:
            problems.append(f"grammar point {structure or '?'!r} needs an explanation and 2 examples")
            continue
        if is_template_grammar_explanation(explanation) or is_template_grammar_usage(usage) or _words(explanation) > 25:
            problems.append(f"grammar point {structure!r} has a filler or over-long explanation")
            continue
        grammar.append({"grammar_structure": structure, "explanation": explanation, "usage_in_story": usage, "examples": examples[:3]})
    if not GRAMMAR_RANGE[0] <= len(grammar) <= GRAMMAR_RANGE[1] + 1:
        problems.append(f"grammar_points needs {GRAMMAR_RANGE[0]}-{GRAMMAR_RANGE[1]} valid entries, got {len(grammar)}")
    grammar = grammar[: GRAMMAR_RANGE[1]]

    if problems:
        raise DraftError("; ".join(problems))

    try:
        minutes = int(raw.get("estimated_minutes") or 15)
    except (TypeError, ValueError):
        minutes = 15
    if not 8 <= minutes <= 25:
        minutes = 15

    meta = infer_topic_meta(title_en)
    if not meta["matched"]:
        # The title says nothing: the setting is the next-best clue. It is not used when the
        # title already matched, because a persona like "office colleague" would pull it astray.
        meta = infer_topic_meta(title_en, notes=context["setting"])
    picked = category if category in TOPIC_CATEGORIES else meta["category"]
    if meta["confidence"] == "low":
        warnings.append("Could not tell the icon from the title; check the icon.")
    draft = {
        "title_vi": _text(raw.get("title_vi")) or title_en,
        "category": picked,
        "icon_key": meta["icon_key"],
        "difficulty_level": level,
        "estimated_minutes": minutes,
        "role_persona": persona,
        "context_description": context,
        "opening_prompt": opening,
        "suggested_prompts": prompts,
        "vocabulary_list": vocabulary,
        "grammar_points": grammar,
    }
    if not _text(raw.get("title_vi")):
        warnings.append("No Vietnamese title was produced; the English one was used.")
    return draft, warnings


async def groq_json(prompt: str) -> Any:
    """One Groq JSON call through the shared key pool; reasoning stays low to keep the cost down."""
    from api.core.groq_key_pool import get_available_groq_key, record_groq_key_usage, resolve_groq_model
    from api.services.trace_cag.llm_client import _throttled_post_json

    max_tokens = int(os.getenv("TOPIC_DRAFT_MAX_TOKENS", "4500"))
    key = await get_available_groq_key(estimated_tokens=max_tokens + 1000)
    if not key:
        raise DraftError("no Groq key is available right now; try again in a minute")
    model = resolve_groq_model("TOPIC_DRAFT_GROQ_MODEL", "CONTENT_AGENT_GROQ_MODEL", "GROQ_MODEL")
    payload: dict[str, Any] = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "response_format": {"type": "json_object"},
        "temperature": 0.6,
        "max_tokens": max_tokens,
        "reasoning_effort": os.getenv("TOPIC_DRAFT_REASONING", "low"),
    }
    response = await _throttled_post_json(
        provider="groq",
        url=GROQ_URL,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        payload=payload,
        timeout=90.0,
    )
    if response is None or response.status_code != 200:
        status = getattr(response, "status_code", "no response")
        raise DraftError(f"the AI service is busy (Groq {status}); try again shortly")
    data = response.json()
    await record_groq_key_usage(key, int(data.get("usage", {}).get("total_tokens", max_tokens)))
    try:
        return json.loads(data["choices"][0]["message"]["content"])
    except (KeyError, IndexError, json.JSONDecodeError) as exc:
        raise DraftError("the model's answer was not valid JSON") from exc


async def generate_topic_draft(
    title_en: str, level: str, category: str = "", notes: str = "", llm: LLM = groq_json, attempts: int = 2
) -> tuple[dict[str, Any], list[str]]:
    """A reviewed-shape draft and its warnings; the second attempt is told what the first got wrong."""
    title = (title_en or "").strip()
    if len(title) < 3:
        raise DraftError("give the topic a title of at least 3 characters first")
    problems: list[str] | None = None
    last = "unknown error"
    for _ in range(max(1, attempts)):
        raw = await llm(build_draft_prompt(title, level, category, notes, problems))
        try:
            return validate_draft(raw, title, level, category)
        except DraftError as exc:
            last = str(exc)
            problems = last.split("; ")
            logger.info("topic draft rejected, retrying: %s", last[:200])
    raise DraftError(f"the draft did not pass the checks after {attempts} tries: {last}")
