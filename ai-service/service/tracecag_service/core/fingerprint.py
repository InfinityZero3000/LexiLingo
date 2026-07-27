"""Portable state fingerprinting used by TRACE-CAG service adapters."""

from __future__ import annotations

from dataclasses import dataclass, field
import hashlib
import re
from typing import Any, Mapping, Sequence


_CEFR_ORDER = ("A1", "A2", "B1", "B2", "C1", "C2")

_ENTITY_STOPWORDS = {
    "what", "which", "who", "whom", "whose", "where", "when", "why", "how",
    "many", "much", "the", "and", "that", "this", "those", "these", "with",
    "from", "into", "onto", "about", "person", "company", "film", "movie",
    "creator", "created", "founder", "founded", "director", "directed",
    "writer", "author", "mother", "father", "wife", "brother", "born",
    "birth", "year", "date", "country", "city", "language", "award",
}


@dataclass(frozen=True, slots=True)
class TraceCAGFingerprint:
    """Portable request-state signature for cache and reuse decisions."""

    query_norm: str
    intent: str
    level: str
    profile_epoch: int
    session_turn: int
    concepts: set[str] = field(default_factory=set)
    entities: set[str] = field(default_factory=set)
    answer_target: str = "feedback"
    relation_hints: set[str] = field(default_factory=set)


def normalize_query(text: str) -> str:
    """Normalize user text for stable cache keys."""

    return " ".join((text or "").strip().lower().split())


def infer_intent(text: str) -> str:
    """Cheap pre-diagnosis intent classifier."""

    query = normalize_query(text)
    if any(token in query for token in ("why", "explain", "what does", "how does")):
        return "explain"
    if any(token in query for token in ("practice", "exercise", "quiz", "train")):
        return "practice"
    if query.endswith("?") or any(
        token in query
        for token in ("who", "where", "when", "which", "what", "how many")
    ):
        return "ask"
    return "correct"


def extract_lightweight_concepts(text: str) -> set[str]:
    """Approximate root concepts before a full KG or LLM diagnosis."""

    query = normalize_query(text)
    concepts: set[str] = set()
    pattern_map = {
        r"\b(i|you|we|they)\s+(is|was)\b": "concept:grammar.subject_verb_agreement",
        r"\b(he|she|it)\s+(go|want|need|have|do)\b": "concept:grammar.third_person_s",
        r"\byesterday\b.*\b(go|come|eat|buy|need|want)\b": "concept:grammar.past_time_markers",
        r"\b(have|has)\s+went\b": "concept:grammar.present_perfect",
        r"\bmore\s+better\b|\bmore\s+worse\b": "concept:grammar.comparatives",
        r"\bexplain\b|\bwhy\b|\bwhat does\b": "intent:explain",
        r"\bpractice\b|\bexercise\b|\bquiz\b": "intent:practice",
    }
    for pattern, concept in pattern_map.items():
        if re.search(pattern, query, re.IGNORECASE):
            concepts.add(concept)

    for token in re.findall(r"[a-z0-9][a-z0-9'-]{3,}", query)[:8]:
        concepts.add(f"token:{token.strip('-')}")
    return {concept for concept in concepts if concept}


def extract_entities(text: str) -> set[str]:
    """Extract stable entity-ish tokens for state compatibility checks."""

    query = normalize_query(text)
    entities = {
        token.strip("-'")
        for token in re.findall(r"[a-z0-9][a-z0-9'-]{2,}", query)
        if token not in _ENTITY_STOPWORDS and len(token.strip("-'")) >= 3
    }
    return {entity for entity in entities if entity}


def answer_target_hint(text: str) -> str:
    """Classify the coarse answer target as a hard reuse signal."""

    query = normalize_query(text)
    if any(token in query for token in ("when", "what year", "which year", "date")):
        return "time"
    if any(token in query for token in ("where", "country", "city", "place", "located")):
        return "place"
    if any(token in query for token in ("how many", "how much", "times", "number")):
        return "number"
    if any(
        token in query
        for token in ("who", "mother", "father", "wife", "brother", "founder", "director")
    ):
        return "person"
    if any(token in query for token in ("which", "what")):
        return "entity"
    return "feedback"


