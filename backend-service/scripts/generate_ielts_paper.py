"""Generate an original IELTS Academic Reading paper from openly licensed passages.

Passages come only from `ielts_passage_manifest.json` (Wikipedia at a pinned
revision, Project Gutenberg by ebook id, US-government pages). Nothing from
Cambridge, British Council, IDP or any practice site is fetched or copied; the
questions are written by an LLM against the passage and then checked twice:

  1. deterministic validators (answer labels, verbatim gaps, word limits,
     option membership, continuous numbering, exactly 40 questions)
  2. a second LLM pass that answers each question blind from the passage; a
     question survives only if its answer matches and its quoted evidence
     really occurs in the passage

The paper lands as a DRAFT (`is_published=false`) with `provenance` filled so the
publish gate in `admin_ielts.py` can pass. Reading only; Listening, Writing and
Speaking are out of scope here.

    venv/bin/python3 scripts/generate_ielts_paper.py --dry-run
    venv/bin/python3 scripts/generate_ielts_paper.py --passages wp-antikythera,wp-mycorrhiza,wp-urban-heat-island
    venv/bin/python3 scripts/generate_ielts_paper.py --dry-run --passages wp-mycorrhiza --first-position 2

Lives in backend-service because the draft is written through the same
`IeltsTest` path as `seed_ielts_test.py`, and a standalone script must not reach
across the service boundary into ai-service's LLM client (same reasoning as
`generate_exercises_ai.py`, which round-robins `GROQ_API_KEYS` itself).
"""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import itertools
import json
import os
import random
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib import robotparser
from urllib.parse import urlparse

import httpx
from dotenv import load_dotenv

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.services.ielts_paper_builder import (  # noqa: E402
    BLUEPRINT,
    COMPLETION_TYPES,
    HEADING_DISTRACTORS,
    TOTAL_QUESTIONS,
    GroupSpec,
    ManifestError,
    PassageSource,
    build_provenance,
    build_reading_section,
    count_words,
    extract_gutenberg_paragraphs,
    extract_html_paragraphs,
    heading_label,
    labelled_passage_text,
    normalize_text,
    paragraph_letters,
    parse_manifest,
    provenance_entry,
    select_heading_paragraphs,
    slug_for,
    trim_to_length,
    validate_group,
    validate_headings,
    validate_paper,
    validate_question,
    word_limit_text,
)
from app.services.ielts_scoring import answer_matches  # noqa: E402

load_dotenv()

GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
GROQ_MODEL = os.getenv("IELTS_GEN_MODEL", "qwen/qwen3.8-27b")
# Generation keeps reasoning on (CLAUDE.md): response_format json_object pins the
# output, so thinking costs nothing in parseability. "none" would disable it.
REASONING_EFFORT = "medium"
USER_AGENT = "LexiLingoContentBot/1.0 (open-licence passage sourcing; +https://github.com/infinityzero3000/lexilingo)"
MANIFEST_PATH = Path(__file__).resolve().parent / "ielts_passage_manifest.json"
MAX_ROUNDS = 3
OVERGENERATE = 2


class PaperRefused(RuntimeError):
    """The paper cannot reach 40 verified questions, so nothing is written."""


