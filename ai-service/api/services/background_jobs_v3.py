"""V3 background jobs (skeleton).

Runs non-blocking updates after responding:
- conversation history
- learner profile updates
- KG write-backs
- optional CAG generation

Implementation note:
We schedule asyncio tasks to avoid blocking the HTTP response.
"""

from __future__ import annotations

import asyncio
import logging
from typing import Any, Dict, List, Optional

from api.core.redis_client import ConversationCache, LearnerProfileCache
from api.services.kg_service_v3 import KnowledgeGraphServiceV3

logger = logging.getLogger(__name__)


class BackgroundJobsV3:
    def __init__(
        self,
        learner_cache: Optional[LearnerProfileCache],
        conversation_cache: Optional[ConversationCache],
        kg: KnowledgeGraphServiceV3,
    ):
        self.learner_cache = learner_cache
        self.conversation_cache = conversation_cache
        self.kg = kg

    def schedule(
        self,
        *,
        user_id: str,
        session_id: str,
        user_message: str,
        ai_response: str,
        analysis: Dict[str, Any],
        linked_concepts: List[str],
        error_types: List[str],
    ) -> None:
        asyncio.create_task(
            self._run(
                user_id=user_id,
                session_id=session_id,
                user_message=user_message,
                ai_response=ai_response,
                analysis=analysis,
                linked_concepts=linked_concepts,
                error_types=error_types,
            )
        )

    async def _run(
        self,
        *,
        user_id: str,
        session_id: str,
        user_message: str,
        ai_response: str,
        analysis: Dict[str, Any],
        linked_concepts: List[str],
        error_types: List[str],
    ) -> None:
        try:
            if self.conversation_cache:
                await self.conversation_cache.add_turn(
                    session_id=session_id,
                    user_message=user_message,
                    ai_response=ai_response,
                    metadata={"v3": True, **(analysis or {})},
                )

            if self.learner_cache:
                for error_type in error_types:
                    await self.learner_cache.add_error(user_id, error_type)

            await self.kg.record_interaction(
                user_id=user_id,
                session_id=session_id,
                linked_concepts=linked_concepts,
                error_types=error_types,
            )

        except Exception as e:
            logger.warning(f"BackgroundJobsV3 failed: {e}")
