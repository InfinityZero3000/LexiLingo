"""Dependency-free TRACE-CAG adapter for demos, tests, and new projects."""

from __future__ import annotations

from dataclasses import dataclass
import time

from service.tracecag_service.core.fingerprint import (
    TraceCAGFingerprint,
    build_cache_key,
    build_fingerprint,
    build_graph_bucket,
)
from service.tracecag_service.core.scar_l1 import (
    L1Candidate,
    L1Decision,
    L1Request,
    decide_l1_reuse,
)
from service.tracecag_service.schemas import TraceCAGRequest, TraceCAGResponse


@dataclass(slots=True)
class _MemoryEntry:
    cache_key: str
    bucket: str
    fingerprint: TraceCAGFingerprint
    response: TraceCAGResponse
    created_at: float
    ttl: int


class InMemoryTraceCAGAnalyzer:
    """Tiny portable analyzer that exercises TRACE-CAG cache semantics.

    It does not call an LLM. Use it to prove the service package can run
    without LexiLingo infrastructure, or as a starting point for another
    project to replace with its own KG/LLM implementation.
    """

    def __init__(self, *, ttl_seconds: int = 3600) -> None:
        self.ttl_seconds = ttl_seconds
        self._entries: dict[str, _MemoryEntry] = {}
        self._buckets: dict[str, list[str]] = {}

    async def analyze(self, request: TraceCAGRequest) -> TraceCAGResponse:
        fingerprint = build_fingerprint(
            user_input=request.user_input,
            learner_profile=request.learner_profile,
            conversation_history=request.conversation_history,
        )
        cache_key = build_cache_key(fingerprint)
        bucket = build_graph_bucket(fingerprint)
        now = time.monotonic()

        if request.cache_policy != "off":
            exact = self._entries.get(cache_key)
            if exact and not self._is_stale(exact, now):
                return self._from_cache(exact, "reuse", "L0", 0.0)

            candidate = self._best_l1_candidate(fingerprint, now)
            if candidate is not None:
                entry, decision = candidate
                return self._from_cache(entry, decision.decision, "L1", decision.risk)

        response = self._generate_response(request, fingerprint)
        if request.cache_policy != "off":
            self._entries[cache_key] = _MemoryEntry(
                cache_key=cache_key,
                bucket=bucket,
                fingerprint=fingerprint,
                response=response.copy(),
                created_at=now,
                ttl=self.ttl_seconds,
            )
            self._buckets.setdefault(bucket, []).append(cache_key)
        return response

    async def close(self) -> None:
        self._entries.clear()
        self._buckets.clear()

    def _best_l1_candidate(
        self,
        fingerprint: TraceCAGFingerprint,
        now: float,
    ) -> tuple[_MemoryEntry, L1Decision] | None:
        request_sig = L1Request(
            query_norm=fingerprint.query_norm,
            intent=fingerprint.intent,
            level=fingerprint.level,
            profile_epoch=fingerprint.profile_epoch,
            session_turn=fingerprint.session_turn,
            concepts=set(fingerprint.concepts),
            entities=set(fingerprint.entities),
            answer_target=fingerprint.answer_target,
            relation_hints=set(fingerprint.relation_hints),
        )

        best: tuple[float, _MemoryEntry, L1Decision] | None = None
        for entry in self._entries.values():
            if self._is_stale(entry, now):
                continue
            candidate_sig = L1Candidate(
                cache_key=entry.cache_key,
                query_norm=entry.fingerprint.query_norm,
                intent=entry.fingerprint.intent,
                level=entry.fingerprint.level,
                profile_epoch=entry.fingerprint.profile_epoch,
                session_turn=entry.fingerprint.session_turn,
                concepts=set(entry.fingerprint.concepts),
                entities=set(entry.fingerprint.entities),
                answer_target=entry.fingerprint.answer_target,
                relation_hints=set(entry.fingerprint.relation_hints),
                created_at=entry.created_at,
                ttl=entry.ttl,
            )
            decision = decide_l1_reuse(request_sig, candidate_sig, now=now)
            if not decision.safe_to_reuse:
                continue
            score = decision.rank_score
            if best is None or score > best[0]:
                best = (score, entry, decision)
        if best is None:
            return None
        return best[1], best[2]

    def _from_cache(
        self,
        entry: _MemoryEntry,
        decision: str,
        layer: str,
        risk: float,
    ) -> TraceCAGResponse:
        response = entry.response.copy()
        if decision == "patch":
            response.tutor_response = (
                f"{response.tutor_response}\n\n"
                "State-compatible cache patch applied for this request."
            )
        response.metadata = {
            **response.metadata,
            "path": "fast",
            "cache_hit": True,
            "cache_decision": decision,
            "cache_layer": layer,
            "cache_bucket": entry.bucket,
            "reuse_risk": risk,
            "tokens_saved": max(response.metadata.get("tokens_saved", 0), 128),
        }
        return response

    def _generate_response(
        self,
        request: TraceCAGRequest,
        fingerprint: TraceCAGFingerprint,
    ) -> TraceCAGResponse:
        return TraceCAGResponse(
            tutor_response=(
                "TRACE-CAG portable service analyzed the request. "
                f"Intent: {fingerprint.intent}. Level: {fingerprint.level}."
            ),
            linked_concepts=sorted(fingerprint.concepts),
            scores={
                "fluency": 0.0,
                "grammar": 0.0,
                "overall": 0.0,
                "vocabulary_level": fingerprint.level,
            },
            action={
                "strategy": "portable",
                "next": "wire_real_kg_llm_adapter",
            },
            metadata={
                "path": "slow",
                "cache_hit": False,
                "cache_decision": "full",
                "cache_layer": "none",
                "cache_bucket": build_graph_bucket(fingerprint),
                "reuse_risk": 1.0,
                "tokens_saved": 0,
                "input_type": request.input_type,
            },
        )

    def _is_stale(self, entry: _MemoryEntry, now: float) -> bool:
        return (now - entry.created_at) >= entry.ttl