def log(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


# ---------------------------------------------------------------- LLM ----

class GroqChat:
    """JSON-mode chat with a rotating key pool, a call cap and a pause per call."""

    def __init__(
        self,
        client: httpx.AsyncClient,
        keys: list[str],
        model: str = GROQ_MODEL,
        concurrency: int = 2,
        delay: float = 6.0,
    ) -> None:
        self._client = client
        self._keys = itertools.cycle(keys) if keys else None
        self._key_count = len(keys)
        self.model = model
        self._sem = asyncio.Semaphore(max(1, concurrency))
        self._delay = delay

    async def complete_json(self, *, system: str, user: str, label: str) -> dict:
        if self._keys is None:
            raise SystemExit("Set GROQ_API_KEYS (comma-separated) or GROQ_API_KEY in backend-service/.env")
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "response_format": {"type": "json_object"},
            "reasoning_effort": REASONING_EFFORT,
            "temperature": 0.6,
            "max_tokens": 8000,
        }
        for attempt in range(max(4, self._key_count)):
            async with self._sem:
                if self._delay:
                    await asyncio.sleep(self._delay)
                headers = {"Authorization": f"Bearer {next(self._keys)}"}
                try:
                    response = await self._client.post(
                        GROQ_URL, json=payload, headers=headers, timeout=180.0
                    )
                except httpx.HTTPError as exc:
                    log(f"    [{label}] network error {type(exc).__name__}; retrying")
                    await asyncio.sleep(3)
                    continue
            status = response.status_code
            if status == 200:
                try:
                    content = response.json()["choices"][0]["message"]["content"]
                    parsed = json.loads(content)
                    if isinstance(parsed, dict):
                        return parsed
                except (KeyError, IndexError, ValueError, TypeError):
                    pass
                log(f"    [{label}] unparseable reply; retrying")
            elif status in (401, 403) or (
                status == 400 and "json_validate_failed" not in response.text
            ):
                raise SystemExit(f"Aborting: Groq rejected the request ({status}): {response.text[:300]}")
            elif status == 429:
                wait = 2 if self._key_count > 1 else 15 * (attempt + 1)
                log(f"    [{label}] rate limited; waiting {wait}s")
                await asyncio.sleep(wait)
            else:
                log(f"    [{label}] HTTP {status}; retrying")
                await asyncio.sleep(5 * (attempt + 1))
        raise PaperRefused(f"{label}: no usable reply from the model after retries")


SYSTEM_PROMPT = (
    "You write original IELTS Academic Reading questions for a language-learning app. "
    "Use ONLY the passage you are given. Never reproduce or imitate the wording of any "
    "published IELTS paper. Reply with one JSON object and nothing else."
)


def generation_prompt(spec: GroupSpec, passage_text: str, count: int, extra: str = "") -> str:
    head = f"TASK: generate {spec.question_type} count={count}"
    if spec.word_limit:
        head += f" word_limit={spec.word_limit}"
    rules: str
    if spec.question_type == "true_false_notgiven":
        rules = (
            f"Write {count} statements about the passage. Paraphrase; do not copy sentences. "
            "Roughly a third each TRUE (the passage says so), FALSE (the passage says the "
            "opposite) and NOT GIVEN (on topic, but the passage neither confirms nor denies it). "
            "Follow the order of the passage.\n"
            'Return {"questions":[{"prompt":"<statement>","answer":"TRUE|FALSE|NOT GIVEN"}]}'
        )
    elif spec.question_type in COMPLETION_TYPES:
        kind = "sentences" if spec.question_type == "sentence_completion" else (
            "consecutive sentences of one short summary of the passage"
        )
        rules = (
            f"Write {count} {kind}, each paraphrasing the passage with ONE gap written exactly as "
            f"{'______'}. The missing word(s) must be copied EXACTLY, letter for letter, from the "
            f"passage and be {word_limit_text(spec.word_limit or 1).lower()} or fewer. "
            "Do not leave the answer anywhere else in the sentence. Follow the order of the passage.\n"
            'Return {"questions":[{"prompt":"<sentence with ______>","answer":"<words from passage>"}]}'
        )
    elif spec.question_type == "multiple_choice":
        rules = (
            f"Write {count} multiple-choice questions, each with exactly four plausible options of "
            "similar length; exactly one is correct according to the passage. Put the correct "
            "option text in 'answer', identical to one entry of 'options'. Vary which position is "
            "correct. Follow the order of the passage.\n"
            'Return {"questions":[{"prompt":"<stem>","options":["..","..","..",".."],"answer":"<one option>"}]}'
        )
    else:
        raise ValueError(spec.question_type)
    return f"{head}\n\nPASSAGE:\n{passage_text}\n\n{rules}{extra}"


def headings_prompt(passage_text: str, targets: list[str]) -> str:
    total = len(targets) + HEADING_DISTRACTORS
    return (
        f"TASK: generate matching_headings targets={','.join(targets)}\n\n"
        f"PASSAGE (paragraphs are labelled by letter):\n{passage_text}\n\n"
        f"Write {total} short headings (at most 8 words each) for a matching-headings task. "
        f"Exactly one correct heading for each of the paragraphs {', '.join(targets)} "
        "(set 'paragraph' to that letter); it must summarise the paragraph's main idea without "
        f"copying its first sentence. Add {HEADING_DISTRACTORS} plausible distractor headings that "
        "do not fit any paragraph well (set 'paragraph' to null).\n"
        'Return {"headings":[{"text":"<heading>","paragraph":"<letter or null>"}]}'
    )


