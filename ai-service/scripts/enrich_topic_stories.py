#!/usr/bin/env python3
"""Replace template filler in the `topic_expansion` stories with real content.

For each such story in data/sample_stories.json it asks qwen (Groq) for a real
definition and in-story example per vocabulary term, three suggested prompts a
learner would actually say, and grammar explanations/examples that fit the
situation.

Nothing is written for a story until it passes a gate: every suggested prompt
and example must come back from the diagnosis with zero grounded errors, no
placeholder pattern, no duplicate and no unchanged old template line. A story
that fails keeps its old content and is reported. If Groq fails the story fails
loudly; there is no fallback to templates.

    python -m scripts.enrich_topic_stories                    # dry run (default)
    python -m scripts.enrich_topic_stories --only story_dental_appointment
    python -m scripts.enrich_topic_stories --write --concurrency=2 --delay=6

Groq's free tier rate-limits hard: --concurrency=2 --delay=6 is the setting that
completed a 93-lesson run; --concurrency=4 --delay=1 lost a third to 429s.
"""

from __future__ import annotations

import argparse
import asyncio
import copy
import json
import math
import os
import re
import sys
import unicodedata
from pathlib import Path
from typing import Any, Awaitable, Callable

AI_SERVICE_ROOT = Path(__file__).resolve().parents[1]
if str(AI_SERVICE_ROOT) not in sys.path:
    sys.path.insert(0, str(AI_SERVICE_ROOT))

from api.services.story_filler import (  # noqa: E402
    is_placeholder_definition,
    is_template_grammar_explanation,
    is_template_grammar_usage,
    is_template_vocab_example,
)
from scripts.generate_tracecag_topic_corpus import (  # noqa: E402
    DEFAULT_SAMPLE_STORIES,
    atomic_write_json,
    load_json,
)

TAG = "topic_expansion"
GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
PARTS_OF_SPEECH = {
    "noun", "noun phrase", "verb", "verb phrase", "phrasal verb",
    "adjective", "adverb", "preposition", "expression",
}

NEW_GRAMMAR_POINTS = 2
MIN_VERIFIED_ERRORS = 0.7

LLM = Callable[[str], Awaitable[Any]]
Diagnose = Callable[[str, str], Awaitable[list[dict[str, Any]]]]


class EnrichmentError(Exception):
    """Generation or validation failed for one story."""


def _words(text: str) -> int:
    return len(text.split())


def _norm(text: str) -> str:
    folded = unicodedata.normalize("NFKC", text or "").casefold()
    return " ".join(folded.split()).rstrip(" .!?,;:")


def is_enriched(story: dict[str, Any]) -> bool:
    """Already has real content: every term carries collocations, a common error and a real definition."""
    vocab = story.get("vocabulary_list") or []
    return bool(vocab) and all(
        v.get("collocations") and "common_error" in v
        and v.get("definition") and not is_placeholder_definition(v["definition"])
        for v in vocab
    )


def select_stories(
    stories: list[dict[str, Any]], only: list[str] | None, force: bool = False, all_stories: bool = False
) -> list[dict[str, Any]]:
    tagged = [s for s in stories if all_stories or TAG in (s.get("tags") or [])]
    if not only:
        return tagged if force else [s for s in tagged if not is_enriched(s)]
    wanted = set(only)
    missing = wanted - {s["story_id"] for s in tagged}
    if missing:
        raise EnrichmentError(f"not a {TAG} story: {', '.join(sorted(missing))}")
    return [s for s in tagged if s["story_id"] in wanted]