def relation_hints(text: str) -> set[str]:
    """Map lexical cues into coarse relation classes for SCAR-L1."""

    query = normalize_query(text)
    relation_map = {
        "founder": ("founder", "founded", "co-founded", "created", "creator"),
        "maker": ("makes", "made by", "manufacturer", "behind"),
        "birth": ("born", "birth"),
        "director": ("director", "directed"),
        "author": ("writer", "author", "wrote"),
        "family": ("mother", "father", "wife", "brother"),
        "time_order": ("came out first", "came first", "first", "earlier", "before", "released"),
        "comparison": ("taller", "higher", "larger", "older", "younger"),
        "location": ("where", "country", "city", "located", "place"),
        "award": ("award", "won"),
    }
    hints: set[str] = set()
    for relation, cues in relation_map.items():
        if any(cue in query for cue in cues):
            hints.add(relation)
    return hints


def profile_epoch(profile: Mapping[str, Any] | None) -> int:
    """Compress learner profile state into a stable epoch integer."""

    profile = profile or {}
    level = normalize_level(str(profile.get("level") or "B1"))
    sessions_completed = int(profile.get("sessions_completed") or 0)
    vocabulary_count = int(profile.get("vocabulary_count") or 0)
    common_errors = profile.get("common_errors") or []
    error_bucket = len(common_errors) // 2 if isinstance(common_errors, Sequence) else 0
    material = f"{level}|{sessions_completed // 3}|{vocabulary_count // 200}|{error_bucket}"
    return int(hashlib.md5(material.encode()).hexdigest()[:8], 16)


def normalize_level(level: str) -> str:
    """Return a known CEFR level, defaulting to B1 for unknown input."""

    upper = (level or "B1").upper()
    return upper if upper in _CEFR_ORDER else "B1"


def build_fingerprint(
    *,
    user_input: str,
    learner_profile: Mapping[str, Any] | None = None,
    conversation_history: Sequence[Mapping[str, Any]] | None = None,
) -> TraceCAGFingerprint:
    """Build the portable request fingerprint."""

    profile = learner_profile or {}
    history = conversation_history or []
    entities = extract_entities(user_input)
    concepts = set(extract_lightweight_concepts(user_input))
    concepts.update(f"entity:{entity}" for entity in entities)
    return TraceCAGFingerprint(
        query_norm=normalize_query(user_input),
        intent=infer_intent(user_input),
        level=normalize_level(str(profile.get("level") or "B1")),
        profile_epoch=profile_epoch(profile),
        session_turn=len(history),
        concepts=concepts,
        entities=entities,
        answer_target=answer_target_hint(user_input),
        relation_hints=relation_hints(user_input),
    )


def build_cache_key(fingerprint: TraceCAGFingerprint) -> str:
    """Build an exact L0 cache key."""

    material = "|".join(
        [
            fingerprint.query_norm,
            fingerprint.intent,
            fingerprint.level,
            str(fingerprint.profile_epoch),
            str(fingerprint.session_turn),
        ]
    )
    return hashlib.md5(material.encode()).hexdigest()


def build_graph_bucket(fingerprint: TraceCAGFingerprint) -> str:
    """Build a graph-state bucket for L1 candidate pooling."""

    material = "|".join(
        [
            "tracecag_l1",
            fingerprint.level,
            fingerprint.intent,
            str(fingerprint.profile_epoch),
            str(fingerprint.session_turn // 2),
            fingerprint.answer_target,
            *sorted(fingerprint.relation_hints),
            *sorted(fingerprint.entities)[:8],
            *sorted(fingerprint.concepts)[:8],
        ]
    )
    return hashlib.md5(material.encode()).hexdigest()