def verification_prompt(passage_text: str, items: list[dict]) -> str:
    lines = []
    for item in items:
        entry = {"id": item["id"], "type": item["type"], "prompt": item["prompt"]}
        if item.get("options"):
            entry["options"] = item["options"]
        lines.append(json.dumps(entry, ensure_ascii=False))
    return (
        "TASK: verify\n\nPASSAGE:\n" + passage_text + "\n\nQUESTIONS (one JSON object per line):\n"
        + "\n".join(lines)
        + "\n\nAnswer every question yourself from the passage alone. For true_false_notgiven answer "
        "TRUE, FALSE or NOT GIVEN. For multiple_choice answer with the full text of one option. "
        "For completion types answer with the exact words from the passage that fill the gap. "
        "For matching_headings answer with the full text of the chosen heading from 'options' "
        "for the paragraph named in the prompt. 'evidence' must be an exact quotation copied from "
        "the passage that supports your answer (empty only for NOT GIVEN).\n"
        'Return {"results":[{"id":<id>,"answer":"<answer>","evidence":"<quote>"}]}'
    )


# ------------------------------------------------------- verification ----

def _evidence_in_passage(evidence: str, passage: str) -> bool:
    haystack = normalize_text(passage)
    fragments = [f for f in re.split(r"\.\.\.|…", evidence) if len(f.split()) >= 3]
    if not fragments:
        return False
    return all(normalize_text(f).strip(" .,;:\"'") in haystack for f in fragments)


def _heading_text(value: str) -> str:
    return re.sub(r"^[ivx]+\.\s*", "", normalize_text(value))


def answers_agree(item: dict, verdict: dict, passage: str) -> bool:
    given = str(verdict.get("answer") or "").strip()
    claimed = str(item["answer"]).strip()
    kind = item["type"]
    if kind == "true_false_notgiven":
        if given.upper() != claimed.upper():
            return False
        if claimed.upper() == "NOT GIVEN":
            return True
    elif kind == "multiple_choice":
        if normalize_text(given) != normalize_text(claimed):
            return False
    elif kind == "matching_headings":
        if _heading_text(given) != _heading_text(claimed):
            return False
    else:
        if not answer_matches(given, [claimed]):
            return False
    return _evidence_in_passage(str(verdict.get("evidence") or ""), passage)


async def verify_questions(
    chat: GroqChat, passage_text: str, passage_plain: str, items: list[dict], label: str
) -> list[bool]:
    """One flag per item: True when the blind answer matches and its evidence is real."""
    reply = await chat.complete_json(
        system=SYSTEM_PROMPT,
        user=verification_prompt(passage_text, items),
        label=f"{label} verify",
    )
    verdicts = {
        v.get("id"): v for v in (reply.get("results") or []) if isinstance(v, dict)
    }
    return [
        item["id"] in verdicts and answers_agree(item, verdicts[item["id"]], passage_plain)
        for item in items
    ]


# ------------------------------------------------------------- groups ----

def _clean_question(raw: Any, spec: GroupSpec) -> dict | None:
    if not isinstance(raw, dict):
        return None
    prompt = str(raw.get("prompt") or "").strip()
    answer = str(raw.get("answer") or "").strip()
    if not prompt or not answer:
        return None
    question: dict[str, Any] = {"type": spec.question_type, "prompt": prompt, "answer": answer}
    if spec.question_type == "true_false_notgiven":
        question["answer"] = answer.upper()
    if spec.question_type in COMPLETION_TYPES:
        spaced = re.sub(r"(_\s*){3,}|\[\s*\.{2,}\s*\]|\.{4,}", " ______ ", prompt)
        question["prompt"] = re.sub(r"\s+([.,;:!?])", r"\1", " ".join(spaced.split()))
        question["answer"] = answer.strip(" .")
    if spec.question_type == "multiple_choice":
        options = raw.get("options")
        if not isinstance(options, list):
            return None
        question["options"] = [str(o).strip() for o in options]
    return question


