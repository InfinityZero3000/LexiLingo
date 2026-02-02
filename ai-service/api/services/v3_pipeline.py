"""V3 knowledge-centric pipeline (skeleton).

This pipeline is designed to be wired into the existing /api/v1/ai/analyze endpoint.

Key goals:
- Fast path via Redis response cache
- Slow path via Diagnose -> Retrieval (Vector+KG) -> templated grounded response
- Background jobs for KG write-back and personalized practice generation
"""

from __future__ import annotations

import time
from typing import Any, Dict, Optional

from api.core.redis_client import (
    ConversationCache,
    LearnerProfileCache,
    RedisClient,
    ResponseCache,
)
from api.models.v3_schemas import (
    ActionPlanItem,
    CacheMeta,
    Correction,
    LinkedConcept,
    TutorResponseMeta,
    TutorResponseV3,
    V3PipelineContext,
)
from api.services.background_jobs_v3 import BackgroundJobsV3
from api.services.diagnoser_v3 import DiagnoserV3
from api.services.grounded_response_v3 import GroundedResponseV3
from api.services.kg_service_v3 import KnowledgeGraphServiceV3
from api.services.retrieval_service_v3 import RetrievalConfig, RetrievalServiceV3
from api.services.graph_analytics import get_graph_analytics


class V3Pipeline:
    def __init__(self):
        self._initialized = False

        self.redis_available = False
        self.response_cache: Optional[ResponseCache] = None
        self.learner_cache: Optional[LearnerProfileCache] = None
        self.conversation_cache: Optional[ConversationCache] = None

        self.kg = KnowledgeGraphServiceV3()
        self.diagnoser = DiagnoserV3()
        self.retrieval = RetrievalServiceV3(self.kg)
        self.grounded = GroundedResponseV3(self.kg)
        self.bg: Optional[BackgroundJobsV3] = None

    async def initialize(self) -> None:
        if self._initialized:
            return

        try:
            redis_client = await RedisClient.get_instance()
            # Even if ping fails internally, the instance may still exist.
            self.response_cache = ResponseCache(redis_client)
            self.learner_cache = LearnerProfileCache(redis_client)
            self.conversation_cache = ConversationCache(redis_client)
            self.redis_available = True
        except Exception:
            self.redis_available = False
            self.response_cache = None
            self.learner_cache = None
            self.conversation_cache = None

        self.bg = BackgroundJobsV3(
            learner_cache=self.learner_cache,
            conversation_cache=self.conversation_cache,
            kg=self.kg,
        )

        self._initialized = True

    async def analyze(
        self,
        *,
        text: str,
        session_id: str,
        user_id: Optional[str],
        learner_profile: Optional[Dict[str, Any]],
    ) -> TutorResponseV3:
        await self.initialize()

        start = time.time()

        resolved_user_id = user_id or "anonymous"

        history = []
        if self.conversation_cache:
            history = await self.conversation_cache.get_history(session_id)

        resolved_profile = learner_profile or {}
        if self.learner_cache and resolved_user_id and resolved_user_id != "anonymous":
            # Merge: request profile overrides cached if provided.
            cached = await self.learner_cache.get_profile(resolved_user_id)
            resolved_profile = {**cached, **resolved_profile}

        ctx = V3PipelineContext(
            user_input=text,
            session_id=session_id,
            user_id=resolved_user_id,
            metadata={
                "learner_profile": resolved_profile,
                "history": history,
                "context_summary": "",
            }
        )

        cache_key = None
        if self.response_cache:
            # Simple cache key that is stable enough for the skeleton.
            level = str(resolved_profile.get("level", "B1"))
            cache_key = f"v3:{level}:{hash(text)}"
            cached = await self.response_cache.get(cache_key)
            if cached:
                latency_ms = int((time.time() - start) * 1000)
                # Ensure metadata exists / override minimally.
                cached.setdefault("metadata", {})
                cached["metadata"] = {
                    "path": "fast",
                    "latency_ms": latency_ms,
                    "models_used": [],
                    "cache": {"hit": True, "key": cache_key},
                }
                return TutorResponseV3.model_validate(cached)

        diagnosis = await self.diagnoser.diagnose(text, ctx)

        # If low confidence -> fast clarifying question
        if diagnosis.next_best_action == "ask_clarify":
            tutor_text = "Mình cần thêm 1 chút thông tin: bạn muốn mình sửa câu này, giải thích ngữ pháp, hay tạo bài tập luyện?"
            latency_ms = int((time.time() - start) * 1000)
            response = TutorResponseV3(
                tutor_response=tutor_text,
                corrections=[],
                linked_concepts=[],
                action_plan=[ActionPlanItem(action="ask")],
                confidence=diagnosis.confidence,
                metadata=TutorResponseMeta(
                    path="fast",
                    latency_ms=latency_ms,
                    models_used=[],
                    cache=CacheMeta(hit=False, key=cache_key),
                ),
                diagnosis=diagnosis,
            )
            return response

        seed_concepts = diagnosis.root_cause_candidates
        retrieval = await self.retrieval.retrieve(text, seed_concepts, ctx)

        # Grounded response (template-based, constrained by RetrievalBundleV3)
        corrections = []
        if any(e.span.lower() == "i goes" for e in diagnosis.suspected_errors):
            corrections.append(Correction(error="I goes", correction="I go", type="subject_verb_agreement"))

        tutor_response = self.grounded.build(text, diagnosis, retrieval)

        if not seed_concepts:
            seed_concepts = [hit.id for hit in retrieval.vector_hits[:2]]

        linked = [LinkedConcept(id=c, weight=0.9) for c in seed_concepts]
        action_plan = []
        if seed_concepts:
            action_plan.append(ActionPlanItem(action="practice", concept=seed_concepts[0], count=5))

        latency_ms = int((time.time() - start) * 1000)
        response = TutorResponseV3(
            tutor_response=tutor_response,
            corrections=corrections,
            linked_concepts=linked,
            action_plan=action_plan,
            confidence=max(0.5, diagnosis.confidence),
            metadata=TutorResponseMeta(
                path="slow",
                latency_ms=latency_ms,
                models_used=[],
                cache=CacheMeta(hit=False, key=cache_key),
            ),
            vietnamese_hint=None,
            pronunciation_tip=None,
            diagnosis=diagnosis,
            retrieval=retrieval,
        )

        # Cache slow response
        if self.response_cache and cache_key:
            await self.response_cache.set(cache_key, response.model_dump(by_alias=True))

        # Schedule background updates
        if self.bg:
            error_types = [e.type for e in diagnosis.suspected_errors]
            self.bg.schedule(
                user_id=resolved_user_id,
                session_id=session_id,
                user_message=text,
                ai_response=response.tutor_response,
                analysis={"diagnosis": diagnosis.model_dump()},
                linked_concepts=seed_concepts,
                error_types=error_types,
            )

        return response

    def get_graph_analytics_summary(self) -> Dict[str, Any]:
        """
        Get graph analytics summary for debugging/monitoring.
        
        Returns:
            Dict with centrality scores, communities, and top concepts
        """
        return self.retrieval.get_analytics_summary()


_v3_pipeline: Optional[V3Pipeline] = None


async def get_v3_pipeline() -> V3Pipeline:
    global _v3_pipeline
    if _v3_pipeline is None:
        _v3_pipeline = V3Pipeline()
        await _v3_pipeline.initialize()
    return _v3_pipeline
