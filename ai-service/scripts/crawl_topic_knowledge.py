#!/usr/bin/env python3
"""Crawl and enrich topic knowledge graphs for LexiLingo topic chat.

Default mode is non-destructive:

    python scripts/crawl_topic_knowledge.py --allow-local-fallback

It writes:
    data/topic_graphs.enriched.json
    data/kg_output/topic_knowledge_prefix.txt
    data/kg_output/topic_crawl_report.json
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import tempfile
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

import httpx


AI_SERVICE_ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = AI_SERVICE_ROOT / "data"
DEFAULT_STORIES_PATH = DATA_DIR / "sample_stories.json"
DEFAULT_TOPIC_GRAPHS_PATH = DATA_DIR / "topic_graphs.json"
DEFAULT_ENRICHED_PATH = DATA_DIR / "topic_graphs.enriched.json"
DEFAULT_PREFIX_PATH = DATA_DIR / "kg_output" / "topic_knowledge_prefix.txt"
DEFAULT_KNOWLEDGE_PREFIX_PATH = DATA_DIR / "kg_output" / "knowledge_prefix.txt"
DEFAULT_REPORT_PATH = DATA_DIR / "kg_output" / "topic_crawl_report.json"
DEFAULT_QUOTA_STATE_PATH = (
    AI_SERVICE_ROOT / "model-development" / "reports" / "provider_quota_state.json"
)

DEFAULT_GROQ_MODEL = os.getenv("GROQ_TOPIC_MODEL") or os.getenv("GROQ_MODEL") or "qwen/qwen3-32b"
GROQ_CHAT_URL = "https://api.groq.com/openai/v1/chat/completions"

# crawl4ai reads this at import time. Keep its SQLite/cache files inside the
# repo so sandboxed runs can write them.
os.environ.setdefault("CRAWL4_AI_BASE_DIRECTORY", str(AI_SERVICE_ROOT))

try:
    from crawl4ai import AsyncWebCrawler
except Exception:  # pragma: no cover - import is environment dependent
    AsyncWebCrawler = None  # type: ignore[assignment]

ALLOWED_RELATIONS = {
    "contains",
    "requires",
    "related_to",
    "builds_on",
    "specialization_of",
    "practices",
    "corrects",
    "includes_cost",
    "discusses",
    "part_of",
}

ALLOWED_ID_PREFIXES = (
    "topic:",
    "entity:",
    "concept:vocab.",
    "concept:grammar.",
    "concept:function.",
    "concept:collocation.",
    "concept:phrase.",
)

CEFR_LEVELS = {"A1", "A2", "B1", "B2", "C1", "C2"}

TOPIC_SOURCE_URLS: dict[str, list[str]] = {
    "story_airport_checkin": [
        "https://learnenglish.britishcouncil.org/vocabulary/b1-b2-vocabulary/air-travel",
        "https://learnenglish.britishcouncil.org/skills/listening/a1-listening/at-the-airport",
    ],
    "story_job_interview": [
        "https://learnenglish.britishcouncil.org/business-english/business-magazine/job-interviews",
        "https://learnenglish.britishcouncil.org/skills/listening/b1-listening/job-interview",
    ],
    "story_restaurant_order": [
        "https://learnenglish.britishcouncil.org/vocabulary/a1-a2-vocabulary/restaurants-1",
        "https://learnenglish.britishcouncil.org/skills/listening/a1-listening/ordering-food-cafe",
    ],
    "story_shopping_clothes": [
        "https://learnenglish.britishcouncil.org/skills/listening/a1-listening/shopping-clothes",
        "https://learnenglish.britishcouncil.org/vocabulary/a1-a2-vocabulary/clothes-1",
    ],
    "story_doctor_visit": [
        "https://learnenglish.britishcouncil.org/vocabulary/b1-b2-vocabulary/health",
        "https://learnenglish.britishcouncil.org/vocabulary/a1-a2-vocabulary/body-parts-1",
    ],
    "story_apartment_renting": [
        "https://learnenglish.britishcouncil.org/skills/listening/c1-listening/renting-house",
        "https://learnenglish.ecenglish.com/lessons/vocabulary-renting-apartment",
    ],
    "story_software_interview": [
        "https://learnenglish.britishcouncil.org/business-english/business-magazine/job-interviews",
        "https://www.freecodecamp.org/news/software-engineering-interview-questions-and-answers/",
    ],
    "story_weather_plans": [
        "https://learnenglish.britishcouncil.org/vocabulary/a1-a2-vocabulary/weather",
        "https://learnenglishteens.britishcouncil.org/vocabulary/beginner-vocabulary/weather",
    ],
}


@dataclass
class CrawlResult:
    url: str
    ok: bool
    markdown: str = ""
    error: str = ""


@dataclass
class TopicReport:
    story_id: str
    title: str
    urls: list[str] = field(default_factory=list)
    crawled_ok: int = 0
    crawled_failed: int = 0
    used_groq: bool = False
    used_local_fallback: bool = False
    concepts: int = 0
    edges: int = 0
    errors: list[str] = field(default_factory=list)


class GroqPayloadTooLarge(RuntimeError):
    """Raised when Groq rejects the request body/context size."""


class GroqClientError(RuntimeError):
    """Raised for non-retryable Groq 4xx responses."""


def current_utc_day() -> str:
    return datetime.now(timezone.utc).date().isoformat()


def load_json(path: Path, default: Any | None = None) -> Any:
    if not path.exists():
        if default is not None:
            return default
        raise FileNotFoundError(path)
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def atomic_write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp_name, path)
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)


def atomic_write_json(path: Path, payload: Any) -> None:
    atomic_write_text(path, json.dumps(payload, ensure_ascii=False, indent=2) + "\n")


def slugify(value: str) -> str:
    text = value.strip().lower()
    text = re.sub(r"['’]", "", text)
    text = re.sub(r"[^a-z0-9]+", "_", text)
    return re.sub(r"_+", "_", text).strip("_") or "item"


def topic_slug(story_id: str) -> str:
    raw = story_id.strip()
    if raw.startswith("story_"):
        raw = raw[len("story_") :]
    return slugify(raw)


def topic_concept_id(story_id: str) -> str:
    return f"topic:{topic_slug(story_id)}"


def normalize_level(level: Any, default: str = "B1") -> str:
    candidate = str(level or default).strip().upper()
    return candidate if candidate in CEFR_LEVELS else default


def load_stories(stories_path: Path, topics: Iterable[str] | None = None, limit: int | None = None) -> list[dict[str, Any]]:
    payload = load_json(stories_path)
    raw_stories = payload.get("stories", payload) if isinstance(payload, dict) else payload
    if not isinstance(raw_stories, list):
        raise ValueError(f"Expected stories list in {stories_path}")

    topic_filter = {item.strip() for item in topics or [] if item.strip()}
    stories: list[dict[str, Any]] = []
    for story in raw_stories:
        if not isinstance(story, dict):
            continue
        story_id = str(story.get("story_id") or "").strip()
        if not story_id:
            continue
        if topic_filter and story_id not in topic_filter and topic_slug(story_id) not in topic_filter:
            continue
        stories.append(story)
        if limit and len(stories) >= limit:
            break
    return stories


def story_title(story: dict[str, Any]) -> str:
    title = story.get("title")
    if isinstance(title, dict):
        return str(title.get("en") or title.get("vi") or story.get("story_id") or "Topic")
    return str(title or story.get("story_id") or "Topic")


def story_level(story: dict[str, Any]) -> str:
    return normalize_level(story.get("difficulty_level") or story.get("level"))


def story_context_text(story: dict[str, Any]) -> str:
    parts: list[str] = [f"Story ID: {story.get('story_id', '')}", f"Title: {story_title(story)}"]
    parts.append(f"Level: {story_level(story)}")
    parts.append(f"Category: {story.get('category', '')}")

    context = story.get("context_description") or {}
    if isinstance(context, dict):
        parts.append(f"Setting: {context.get('setting', '')}")
        parts.append(f"Scenario: {context.get('scenario', '')}")
        objectives = context.get("objectives") or []
        if objectives:
            parts.append("Objectives: " + "; ".join(str(item) for item in objectives))

    vocab_terms: list[str] = []
    for item in story.get("vocabulary_list") or []:
        if not isinstance(item, dict):
            continue
        term = str(item.get("term") or item.get("word") or "").strip()
        definition = str(item.get("definition") or "").strip()
        example = str(item.get("example_in_story") or item.get("example") or "").strip()
        if term:
            vocab_terms.append(f"{term}: {definition}. {example}".strip())
    if vocab_terms:
        parts.append("Vocabulary: " + " | ".join(vocab_terms))

    grammar_terms: list[str] = []
    for item in story.get("grammar_points") or []:
        if not isinstance(item, dict):
            continue
        structure = str(item.get("grammar_structure") or item.get("topic") or item.get("name") or "").strip()
        explanation = str(item.get("explanation") or "").strip()
        if structure:
            grammar_terms.append(f"{structure}: {explanation}".strip())
    if grammar_terms:
        parts.append("Grammar: " + " | ".join(grammar_terms))

    return "\n".join(part for part in parts if part.strip())


def compact_markdown(markdown: str, max_chars: int = 18_000) -> str:
    text = re.sub(r"\n{3,}", "\n\n", markdown or "")
    text = re.sub(r"[ \t]{2,}", " ", text)
    text = "\n".join(line.strip() for line in text.splitlines())
    text = text.strip()
    if len(text) <= max_chars:
        return text

    head = text[: max_chars // 2]
    tail = text[-max_chars // 2 :]
    return f"{head}\n\n[...content truncated...]\n\n{tail}"


class GroqKeyPool:
    """Round-robin Groq key pool backed by provider_quota_state.json."""

    def __init__(
        self,
        keys: list[str],
        state_file: Path,
        namespace: str = "groq",
        rpd_per_key: int = 14_400,
    ) -> None:
        self.keys = list(dict.fromkeys(k.strip() for k in keys if k.strip()))
        self.state_file = state_file
        self.namespace = namespace
        self.rpd_per_key = rpd_per_key
        self.index = 0
        self.day_counts: dict[str, int] = {key: 0 for key in self.keys}
        self.cooldown_until: dict[str, float] = {}
        self._load_state()

    @classmethod
    def from_state_file(
        cls,
        state_file: Path,
        namespace: str = "groq",
        extra_keys: Iterable[str] | None = None,
        rpd_per_key: int = 14_400,
    ) -> "GroqKeyPool":
        raw = load_json(state_file, default={"providers": {}})
        provider = ((raw.get("providers") or {}).get(namespace) or {}) if isinstance(raw, dict) else {}
        keys = list((provider.get("day_counts") or {}).keys())
        keys.extend((provider.get("cooldown_until") or {}).keys())
        keys.extend(extra_keys or [])
        env_keys = os.getenv("GROQ_KEYS", "")
        if env_keys:
            keys.extend(item.strip() for item in env_keys.split(","))
        env_key = os.getenv("GROQ_API_KEY", "")
        if env_key:
            keys.append(env_key)
        return cls(keys=keys, state_file=state_file, namespace=namespace, rpd_per_key=rpd_per_key)

    def _load_state(self) -> None:
        raw = load_json(self.state_file, default={"providers": {}})
        provider = ((raw.get("providers") or {}).get(self.namespace) or {}) if isinstance(raw, dict) else {}
        if provider.get("utc_day") == current_utc_day():
            for key, count in (provider.get("day_counts") or {}).items():
                if key in self.day_counts:
                    try:
                        self.day_counts[key] = int(count)
                    except (TypeError, ValueError):
                        self.day_counts[key] = 0
        else:
            self.day_counts = {key: 0 for key in self.keys}

        now = time.time()
        for key, wall_time in (provider.get("cooldown_until") or {}).items():
            if key not in self.day_counts:
                continue
            try:
                until = float(wall_time)
            except (TypeError, ValueError):
                continue
            if until > now:
                self.cooldown_until[key] = until

        try:
            self.index = int(provider.get("index", 0)) % max(len(self.keys), 1)
        except (TypeError, ValueError):
            self.index = 0

    def has_keys(self) -> bool:
        return bool(self.keys)

    def pick(self, exclude: set[str] | None = None) -> str | None:
        if not self.keys:
            return None
        excluded = exclude or set()
        now = time.time()
        for _ in range(len(self.keys)):
            key = self.keys[self.index % len(self.keys)]
            self.index = (self.index + 1) % max(len(self.keys), 1)
            if key in excluded:
                continue
            if self.cooldown_until.get(key, 0.0) > now:
                continue
            if self.day_counts.get(key, 0) >= self.rpd_per_key:
                continue
            return key
        return None

    def soonest_available_in(self, exclude: set[str] | None = None) -> float:
        excluded = exclude or set()
        now = time.time()
        waits = [
            max(0.0, self.cooldown_until.get(key, now) - now)
            for key in self.keys
            if key not in excluded and self.day_counts.get(key, 0) < self.rpd_per_key
        ]
        return min(waits) if waits else float("inf")

    def on_success(self, key: str) -> None:
        if key in self.day_counts:
            self.day_counts[key] = self.day_counts.get(key, 0) + 1
        self.persist()

    def on_fail(self, key: str, cooldown_seconds: float = 65.0) -> None:
        if key in self.day_counts:
            self.cooldown_until[key] = time.time() + max(cooldown_seconds, 1.0)
        self.persist()

    def clear_cooldowns(self) -> None:
        self.cooldown_until = {}
        self.persist()

    def persist(self) -> None:
        payload = load_json(self.state_file, default={"providers": {}})
        if not isinstance(payload, dict):
            payload = {}
        providers = payload.setdefault("providers", {})
        providers[self.namespace] = {
            "utc_day": current_utc_day(),
            "index": self.index,
            "day_counts": {key: self.day_counts.get(key, 0) for key in self.keys},
            "cooldown_until": {
                key: until
                for key, until in self.cooldown_until.items()
                if key in self.day_counts and until > time.time()
            },
        }
        atomic_write_json(self.state_file, payload)


def extract_json_object(text: str) -> dict[str, Any]:
    raw = (text or "").strip()
    if raw.startswith("```"):
        raw = re.sub(r"^```(?:json)?\s*", "", raw, flags=re.IGNORECASE)
        raw = re.sub(r"\s*```$", "", raw)

    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        start = raw.find("{")
        end = raw.rfind("}")
        if start < 0 or end <= start:
            raise
        parsed = json.loads(raw[start : end + 1])

    if not isinstance(parsed, dict):
        raise ValueError("Groq response must be a JSON object")
    return parsed


def sanitize_concept(raw: dict[str, Any], default_level: str) -> dict[str, Any] | None:
    node_id = str(raw.get("id") or "").strip().lower()
    if not node_id or not node_id.startswith(ALLOWED_ID_PREFIXES):
        return None
    if not re.fullmatch(r"[a-z0-9:._-]+", node_id):
        return None
    title = str(raw.get("title") or node_id).strip()
    keywords = str(raw.get("keywords") or title).strip()
    concept = {
        "id": node_id,
        "title": title,
        "level": normalize_level(raw.get("level"), default_level),
        "keywords": normalize_keywords(keywords),
    }
    source_urls = raw.get("source_urls")
    if isinstance(source_urls, list):
        concept["source_urls"] = [str(url) for url in source_urls if str(url).strip()][:5]
    return concept


def sanitize_edge(raw: dict[str, Any]) -> dict[str, str] | None:
    from_id = str(raw.get("from") or "").strip().lower()
    to_id = str(raw.get("to") or "").strip().lower()
    relation = str(raw.get("relation") or "related_to").strip().lower()
    relation = re.sub(r"[^a-z0-9_]+", "_", relation).strip("_") or "related_to"
    if not from_id or not to_id:
        return None
    if relation not in ALLOWED_RELATIONS:
        relation = "related_to"
    return {"from": from_id, "to": to_id, "relation": relation}


def normalize_keywords(keywords: str) -> str:
    tokens = re.findall(r"[a-zA-Z0-9][a-zA-Z0-9'/-]*", keywords)
    seen: set[str] = set()
    clean: list[str] = []
    for token in tokens:
        normalized = token.lower().strip("'/-")
        if len(normalized) < 2 or normalized in seen:
            continue
        seen.add(normalized)
        clean.append(normalized)
    return " ".join(clean[:80])


def validate_extraction(
    payload: dict[str, Any],
    story: dict[str, Any],
    known_ids: set[str] | None = None,
) -> dict[str, Any]:
    default_level = story_level(story)
    known = set(known_ids or set())
    concepts: dict[str, dict[str, Any]] = {}
    edges: dict[tuple[str, str, str], dict[str, str]] = {}

    topic_id = topic_concept_id(str(story.get("story_id") or "topic"))
    topic_node = {
        "id": topic_id,
        "title": story_title(story),
        "level": default_level,
        "keywords": normalize_keywords(story_context_text(story)),
    }
    concepts[topic_id] = topic_node

    for raw in payload.get("concepts") or []:
        if not isinstance(raw, dict):
            continue
        concept = sanitize_concept(raw, default_level)
        if not concept:
            continue
        if concept["id"] in concepts:
            concepts[concept["id"]] = merge_concept(concepts[concept["id"]], concept)
        else:
            concepts[concept["id"]] = concept

    all_ids = known | set(concepts)
    for raw in payload.get("edges") or []:
        if not isinstance(raw, dict):
            continue
        edge = sanitize_edge(raw)
        if not edge:
            continue
        if edge["from"] not in all_ids or edge["to"] not in all_ids:
            continue
        edges[(edge["from"], edge["to"], edge["relation"])] = edge

    for concept_id in concepts:
        if concept_id == topic_id:
            continue
        edge = {"from": topic_id, "to": concept_id, "relation": "contains"}
        edges[(edge["from"], edge["to"], edge["relation"])] = edge

    source_notes = payload.get("source_notes") if isinstance(payload.get("source_notes"), list) else []
    return {
        "concepts": list(concepts.values()),
        "edges": list(edges.values()),
        "source_notes": source_notes[:20],
    }


def merge_concept(existing: dict[str, Any], incoming: dict[str, Any]) -> dict[str, Any]:
    merged = dict(existing)
    if not merged.get("title") and incoming.get("title"):
        merged["title"] = incoming["title"]
    if not merged.get("level") and incoming.get("level"):
        merged["level"] = incoming["level"]

    keywords = normalize_keywords(f"{existing.get('keywords', '')} {incoming.get('keywords', '')}")
    if keywords:
        merged["keywords"] = keywords

    urls: list[str] = []
    for concept in (existing, incoming):
        raw_urls = concept.get("source_urls")
        if isinstance(raw_urls, list):
            for url in raw_urls:
                url_text = str(url).strip()
                if url_text and url_text not in urls:
                    urls.append(url_text)
    if urls:
        merged["source_urls"] = urls[:8]
    return merged


def merge_knowledge(existing: dict[str, Any], additions: list[dict[str, Any]]) -> dict[str, Any]:
    merged = {
        "version": str(existing.get("version") or "1.1.0"),
        "description": str(
            existing.get("description")
            or "Topic-specific knowledge graphs for LexiLingo TraceCAG"
        ),
        "concepts": [],
        "edges": [],
    }

    concepts: dict[str, dict[str, Any]] = {}
    edges: dict[tuple[str, str, str], dict[str, str]] = {}

    for concept in existing.get("concepts") or []:
        if isinstance(concept, dict) and concept.get("id"):
            concepts[str(concept["id"]).lower()] = dict(concept, id=str(concept["id"]).lower())

    for payload in additions:
        for concept in payload.get("concepts") or []:
            if not isinstance(concept, dict) or not concept.get("id"):
                continue
            cid = str(concept["id"]).lower()
            if cid in concepts:
                concepts[cid] = merge_concept(concepts[cid], dict(concept, id=cid))
            else:
                concepts[cid] = dict(concept, id=cid)

    known_ids = set(concepts)
    for edge in existing.get("edges") or []:
        cleaned = sanitize_edge(edge) if isinstance(edge, dict) else None
        if cleaned and cleaned["from"] in known_ids and cleaned["to"] in known_ids:
            edges[(cleaned["from"], cleaned["to"], cleaned["relation"])] = cleaned

    for payload in additions:
        for edge in payload.get("edges") or []:
            cleaned = sanitize_edge(edge) if isinstance(edge, dict) else None
            if cleaned and cleaned["from"] in known_ids and cleaned["to"] in known_ids:
                edges[(cleaned["from"], cleaned["to"], cleaned["relation"])] = cleaned

    merged["concepts"] = sorted(concepts.values(), key=lambda item: str(item.get("id", "")))
    merged["edges"] = sorted(
        edges.values(),
        key=lambda item: (item["from"], item["relation"], item["to"]),
    )
    return merged


def collect_known_concept_ids(data_dir: Path, topic_graphs: dict[str, Any]) -> set[str]:
    ids: set[str] = set()
    for concept in topic_graphs.get("concepts") or []:
        if isinstance(concept, dict) and concept.get("id"):
            ids.add(str(concept["id"]).lower())

    candidate_files = [data_dir / "knowledge_extended.json"]
    kg_dir = data_dir / "kg"
    if kg_dir.exists():
        candidate_files.extend(sorted(kg_dir.glob("*.json")))

    for path in candidate_files:
        if not path.exists():
            continue
        try:
            payload = load_json(path)
        except Exception:
            continue
        for concept in payload.get("concepts") or []:
            if isinstance(concept, dict) and concept.get("id"):
                ids.add(str(concept["id"]).lower())
    return ids


def build_local_payload(story: dict[str, Any], source_urls: list[str]) -> dict[str, Any]:
    sid = str(story.get("story_id") or "topic")
    tslug = topic_slug(sid)
    topic_id = topic_concept_id(sid)
    level = story_level(story)

    concepts: list[dict[str, Any]] = [
        {
            "id": topic_id,
            "title": story_title(story),
            "level": level,
            "keywords": normalize_keywords(story_context_text(story)),
            "source_urls": source_urls,
        },
        {
            "id": f"concept:vocab.{tslug}",
            "title": f"{story_title(story)} Vocabulary",
            "level": level,
            "keywords": normalize_keywords(story_context_text(story)),
            "source_urls": source_urls,
        },
    ]
    edges: list[dict[str, str]] = [
        {"from": topic_id, "to": f"concept:vocab.{tslug}", "relation": "contains"}
    ]

    for item in story.get("vocabulary_list") or []:
        if not isinstance(item, dict):
            continue
        term = str(item.get("term") or item.get("word") or "").strip()
        if not term:
            continue
        cid = f"entity:{slugify(term)}"
        concepts.append(
            {
                "id": cid,
                "title": term,
                "level": level,
                "keywords": normalize_keywords(
                    f"{term} {item.get('definition', '')} {item.get('example_in_story', '')}"
                ),
                "source_urls": source_urls,
            }
        )
        edges.append({"from": topic_id, "to": cid, "relation": "contains"})
        edges.append({"from": f"concept:vocab.{tslug}", "to": cid, "relation": "contains"})

    for item in story.get("grammar_points") or []:
        if not isinstance(item, dict):
            continue
        structure = str(item.get("grammar_structure") or item.get("topic") or item.get("name") or "").strip()
        if not structure:
            continue
        cid = f"concept:grammar.{slugify(structure)}"
        concepts.append(
            {
                "id": cid,
                "title": structure,
                "level": level,
                "keywords": normalize_keywords(
                    f"{structure} {item.get('explanation', '')} {item.get('usage_in_story', '')}"
                ),
                "source_urls": source_urls,
            }
        )
        edges.append({"from": topic_id, "to": cid, "relation": "practices"})

    return {
        "concepts": concepts,
        "edges": edges,
        "source_notes": [
            {
                "url": url,
                "summary": "Local story context used because crawl/Groq enrichment was unavailable.",
            }
            for url in source_urls
        ],
    }


def build_groq_prompt(story: dict[str, Any], crawl_results: list[CrawlResult], max_source_chars: int) -> str:
    source_blocks: list[str] = []
    ok_results = [result for result in crawl_results if result.ok and result.markdown]
    per_source_chars = max(1200, max_source_chars // max(len(ok_results), 1))
    for result in ok_results:
        source_blocks.append(
            f"URL: {result.url}\nCONTENT:\n{compact_markdown(result.markdown, per_source_chars)}"
        )
    sources = "\n\n---\n\n".join(source_blocks) or "No external crawl content was available."

    return f"""
