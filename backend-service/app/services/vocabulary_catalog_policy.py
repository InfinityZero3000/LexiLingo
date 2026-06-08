"""Quality and balancing rules for the starter vocabulary catalog."""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Hashable, Iterable, Mapping, Sequence

STARTER_TOPIC_QUOTAS: dict[str, int] = {
    "general": 34,
    "travel": 34,
    "business": 33,
    "daily": 33,
    "science": 33,
    "technology": 33,
}

TOPIC_ALIASES: dict[str, str] = {
    "daily_life": "daily",
}

# Fill the more specific topics before the broad general bucket.
_SELECTION_PRIORITY = (
    "travel",
    "science",
    "technology",
    "daily",
    "business",
    "general",
)

_PLACEHOLDER_DEFINITIONS = {
    "n/a",
    "n/a yet",
    "na",
    "na yet",
    "not available",
    "not available yet",
    "unknown",
    "tbd",
    "todo",
}


@dataclass(frozen=True)
class VocabularyCandidate:
    id: Hashable
    word: str
    definition: str | None
    usage_frequency: int
    tags: Any
    created_at: datetime | None = None


@dataclass(frozen=True)
class StarterVocabularyAssignment:
    candidate: VocabularyCandidate
    topic: str


def _normalized_placeholder_text(value: str | None) -> str:
    text = (value or "").strip().lower()
    text = re.sub(r"\s+", " ", text)
    text = text.lstrip("#").strip()
    text = re.sub(r"[.\-_]+", "", text).strip()
    return text


def is_placeholder_definition(definition: str | None) -> bool:
    """Return whether a definition is empty or a known placeholder."""
    normalized = _normalized_placeholder_text(definition)
    if not normalized:
        return True
    return normalized in _PLACEHOLDER_DEFINITIONS


def canonical_topic(tag: str) -> str:
    normalized = tag.strip().lower()
    return TOPIC_ALIASES.get(normalized, normalized)


def _flatten_tag_values(tags: Any) -> Iterable[str]:
    if isinstance(tags, str):
        yield tags
        return

    if isinstance(tags, Mapping):
        for key in ("source", "topic", "tags", "anki_tags"):
            if key in tags:
                yield from _flatten_tag_values(tags[key])
        return

    if isinstance(tags, Sequence):
        for tag in tags:
            yield from _flatten_tag_values(tag)


def normalize_topic_tags(tags: Any) -> tuple[str, ...]:
    """Extract unique canonical topic tags from legacy JSON payload shapes."""
    normalized: list[str] = []
    for raw_tag in _flatten_tag_values(tags):
        topic = canonical_topic(raw_tag)
        if topic in STARTER_TOPIC_QUOTAS and topic not in normalized:
            normalized.append(topic)
    return tuple(normalized)


def normalize_all_tags(tags: Any) -> list[str]:
    normalized: list[str] = []
    for raw_tag in _flatten_tag_values(tags):
        tag = canonical_topic(raw_tag)
        if tag and tag not in normalized:
            normalized.append(tag)
    return normalized


def has_tag(tags: Any, expected_tag: str) -> bool:
    expected = expected_tag.strip().lower()
    return any(
        raw_tag.strip().lower() == expected for raw_tag in _flatten_tag_values(tags)
    )


def _candidate_sort_key(
    candidate: VocabularyCandidate,
) -> tuple[int, str, str, str]:
    return (
        -max(candidate.usage_frequency or 0, 0),
        candidate.created_at.isoformat() if candidate.created_at else "9999",
        candidate.word.casefold(),
        str(candidate.id),
    )


def select_balanced_starter_vocabulary(
    candidates: Iterable[VocabularyCandidate],
) -> list[StarterVocabularyAssignment]:
    """Select 200 unique valid words using exact per-topic quotas."""
    valid_candidates = [
        candidate
        for candidate in candidates
        if candidate.word.strip()
        and not is_placeholder_definition(candidate.definition)
        and normalize_topic_tags(candidate.tags)
    ]
    valid_candidates.sort(key=_candidate_sort_key)

    selected_ids: set[Hashable] = set()
    assignments: list[StarterVocabularyAssignment] = []

    for topic in _SELECTION_PRIORITY:
        quota = STARTER_TOPIC_QUOTAS[topic]
        topic_candidates = [
            candidate
            for candidate in valid_candidates
            if candidate.id not in selected_ids
            and topic in normalize_topic_tags(candidate.tags)
        ]
        if len(topic_candidates) < quota:
            raise ValueError(
                f"Starter vocabulary topic '{topic}' needs {quota} valid "
                f"items but only {len(topic_candidates)} are available"
            )

        for candidate in topic_candidates[:quota]:
            selected_ids.add(candidate.id)
            assignments.append(
                StarterVocabularyAssignment(candidate=candidate, topic=topic)
            )

    topic_order = {topic: index for index, topic in enumerate(STARTER_TOPIC_QUOTAS)}
    assignments.sort(
        key=lambda assignment: (
            topic_order[assignment.topic],
            _candidate_sort_key(assignment.candidate),
        )
    )
    return assignments