async def build_group(
    chat: GroqChat, spec: GroupSpec, passage_text: str, passage_plain: str, label: str
) -> list[dict]:
    collected: list[dict] = []
    for round_no in range(1, MAX_ROUNDS + 1):
        need = spec.count - len(collected)
        reply = await chat.complete_json(
            system=SYSTEM_PROMPT,
            user=generation_prompt(spec, passage_text, need + OVERGENERATE),
            label=f"{label} {spec.question_type} r{round_no}",
        )
        seen = {normalize_text(q["prompt"]) for q in collected}
        candidates: list[dict] = []
        for raw in reply.get("questions") or []:
            question = _clean_question(raw, spec)
            if not question:
                continue
            problems = validate_question(question, spec, passage_plain)
            if problems:
                log(f"    [{label}] dropped: {'; '.join(problems)}")
                continue
            key = normalize_text(question["prompt"])
            if key in seen:
                continue
            seen.add(key)
            candidates.append(question)
        if not candidates:
            continue
        items = [{**q, "id": i} for i, q in enumerate(candidates, start=1)]
        flags = await verify_questions(chat, passage_text, passage_plain, items, label)
        for question, ok in zip(candidates, flags):
            if ok:
                collected.append(question)
            else:
                log(f"    [{label}] unsupported, dropped: {question['prompt'][:70]}")
        if len(collected) >= spec.count:
            collected = collected[: spec.count]
            problems = validate_group(collected, spec)
            if not problems:
                return collected
            log(f"    [{label}] group rejected: {'; '.join(problems)}")
            collected = []
    raise PaperRefused(
        f"{label}: only {len(collected)} of {spec.count} {spec.question_type} questions survived"
    )


async def build_heading_group(
    chat: GroqChat, spec: GroupSpec, passage_text: str, passage_plain: str,
    paragraphs: list[str], seed: str, label: str,
) -> list[dict]:
    letters = paragraph_letters(len(paragraphs))
    targets = [letters[i] for i in select_heading_paragraphs(len(paragraphs), spec.count)]
    for attempt in range(1, MAX_ROUNDS + 1):
        reply = await chat.complete_json(
            system=SYSTEM_PROMPT,
            user=headings_prompt(passage_text, targets),
            label=f"{label} headings r{attempt}",
        )
        headings = [h for h in (reply.get("headings") or []) if isinstance(h, dict)]
        problems = validate_headings(headings, targets)
        if problems:
            log(f"    [{label}] headings rejected: {'; '.join(problems)}")
            continue
        order = list(range(len(headings)))
        random.Random(seed).shuffle(order)
        labelled = [heading_label(n, str(headings[i]["text"]).strip()) for n, i in enumerate(order)]
        correct = {
            str(headings[i]["paragraph"]): labelled[n]
            for n, i in enumerate(order)
            if headings[i].get("paragraph")
        }
        questions = [
            {
                "type": "matching_headings",
                "prompt": f"Paragraph {letter}",
                "paragraph": letter,
                "answer": correct[letter],
                "options": labelled,
            }
            for letter in targets
        ]
        for q in questions:
            problems = validate_question(q, spec, passage_plain)
            if problems:
                break
        if problems:
            log(f"    [{label}] heading question rejected: {'; '.join(problems)}")
            continue
        items = [{**q, "id": i} for i, q in enumerate(questions, start=1)]
        flags = await verify_questions(chat, passage_text, passage_plain, items, label)
        if all(flags):
            return questions
        log(f"    [{label}] {flags.count(False)} heading(s) not confirmed; regenerating")
    raise PaperRefused(f"{label}: matching headings could not be verified")


# ------------------------------------------------------------ passages ----

class RobotsDenied(RuntimeError):
    pass


async def _robots_allows(client: httpx.AsyncClient, url: str) -> bool:
    parts = urlparse(url)
    robots_url = f"{parts.scheme}://{parts.netloc}/robots.txt"
    response = await client.get(robots_url)
    if response.status_code == 404:
        return True
    if response.status_code != 200:
        return False
    parser = robotparser.RobotFileParser()
    parser.parse(response.text.splitlines())
    return parser.can_fetch(USER_AGENT, url)