You are building a compact English-learning knowledge graph for LexiLingo topic chat.

Return ONLY valid JSON. No markdown. No commentary.

Story context:
{story_context_text(story)}

External crawl sources:
{sources}

Create topic-specific knowledge. Prefer useful conversation data: vocabulary,
phrases, grammar, collocations, speech functions, scenario entities, and
relationships that help an English tutor stay grounded in the topic.

Required JSON shape:
{{
  "concepts": [
    {{
      "id": "topic:{topic_slug(str(story.get("story_id") or "topic"))}",
      "title": "Readable title",
      "level": "{story_level(story)}",
      "keywords": "lowercase keyword list",
      "source_urls": ["https://..."]
    }}
  ],
  "edges": [
    {{"from": "topic:...", "to": "concept:vocab....", "relation": "contains"}}
  ],
  "source_notes": [
    {{"url": "https://...", "summary": "short factual source summary"}}
  ]
}}

Rules:
- Include exactly one topic node with id "{topic_concept_id(str(story.get("story_id") or "topic"))}".
- Add 8 to 18 additional concepts.
- Allowed id prefixes: {", ".join(ALLOWED_ID_PREFIXES)}.
- Use lowercase slug ids with no spaces.
- Allowed relations: {", ".join(sorted(ALLOWED_RELATIONS))}.
- Keep keywords concise, factual, and relevant to English conversation practice.
- Do not include unsafe medical/legal/financial advice; only language-learning vocabulary and phrases.
""".strip()


async def crawl_url(url: str, timeout: float = 40.0) -> CrawlResult:
    if AsyncWebCrawler is None:
        return CrawlResult(url=url, ok=False, error="crawl4ai is not installed")

    try:
        async with AsyncWebCrawler() as crawler:
            result = await asyncio.wait_for(crawler.arun(url=url), timeout=timeout)
        markdown = getattr(result, "markdown", "") or ""
        if not isinstance(markdown, str):
            markdown = str(markdown)
        if not markdown.strip():
            return CrawlResult(url=url, ok=False, error="empty markdown")
        return CrawlResult(url=url, ok=True, markdown=markdown)
    except Exception as exc:
        return CrawlResult(url=url, ok=False, error=str(exc))


async def crawl_topic_urls(urls: list[str], timeout: float) -> list[CrawlResult]:
    return await asyncio.gather(*(crawl_url(url, timeout=timeout) for url in urls))


async def call_groq(
    prompt: str,
    key_pool: GroqKeyPool,
    model: str,
    temperature: float = 0.1,
    max_tokens: int = 2200,
    wait_for_quota_seconds: float = 0.0,
) -> dict[str, Any]:
    excluded: set[str] = set()
    last_error: Exception | None = None
    wait_deadline = time.monotonic() + max(0.0, wait_for_quota_seconds)

    while True:
        key = key_pool.pick(exclude=excluded)
        if not key:
            wait = key_pool.soonest_available_in(exclude=excluded)
            if wait_for_quota_seconds > 0 and wait != float("inf"):
                remaining_budget = wait_deadline - time.monotonic()
                if remaining_budget > 0 and wait <= remaining_budget:
                    await asyncio.sleep(wait + 0.5)
                    continue
            if last_error:
                raise RuntimeError(f"No Groq key available after failures: {last_error}") from last_error
            raise RuntimeError("No Groq key available")

        try:
            request_payload: dict[str, Any] = {
                "model": model,
                "messages": [
                    {
                        "role": "system",
                        "content": "You output strict JSON for a knowledge graph extraction task.",
                    },
                    {"role": "user", "content": prompt},
                ],
                "temperature": temperature,
                "max_tokens": max_tokens,
                "response_format": {"type": "json_object"},
            }
            async with httpx.AsyncClient(timeout=90.0) as client:
                response = await client.post(
                    GROQ_CHAT_URL,
                    headers={
                        "Authorization": f"Bearer {key}",
                        "Content-Type": "application/json",
                    },
                    json=request_payload,
                )
                if response.status_code == 400 and "json_validate_failed" in response.text:
                    request_payload.pop("response_format", None)
                    response = await client.post(
                        GROQ_CHAT_URL,
                        headers={
                            "Authorization": f"Bearer {key}",
                            "Content-Type": "application/json",
                        },
                        json=request_payload,
                    )
            if response.status_code in {429, 500, 502, 503, 504}:
                retry_after = response.headers.get("retry-after")
                cooldown = float(retry_after) if retry_after and retry_after.isdigit() else 65.0
                key_pool.on_fail(key, cooldown_seconds=cooldown)
                last_error = RuntimeError(f"Groq HTTP {response.status_code}")
                if response.status_code != 429:
                    excluded.add(key)
                continue
            if response.status_code in {401, 403}:
                excluded.add(key)
                last_error = GroqClientError(f"Groq HTTP {response.status_code}: invalid or unauthorized key")
                continue
            if response.status_code == 413:
                raise GroqPayloadTooLarge("Groq rejected the prompt as too large")
            if 400 <= response.status_code < 500:
                raise GroqClientError(f"Groq HTTP {response.status_code}: {response.text[:300]}")
            response.raise_for_status()
            data = response.json()
            content = data["choices"][0]["message"]["content"]
            parsed = extract_json_object(content)
            key_pool.on_success(key)
            return parsed
        except GroqPayloadTooLarge:
            raise
        except GroqClientError:
            raise
        except (json.JSONDecodeError, ValueError):
            raise
        except (httpx.ConnectError, httpx.NetworkError, httpx.TimeoutException) as exc:
            raise RuntimeError(f"Groq network error: {exc}") from exc
        except Exception as exc:
            key_pool.on_fail(key)
            excluded.add(key)
            last_error = exc


async def repair_with_groq(raw_text: str, key_pool: GroqKeyPool, model: str) -> dict[str, Any]:
    prompt = f"""