def build_prompt(story: dict[str, Any], problems: list[str] | None = None) -> str:
    level = story["difficulty_level"]
    terms = [v["term"] for v in story["vocabulary_list"]]
    structures = [g["grammar_structure"] for g in (story.get("grammar_points") or [])]
    grammar_line = (
        f"Grammar structures (keep each exactly as written, same order): {json.dumps(structures)}"
        if structures else
        f"Grammar structures: none yet. Choose exactly {NEW_GRAMMAR_POINTS} structures a {level} learner "
        "really needs in this scenario, and name each in \"grammar_structure\" (e.g. \"Modal verbs for requests\")."
    )
    retry = ""
    if problems:
        listed = "\n".join(f"- {p}" for p in problems[:12])
        retry = f"\nYour previous answer was rejected for these reasons, fix every one:\n{listed}\n"
    return f"""You write teaching content for an English conversation-practice app.

Scenario: {story['title']['en']} (CEFR {level}). Setting: {story['context_description']['setting']}.
The learner talks to: {story['role_persona']['name']}, {story['role_persona']['role']}.

Vocabulary terms (keep each term exactly as written): {json.dumps(terms)}
{grammar_line}

Return one JSON object:
{{
  "vocabulary": [{{"term": "...", "definition": "...", "example_in_story": "...", "part_of_speech": "...",
                  "collocations": ["...", "..."],
                  "common_error": {{"wrong": "...", "right": "...", "why": "..."}}}}],
  "suggested_prompts": ["...", "...", "..."],
  "grammar_points": [{{"grammar_structure": "...", "explanation": "...", "usage_in_story": "...", "examples": ["...", "..."]}}]
}}

Rules:
- One vocabulary entry per term, same order. "definition" is a real definition of what the word or phrase means in this scenario, at most 15 words, simple enough for {level}. Never write "a useful expression" or restate the scenario.
- "example_in_story" is a natural sentence at {level} that contains the term exactly as written. A speaker in the scenario could say it.
- "part_of_speech" is one of: {", ".join(sorted(PARTS_OF_SPEECH))}.
- "collocations": exactly 2 short, natural word combinations (2-6 words) that contain the term exactly as written and that people really use, e.g. "have a toothache", "a bad toothache". Not full sentences.
- "common_error": a mistake a {level} learner (especially a Vietnamese speaker) really makes with this term. "wrong" is a short sentence with exactly that mistake; "right" is the same sentence corrected, changing only what is needed; "why" explains the rule in at most 15 simple English words.
- "suggested_prompts": exactly 3 different first-person sentences the LEARNER would say to {story['role_persona']['role']} in this situation. Each is complete, grammatical, at most 14 words, with correct articles (for example "I have a toothache.", never "I need help with the toothache."). Do not reuse the vocabulary example sentences.
- "grammar_points": same count and order as the structures. "explanation" is one clear sentence (at most 25 words) about the structure itself, not about "keeping the conversation clear". "usage_in_story" says how it is used in this scenario. "examples" are 2 or 3 correct sentences that use the structure in this scenario.
- Every sentence must be free of grammar mistakes.{retry}"""