async def fetch_passage(client: httpx.AsyncClient, source: PassageSource) -> dict:
    url = source.source_url
    if not await _robots_allows(client, url):
        raise RobotsDenied(f"robots.txt does not allow fetching {url}")
    response = await client.get(url)
    response.raise_for_status()
    retrieved_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    if source.kind == "gutenberg":
        response.encoding = "utf-8"
        paragraphs = extract_gutenberg_paragraphs(response.text, source.start_marker or "")
    else:
        if source.kind == "wikipedia":
            served = re.search(r'"wgRevisionId":(\d+)', response.text)
            if not served or int(served.group(1)) != source.revision:
                raise PaperRefused(f"{source.id}: Wikipedia did not serve revision {source.revision}")
        paragraphs = extract_html_paragraphs(response.text)
    return passage_from_paragraphs(source, paragraphs, retrieved_at)


def passage_from_paragraphs(
    source: PassageSource, paragraphs: list[str], retrieved_at: str
) -> dict:
    kept = trim_to_length(paragraphs)
    words = sum(count_words(p) for p in kept)
    return {
        "source": source,
        "paragraphs": kept,
        "words": words,
        "provenance": provenance_entry(source, retrieved_at, words, trimmed=len(kept) < len(paragraphs)),
    }


async def build_passage_groups(
    chat: GroqChat, passage: dict, position: int
) -> dict:
    """Question groups for one passage, from the blueprint slot `position` (1-based)."""
    source: PassageSource = passage["source"]
    specs = BLUEPRINT[position - 1]
    labelled = any(s.question_type == "matching_headings" for s in specs)
    text = labelled_passage_text(passage["paragraphs"], labelled)
    plain = "\n\n".join(passage["paragraphs"])
    groups = []
    for spec in specs:
        label = f"{source.id}"
        if spec.question_type == "matching_headings":
            questions = await build_heading_group(
                chat, spec, text, plain, passage["paragraphs"], f"{source.id}", label
            )
        else:
            questions = await build_group(chat, spec, text, plain, label)
        groups.append({"spec": spec, "questions": questions})
    return {
        "title": source.title,
        "text": text,
        "groups": groups,
        "source_note": passage["provenance"]["attribution"] + ". " + passage["provenance"]["adaptation_note"],
    }


# ------------------------------------------------------------- assembly ----

def assemble_paper(
    passages: list[dict], built: list[dict], first_position: int, model: str, partial: bool
) -> dict:
    """The record that is either written to JSON or stored as a draft."""
    section = build_reading_section(built, first_position)
    content = {"sections": [section]}
    problems = validate_paper(content, None if partial else TOTAL_QUESTIONS)
    if problems:
        raise PaperRefused("; ".join(problems))
    source_ids = [p["source"].id for p in passages]
    fingerprint = json.dumps(
        [(p["source"].id, p["source"].revision, p["source"].ebook_id) for p in passages]
    )
    digest = hashlib.sha256(fingerprint.encode()).hexdigest()
    titles = " / ".join(p["source"].title for p in passages)
    generator = {
        "script": "scripts/generate_ielts_paper.py",
        "model": model,
        "reasoning_effort": REASONING_EFFORT,
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "questions": "original, written by an LLM against the passage and verified by a blind second pass",
        "partial": partial,
    }
    return {
        "title": f"IELTS Academic Reading Practice - {titles}"[:255],
        "slug": slug_for(source_ids, digest),
        "description": (
            "Three Academic Reading passages from openly licensed sources with 40 original "
            "questions (True/False/Not Given, matching headings, completion, multiple choice). "
            "Reading only."
        ),
        "test_type": "academic",
        "skill_scope": "reading",
        "target_band": "5.5-7.0",
        "content": content,
        "provenance": build_provenance(
            [p["provenance"] for p in passages], generator, first_position
        ),
    }


def draft_problems(paper: dict) -> list[str]:
    """What the admin publish gate would say, so a draft is never created already broken."""
    from app.routes.admin_ielts import provenance_problems, validate_test_content

    return validate_test_content(paper["content"], paper["skill_scope"]) + provenance_problems(
        paper["content"], paper["provenance"]
    )