Repair this malformed knowledge graph response into ONLY valid JSON with
"concepts", "edges", and "source_notes" keys. Preserve useful facts.

Malformed response:
{raw_text[:8000]}
""".strip()
    return await call_groq(prompt, key_pool=key_pool, model=model, temperature=0.0, max_tokens=1800)


async def enrich_story(
    story: dict[str, Any],
    known_ids: set[str],
    key_pool: GroqKeyPool | None,
    model: str,
    allow_local_fallback: bool,
    crawl_timeout: float,
    max_source_chars: int,
    wait_for_quota_seconds: float,
) -> tuple[dict[str, Any], TopicReport]:
    sid = str(story.get("story_id") or "")
    urls = TOPIC_SOURCE_URLS.get(sid, [])
    report = TopicReport(story_id=sid, title=story_title(story), urls=urls)

    crawl_results = await crawl_topic_urls(urls, timeout=crawl_timeout) if urls else []
    report.crawled_ok = sum(1 for result in crawl_results if result.ok)
    report.crawled_failed = sum(1 for result in crawl_results if not result.ok)
    for result in crawl_results:
        if not result.ok:
            report.errors.append(f"crawl failed for {result.url}: {result.error}")

    payload: dict[str, Any] | None = None
    if key_pool and key_pool.has_keys():
        try:
            prompt = build_groq_prompt(story, crawl_results, max_source_chars=max_source_chars)
            payload = await call_groq(
                prompt,
                key_pool=key_pool,
                model=model,
                wait_for_quota_seconds=wait_for_quota_seconds,
            )
            report.used_groq = True
        except Exception as exc:
            report.errors.append(f"groq extraction failed: {exc}")

    if payload is None:
        if not allow_local_fallback:
            raise RuntimeError(f"No Groq extraction available for {sid}; use --allow-local-fallback to continue")
        payload = build_local_payload(story, urls)
        report.used_local_fallback = True

    validated = validate_extraction(payload, story, known_ids=known_ids)
    report.concepts = len(validated["concepts"])
    report.edges = len(validated["edges"])
    return validated, report


def render_knowledge_prefix(graph: dict[str, Any], max_edges: int | None = None) -> str:
    concepts = {
        str(concept.get("id") or "").lower(): concept
        for concept in graph.get("concepts") or []
        if isinstance(concept, dict) and concept.get("id")
    }

    lines = ["[LEXILINGO KNOWLEDGE BASE]"]
    count = 0
    for edge in graph.get("edges") or []:
        if not isinstance(edge, dict):
            continue
        from_id = str(edge.get("from") or "").lower()
        to_id = str(edge.get("to") or "").lower()
        relation = str(edge.get("relation") or "related_to")
        if from_id not in concepts or to_id not in concepts:
            continue
        src = concepts[from_id]
        dst = concepts[to_id]
        lines.append(
            f"- ({src.get('title', from_id)} ({concept_type(from_id)})) "
            f"-[{relation}]-> "
            f"({dst.get('title', to_id)} ({concept_type(to_id)})) "
            f"[Source: topic_crawl]"
        )
        count += 1
        if max_edges and count >= max_edges:
            break
    return "\n".join(lines) + "\n"


def concept_type(concept_id: str) -> str:
    if concept_id.startswith("topic:"):
        return "Topic"
    if concept_id.startswith("entity:"):
        return "Vocabulary"
    if concept_id.startswith("concept:grammar."):
        return "Grammar"
    if concept_id.startswith("concept:function."):
        return "Function"
    if concept_id.startswith("concept:collocation."):
        return "Collocation"
    if concept_id.startswith("concept:phrase."):
        return "Phrase"
    if concept_id.startswith("concept:vocab."):
        return "Vocabulary"
    return "Concept"


def parse_topic_args(values: list[str] | None) -> list[str]:
    topics: list[str] = []
    for value in values or []:
        topics.extend(part.strip() for part in value.split(",") if part.strip())
    return topics


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Crawl and enrich LexiLingo topic knowledge data.")
    parser.add_argument("--stories", type=Path, default=DEFAULT_STORIES_PATH)
    parser.add_argument("--topic-graphs", type=Path, default=DEFAULT_TOPIC_GRAPHS_PATH)
    parser.add_argument("--quota-state", type=Path, default=DEFAULT_QUOTA_STATE_PATH)
    parser.add_argument("--output", type=Path, default=DEFAULT_ENRICHED_PATH)
    parser.add_argument("--prefix-output", type=Path, default=DEFAULT_PREFIX_PATH)
    parser.add_argument("--report-output", type=Path, default=DEFAULT_REPORT_PATH)
    parser.add_argument("--topics", nargs="*", default=None, help="Story IDs or slugs. Comma-separated is also accepted.")
    parser.add_argument("--limit", type=int, default=None)
    parser.add_argument("--model", default=DEFAULT_GROQ_MODEL)
    parser.add_argument("--crawl-timeout", type=float, default=40.0)
    parser.add_argument("--max-source-chars", type=int, default=6_000)
    parser.add_argument("--rpd-per-key", type=int, default=14_400)
    parser.add_argument("--merge", action="store_true", help="Update data/topic_graphs.json instead of writing only the enriched copy.")
    parser.add_argument("--update-prefix", action="store_true", help="Write to kg_output/knowledge_prefix.txt as well.")
    parser.add_argument("--dry-run", action="store_true", help="Run extraction but do not write output files.")
    parser.add_argument("--allow-local-fallback", action="store_true", help="Generate from bundled story data if crawl/Groq fails.")
    parser.add_argument("--clear-cooldowns", action="store_true", help="Clear persisted Groq cooldowns before running.")
    parser.add_argument("--wait-for-quota-seconds", type=float, default=0.0, help="Wait this long per Groq call for a rate-limited key to become available.")
    return parser


async def run(args: argparse.Namespace) -> dict[str, Any]:
    topics = parse_topic_args(args.topics)
    stories = load_stories(args.stories, topics=topics, limit=args.limit)
    if not stories:
        raise RuntimeError("No matching stories found")

    topic_graphs = load_json(args.topic_graphs, default={"version": "1.1.0", "concepts": [], "edges": []})
    known_ids = collect_known_concept_ids(DATA_DIR, topic_graphs)

    key_pool: GroqKeyPool | None = None
    if args.quota_state.exists() or os.getenv("GROQ_KEYS") or os.getenv("GROQ_API_KEY"):
        key_pool = GroqKeyPool.from_state_file(
            args.quota_state,
            namespace="groq",
            rpd_per_key=args.rpd_per_key,
        )
        if args.clear_cooldowns:
            key_pool.clear_cooldowns()

    additions: list[dict[str, Any]] = []
    reports: list[TopicReport] = []
    for story in stories:
        addition, report = await enrich_story(
            story,
            known_ids=known_ids,
            key_pool=key_pool,
            model=args.model,
            allow_local_fallback=args.allow_local_fallback,
            crawl_timeout=args.crawl_timeout,
            max_source_chars=args.max_source_chars,
            wait_for_quota_seconds=args.wait_for_quota_seconds,
        )
        additions.append(addition)
        known_ids.update(str(concept.get("id")).lower() for concept in addition.get("concepts") or [])
        reports.append(report)

    merged = merge_knowledge(topic_graphs, additions)
    prefix = render_knowledge_prefix(merged)
    report_payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "model": args.model,
        "stories_processed": len(stories),
        "concept_count": len(merged.get("concepts") or []),
        "edge_count": len(merged.get("edges") or []),
        "reports": [report.__dict__ for report in reports],
    }

    if not args.dry_run:
        output_path = args.topic_graphs if args.merge else args.output
        atomic_write_json(output_path, merged)
        atomic_write_text(args.prefix_output, prefix)
        if args.update_prefix:
            atomic_write_text(DEFAULT_KNOWLEDGE_PREFIX_PATH, prefix)
        atomic_write_json(args.report_output, report_payload)

    return report_payload


def main() -> None:
    parser = build_arg_parser()
    args = parser.parse_args()
    report = asyncio.run(run(args))

    groq_count = sum(1 for item in report["reports"] if item.get("used_groq"))
    fallback_count = sum(1 for item in report["reports"] if item.get("used_local_fallback"))
    print(
        "Topic crawl complete: "
        f"stories={report['stories_processed']} "
        f"concepts={report['concept_count']} "
        f"edges={report['edge_count']} "
        f"groq={groq_count} "
        f"fallback={fallback_count}"
    )
    if not args.dry_run:
        output_path = args.topic_graphs if args.merge else args.output
        print(f"Graph output: {output_path}")
        print(f"Prefix output: {args.prefix_output}")
        print(f"Report output: {args.report_output}")


if __name__ == "__main__":
    main()