def _str(value: Any, what: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise EnrichmentError(f"{what}: missing or not text")
    return value.strip()


def parse_enrichment(raw: Any, story: dict[str, Any]) -> dict[str, Any]:
    """Validate the model's JSON against the story; raises EnrichmentError naming every problem."""
    problems: list[str] = []
    if not isinstance(raw, dict):
        raise EnrichmentError("answer is not a JSON object")

    vocab_in = raw.get("vocabulary")
    by_term = {}
    if isinstance(vocab_in, list):
        by_term = {str(v.get("term", "")).strip().lower(): v for v in vocab_in if isinstance(v, dict)}
    vocabulary: list[dict[str, str]] = []
    for item in story["vocabulary_list"]:
        term = item["term"]
        entry = by_term.get(term.lower())
        if entry is None:
            problems.append(f"vocabulary: no entry for {term!r}")
            continue
        try:
            definition = _str(entry.get("definition"), f"definition of {term!r}")
            example = _str(entry.get("example_in_story"), f"example of {term!r}")
        except EnrichmentError as exc:
            problems.append(str(exc))
            continue
        if is_placeholder_definition(definition) or _norm(definition) == _norm(term):
            problems.append(f"definition of {term!r} is a placeholder")
        if not 2 <= _words(definition) <= 15:
            problems.append(f"definition of {term!r} must be 2-15 words, got {_words(definition)}")
        if is_template_vocab_example(example) or term.lower() not in example.lower():
            problems.append(f"example of {term!r} must be a real sentence containing the term")
        if not 3 <= _words(example) <= 25:
            problems.append(f"example of {term!r} must be 3-25 words")
        pos = str(entry.get("part_of_speech") or "").strip().lower()
        collocations = entry.get("collocations")
        if not isinstance(collocations, list) or len(collocations) != 2 or not all(
            isinstance(c, str) and term.lower() in c.lower() and 2 <= _words(c) <= 6 for c in collocations
        ):
            problems.append(f"collocations of {term!r} must be 2 phrases of 2-6 words containing the term")
            collocations = []
        error = entry.get("common_error")
        wrong = right = why = ""
        if isinstance(error, dict):
            wrong, right, why = (str(error.get(k) or "").strip() for k in ("wrong", "right", "why"))
        # A malformed common error is dropped, not fatal: the gate keeps only verified ones.
        common_error = (
            {"wrong": wrong, "right": right, "why": why}
            if wrong and right and why and _norm(wrong) != _norm(right)
            and _words(why) <= 15 and 2 <= _words(wrong) <= 16 and 2 <= _words(right) <= 16
            else None
        )
        vocabulary.append({
            "term": term,
            "definition": definition,
            "example_in_story": example,
            "part_of_speech": pos if pos in PARTS_OF_SPEECH else item.get("part_of_speech", "noun"),
            "collocations": [c.strip() for c in collocations],
            "common_error": common_error,
        })

    prompts_in = raw.get("suggested_prompts")
    prompts: list[str] = []
    if not isinstance(prompts_in, list) or len(prompts_in) != 3:
        problems.append("suggested_prompts must be exactly 3 sentences")
    else:
        for prompt in prompts_in:
            try:
                text = _str(prompt, "suggested prompt")
            except EnrichmentError as exc:
                problems.append(str(exc))
                continue
            if _words(text) > 14:
                problems.append(f"suggested prompt too long: {text!r}")
            prompts.append(text)

    grammar_in = raw.get("grammar_points")
    grammar: list[dict[str, Any]] = []
    expected = (story.get("grammar_points") or [])
    if not expected and isinstance(grammar_in, list):
        # The story had none: the model proposes them, named by itself.
        expected = [
            {"grammar_structure": str(g.get("grammar_structure") or "").strip()}
            for g in grammar_in if isinstance(g, dict)
        ]
        if len(expected) != NEW_GRAMMAR_POINTS or not all(g["grammar_structure"] for g in expected):
            problems.append(f"grammar_points must propose {NEW_GRAMMAR_POINTS} named structures")
            expected = []
            grammar_in = None
    if not isinstance(grammar_in, list) or len(grammar_in) != len(expected):
        if grammar_in is not None or story.get("grammar_points"):
            problems.append(f"grammar_points must have {len(expected)} entries")
    else:
        for old, new in zip(expected, grammar_in):
            if not isinstance(new, dict) or _norm(str(new.get("grammar_structure", ""))) != _norm(old["grammar_structure"]):
                problems.append(f"grammar point {old['grammar_structure']!r} changed or out of order")
                continue
            try:
                explanation = _str(new.get("explanation"), "grammar explanation")
                usage = _str(new.get("usage_in_story"), "grammar usage")
            except EnrichmentError as exc:
                problems.append(f"{old['grammar_structure']!r}: {exc}")
                continue
            examples = new.get("examples")
            if not isinstance(examples, list) or not 2 <= len(examples) <= 3 or not all(
                isinstance(e, str) and e.strip() for e in examples
            ):
                problems.append(f"{old['grammar_structure']!r}: examples must be 2-3 sentences")
                continue
            if is_template_grammar_explanation(explanation) or is_template_grammar_usage(usage):
                problems.append(f"{old['grammar_structure']!r}: explanation is template filler")
            if _words(explanation) > 25:
                problems.append(f"{old['grammar_structure']!r}: explanation over 25 words")
            grammar.append({
                **old,
                "explanation": explanation,
                "usage_in_story": usage,
                "examples": [e.strip() for e in examples],
            })

    if problems:
        raise EnrichmentError("; ".join(problems))
    return {"vocabulary": vocabulary, "suggested_prompts": prompts, "grammar_points": grammar}


def _sentences(enriched: dict[str, Any]) -> list[str]:
    out = list(enriched["suggested_prompts"])
    out += [v["example_in_story"] for v in enriched["vocabulary"]]
    out += [v["common_error"]["right"] for v in enriched["vocabulary"] if v.get("common_error")]
    for g in enriched["grammar_points"]:
        out += g["examples"]
    return out


def _old_sentences(story: dict[str, Any]) -> set[str]:
    old = set(story.get("suggested_prompts") or [])
    old |= {v.get("example_in_story", "") for v in story["vocabulary_list"]}
    for g in (story.get("grammar_points") or []):
        old |= set(g.get("examples") or [])
    return {_norm(s) for s in old if s}


async def gate(story: dict[str, Any], enriched: dict[str, Any], diagnose: Diagnose) -> list[str]:
    """Problems that keep a story from being written; empty means it passed.

    A common error whose "wrong" sentence the diagnosis does not flag is dropped
    (set to None) rather than failing the story, so the KG never teaches a
    non-error; the story still needs MIN_VERIFIED_ERRORS of its terms covered.
    """
    problems: list[str] = []
    level = story["difficulty_level"]
    vocab = enriched["vocabulary"]
    for item in vocab:
        error = item.get("common_error")
        if error and not await diagnose(error["wrong"], level):
            item["common_error"] = None
    verified = sum(1 for item in vocab if item.get("common_error"))
    if vocab and verified < max(1, math.floor(MIN_VERIFIED_ERRORS * len(vocab))):
        problems.append(
            f"only {verified} of {len(vocab)} common errors are real mistakes the diagnosis flags; "
            "write clearer, typical learner mistakes"
        )
    sentences = _sentences(enriched)
    seen: set[str] = set()
    old = _old_sentences(story)
    for text in sentences:
        key = _norm(text)
        if key in seen:
            problems.append(f"duplicate sentence: {text!r}")
        seen.add(key)
        if key in old:
            problems.append(f"unchanged from the old template: {text!r}")
    for text in sentences:
        for err in await diagnose(text, level):
            problems.append(
                f"diagnosis flags {text!r}: {err.get('span')!r} -> {err.get('correction')!r}"
            )
    return problems


def apply_enrichment(story: dict[str, Any], enriched: dict[str, Any]) -> dict[str, Any]:
    new = copy.deepcopy(story)
    for item, fresh in zip(new["vocabulary_list"], enriched["vocabulary"]):
        item.update(
            definition=fresh["definition"],
            example_in_story=fresh["example_in_story"],
            part_of_speech=fresh["part_of_speech"],
            collocations=list(fresh["collocations"]),
            common_error=dict(fresh["common_error"]) if fresh.get("common_error") else None,
        )
    new["suggested_prompts"] = list(enriched["suggested_prompts"])
    new["grammar_points"] = copy.deepcopy(enriched["grammar_points"])
    return new


async def enrich_story(
    story: dict[str, Any], llm: LLM, diagnose: Diagnose, attempts: int = 2
) -> tuple[dict[str, Any] | None, list[str]]:
    """(new_story, []) when it passed; (None, problems) when every attempt failed."""
    problems: list[str] = []
    for _ in range(max(1, attempts)):
        try:
            raw = await llm(build_prompt(story, problems or None))
            enriched = parse_enrichment(raw, story)
            problems = await gate(story, enriched, diagnose)
        except EnrichmentError as exc:
            problems = [str(exc)]
            continue
        if not problems:
            return apply_enrichment(story, enriched), []
    return None, problems


def describe(old: dict[str, Any], new: dict[str, Any]) -> list[str]:
    lines = [f"  prompts: {old.get('suggested_prompts')} -> {new['suggested_prompts']}"]
    for a, b in list(zip(old["vocabulary_list"], new["vocabulary_list"]))[:3]:
        lines.append(f"  {b['term']}: {a.get('definition', '')[:60]!r} -> {b['definition']!r}")
    first = new["grammar_points"][0]
    lines.append(f"  {first['grammar_structure']}: {first['explanation']}")
    return lines


async def run(
    stories: list[dict[str, Any]],
    llm: LLM,
    diagnose: Diagnose,
    *,
    only: list[str] | None = None,
    concurrency: int = 2,
    delay: float = 6.0,
    attempts: int = 2,
    force: bool = False,
    all_stories: bool = False,
    log: Callable[[str], None] = print,
    on_pass: Callable[[list[dict[str, Any]]], None] | None = None,
) -> tuple[list[dict[str, Any]], dict[str, list[str]]]:
    """Returns (all stories with passing ones replaced, {story_id: problems} for failures).

    ``on_pass`` gets the merged list after every passing story, so a long run
    that dies on a rate limit keeps what it already finished.
    """
    targets = select_stories(stories, only, force, all_stories)
    log(f"{len(targets)} story(ies) to enrich")
    semaphore = asyncio.Semaphore(max(1, concurrency))
    results: dict[str, dict[str, Any]] = {}
    failures: dict[str, list[str]] = {}

    async def one(story: dict[str, Any]) -> None:
        async with semaphore:
            new, problems = await enrich_story(story, llm, diagnose, attempts)
            if new is None:
                failures[story["story_id"]] = problems
                log(f"FAIL {story['story_id']}: {problems[:3]}")
            else:
                results[story["story_id"]] = new
                if on_pass is not None:
                    on_pass([results.get(s["story_id"], s) for s in stories])
                log(f"ok   {story['story_id']}")
                for line in describe(story, new):
                    log(line)
            if delay > 0:
                await asyncio.sleep(delay)

    await asyncio.gather(*(one(s) for s in targets))
    merged = [results.get(s["story_id"], s) for s in stories]
    return merged, failures


async def _groq_json(
    messages: list[dict[str, str]], *, max_tokens: int, temperature: float, effort: str | None
) -> Any:
    from api.core.groq_key_pool import get_available_groq_key, record_groq_key_usage, resolve_groq_model
    from api.services.trace_cag.llm_client import _throttled_post_json

    key = await get_available_groq_key(estimated_tokens=max_tokens + 1500)
    if not key:
        raise EnrichmentError("no Groq key available (set GROQ_API_KEY or GROQ_API_KEYS)")
    model = resolve_groq_model("STORY_ENRICH_GROQ_MODEL", "CONTENT_AGENT_GROQ_MODEL")
    payload: dict[str, Any] = {
        "model": model,
        "messages": messages,
        "response_format": {"type": "json_object"},
        "temperature": temperature,
        "max_tokens": max_tokens,
    }
    if effort:
        payload["reasoning_effort"] = effort
    response = await _throttled_post_json(
        provider="groq",
        url=GROQ_URL,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        payload=payload,
        timeout=120.0,
    )
    if response is None or response.status_code != 200:
        raise EnrichmentError(f"Groq returned {getattr(response, 'status_code', 'no response')}")
    data = response.json()
    await record_groq_key_usage(key, int(data.get("usage", {}).get("total_tokens", max_tokens)))
    try:
        return json.loads(data["choices"][0]["message"]["content"])
    except (KeyError, IndexError, json.JSONDecodeError) as exc:
        raise EnrichmentError(f"Groq answer is not valid JSON: {type(exc).__name__}") from exc


async def groq_llm(prompt: str) -> Any:
    # Reasoning stays on for generation (CLAUDE.md); json_object keeps the output clean.
    effort = os.getenv("STORY_ENRICH_REASONING", "medium")
    return await _groq_json(
        [{"role": "user", "content": prompt}], max_tokens=7000, temperature=0.6, effort=effort
    )


async def groq_diagnose(text: str, level: str) -> list[dict[str, Any]]:
    """Grounded diagnosis errors for one sentence, judged exactly as topic chat judges a learner."""
    from api.services.educational_hints_parser import EducationalHintsParser
    from api.services.trace_cag.nodes_v2 import build_diagnosis_prompt

    data = await _groq_json(
        [
            {"role": "system", "content": "You are an English grammar analyzer. Return only valid JSON."},
            {"role": "user", "content": build_diagnosis_prompt(text, level, closed=True)},
        ],
        max_tokens=400,
        temperature=0.0,
        effort=None,
    )
    errors = data.get("errors") if isinstance(data, dict) else None
    return EducationalHintsParser.corrections_from_diagnosis(None, errors or [], text)[1]


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Replace template filler in topic_expansion stories.")
    parser.add_argument("--sample-stories", type=Path, default=DEFAULT_SAMPLE_STORIES)
    parser.add_argument("--write", action="store_true", help="write passing stories back (default: dry run)")
    parser.add_argument("--dry-run", action="store_true", help="print the diff, write nothing (the default)")
    parser.add_argument("--only", action="append", default=[], help="story id; repeatable")
    parser.add_argument("--concurrency", type=int, default=2)
    parser.add_argument("--delay", type=float, default=6.0)
    parser.add_argument("--attempts", type=int, default=3)
    parser.add_argument("--force", action="store_true", help="also redo stories that are already enriched")
    parser.add_argument(
        "--all-stories", action="store_true",
        help=f"include the hand-written stories, not only the {TAG} ones (they lack prompts and KG material)",
    )
    return parser


async def amain(args: argparse.Namespace, llm: LLM = groq_llm, diagnose: Diagnose = groq_diagnose) -> int:
    if args.write and args.dry_run:
        raise SystemExit("--write and --dry-run are mutually exclusive")
    payload = load_json(args.sample_stories)
    stories = payload.get("stories", payload) if isinstance(payload, dict) else payload
    def save(current: list[dict[str, Any]]) -> None:
        out = {**payload, "stories": current} if isinstance(payload, dict) else current
        atomic_write_json(args.sample_stories, out)

    merged, failures = await run(
        stories, llm, diagnose,
        only=[o for item in args.only for o in item.split(",") if o],
        concurrency=args.concurrency, delay=args.delay, attempts=args.attempts,
        force=args.force, all_stories=getattr(args, "all_stories", False),
        on_pass=save if args.write else None,
    )
    changed = sum(1 for a, b in zip(stories, merged) if a is not b)
    print(f"\n{changed} story(ies) passed the gate, {len(failures)} failed")
    for story_id, problems in sorted(failures.items()):
        print(f"  FAILED {story_id}")
        for problem in problems[:5]:
            print(f"    - {problem}")
    if args.write and changed:
        print(f"wrote {args.sample_stories} after each passing story")
    elif changed:
        print("dry run: nothing written (pass --write to apply)")
    return 1 if failures else 0


def main() -> None:
    sys.exit(asyncio.run(amain(build_arg_parser().parse_args())))


if __name__ == "__main__":
    main()