async def save_draft(db: Any, paper: dict, replace: bool = False) -> tuple[str, str]:
    """Insert the paper unpublished. Returns (action, id). Never touches a published row."""
    from sqlalchemy import select

    from app.models.ielts import IeltsTest

    existing = (
        await db.execute(select(IeltsTest).where(IeltsTest.slug == paper["slug"]))
    ).scalar_one_or_none()
    if existing is not None:
        if existing.is_published:
            raise PaperRefused(f"{paper['slug']} already exists and is published; not overwriting")
        if not replace:
            raise PaperRefused(f"{paper['slug']} already exists as a draft; pass --replace to rewrite it")
        existing.title = paper["title"]
        existing.description = paper["description"]
        existing.content = paper["content"]
        existing.provenance = paper["provenance"]
        existing.is_published = False
        test, action = existing, "replaced"
    else:
        test = IeltsTest(
            title=paper["title"],
            slug=paper["slug"],
            description=paper["description"],
            test_type=paper["test_type"],
            skill_scope=paper["skill_scope"],
            target_band=paper["target_band"],
            content=paper["content"],
            provenance=paper["provenance"],
            is_published=False,
        )
        db.add(test)
        action = "created"
    await db.commit()
    await db.refresh(test)
    return action, str(test.id)


# ------------------------------------------------------------------ main ----

def load_manifest(path: Path = MANIFEST_PATH) -> list[PassageSource]:
    return parse_manifest(json.loads(path.read_text(encoding="utf-8")))


def groq_keys() -> list[str]:
    return [
        k.strip()
        for k in (os.getenv("GROQ_API_KEYS") or os.getenv("GROQ_API_KEY") or "").split(",")
        if k.strip()
    ]


async def run(args: argparse.Namespace, db: Any = None) -> dict:
    manifest = {s.id: s for s in load_manifest()}
    ids = args.passages.split(",") if args.passages else list(manifest)[:3]
    unknown = [i for i in ids if i not in manifest]
    if unknown:
        raise PaperRefused(f"not in the manifest: {', '.join(unknown)}")
    partial = len(ids) != 3
    if partial and not args.dry_run:
        raise PaperRefused("a paper needs exactly three passages; fewer is only allowed with --dry-run")
    if args.first_position + len(ids) - 1 > len(BLUEPRINT):
        raise PaperRefused("--first-position runs past passage 3")

    headers = {"User-Agent": USER_AGENT}
    async with httpx.AsyncClient(headers=headers, follow_redirects=True, timeout=60.0) as client:
        passages = []
        for pid in ids:
            log(f"fetching {pid}")
            passages.append(await fetch_passage(client, manifest[pid]))
        chat = GroqChat(client, groq_keys(), GROQ_MODEL, args.concurrency, args.delay)
        built = await asyncio.gather(
            *(
                build_passage_groups(chat, passage, args.first_position + offset)
                for offset, passage in enumerate(passages)
            )
        )
    paper = assemble_paper(passages, list(built), args.first_position, GROQ_MODEL, partial)
    problems = [] if partial else draft_problems(paper)
    if problems:
        raise PaperRefused("; ".join(problems))
    return paper


async def main(args: argparse.Namespace) -> int:
    try:
        paper = await run(args)
        if args.dry_run:
            out = Path(args.out or f"{paper['slug']}.json")
            out.write_text(json.dumps(paper, indent=2, ensure_ascii=False), encoding="utf-8")
            print(f"dry run: wrote {out}")
            return 0
        from app.core.database import AsyncSessionLocal

        async with AsyncSessionLocal() as db:
            action, test_id = await save_draft(db, paper, replace=args.replace)
        print(f"{action} draft {paper['slug']} ({test_id}), is_published=false")
        return 0
    except (PaperRefused, ManifestError, RobotsDenied) as exc:
        print(f"REFUSED: {exc}", file=sys.stderr)
        return 1


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--passages", help="comma-separated manifest ids (default: the first three)")
    parser.add_argument("--first-position", type=int, default=1, choices=(1, 2, 3),
                        help="blueprint slot of the first passage; only useful for a one-passage --dry-run")
    parser.add_argument("--dry-run", action="store_true", help="write JSON to --out instead of the database")
    parser.add_argument("--out", help="dry-run output file (default: <slug>.json in the current directory)")
    parser.add_argument("--replace", action="store_true", help="rewrite an existing unpublished draft with the same slug")
    parser.add_argument("--concurrency", type=int, default=2)
    parser.add_argument("--delay", type=float, default=6.0, help="seconds to pause before each LLM call")
    return parser.parse_args(argv)


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main(parse_args())))
