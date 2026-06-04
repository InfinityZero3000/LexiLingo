"""
AI Orchestrator Service

Real lifecycle manager for the TraceCAG pipeline and all sub-services.

Responsibilities:
  - Coordinate initialization order: KG → ModelGateway → TraceCAGPipeline
  - Expose process() as the single public entry point (delegates to pipeline)
  - Aggregate cumulative request stats (latency, cache hit rate, model usage)
  - Surface health across all sub-services
"""

import logging
from datetime import datetime
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


class AIOrchestrator:
    """
    Lifecycle coordinator for the TraceCAG multi-agent pipeline.

    Init order (enforced in initialize()):
      1. KnowledgeGraphServiceV3   — KuzuDB schema + concept seeding
      2. ModelGateway              — lazy model registry + auto-unload scheduler
      3. TraceCAGPipeline          — LangGraph StateGraph compile

    All three are singletons managed by their own modules; the Orchestrator
    holds references for health aggregation only (no ownership).
    """

    _instance: Optional["AIOrchestrator"] = None

    def __init__(self):
        self.start_time = datetime.now()
        self._initialized = False
        self._pipeline = None   # TraceCAGPipeline
        self._gateway = None    # ModelGateway
        self._kg = None         # KnowledgeGraphServiceV3

        # Cumulative stats
        self._total_requests: int = 0
        self._total_latency_ms: int = 0
        self._cache_hits: int = 0
        self._error_count: int = 0

        logger.info("AIOrchestrator created")

    @classmethod
    def get_instance(cls) -> "AIOrchestrator":
        if cls._instance is None:
            cls._instance = AIOrchestrator()
        return cls._instance

    # ── Lifecycle ────────────────────────────────────────────────────────────

    async def initialize(self) -> None:
        """
        Initialize all sub-services in dependency order.
        Safe to call multiple times (idempotent).
        """
        if self._initialized:
            return

        # 1. Knowledge Graph (cheap, synchronous schema setup)
        try:
            from api.services.kg_service_v3 import get_kg_service
            self._kg = get_kg_service()
            logger.info("AIOrchestrator: KG service ready")
        except Exception as e:
            logger.warning(f"AIOrchestrator: KG service unavailable: {e}")

        # 2. ModelGateway (registers handlers, starts auto-unload scheduler)
        try:
            from api.services.model_gateway import get_gateway
            self._gateway = await get_gateway()
            logger.info("AIOrchestrator: ModelGateway ready")
        except Exception as e:
            logger.warning(f"AIOrchestrator: ModelGateway unavailable: {e}")

        # 3. TraceCAGPipeline (compiles LangGraph StateGraph)
        try:
            from api.services.trace_cag.graph import get_trace_cag
            self._pipeline = await get_trace_cag()
            logger.info("AIOrchestrator: TraceCAG pipeline compiled")
        except Exception as e:
            logger.error(f"AIOrchestrator: TraceCAG pipeline failed: {e}")
            raise

        self._initialized = True
        logger.info("AIOrchestrator ready (kg + gateway + trace-cag)")

    async def shutdown(self) -> None:
        """Gracefully release resources."""
        if self._gateway and hasattr(self._gateway, "shutdown"):
            try:
                await self._gateway.shutdown()
            except Exception as e:
                logger.warning(f"AIOrchestrator: gateway shutdown error: {e}")

        self._initialized = False
        logger.info("AIOrchestrator shutdown")

    @property
    def pipeline(self):
        """Direct access to the TraceCAGPipeline (used by the streaming endpoint)."""
        return self._pipeline

    # ── Public entry point ───────────────────────────────────────────────────

    async def process(
        self,
        user_input: str,
        session_id: str,
        conversation_history: Optional[List[Dict[str, Any]]] = None,
        **kwargs: Any,
    ) -> Dict[str, Any]:
        """
        Single public entry point — delegates to TraceCAGPipeline.analyze().

        Updates cumulative stats after each request.

        Args:
            user_input: Raw text (or transcription key) from the user.
            session_id: Unique session identifier.
            conversation_history: Pre-loaded history list (skips Redis fetch).
            **kwargs: Forwarded to pipeline.analyze() (learner_profile, policies…).

        Returns:
            Formatted TraceCAG response dict.
        """
        if not self._initialized:
            await self.initialize()

        try:
            result = await self._pipeline.analyze(
                user_input=user_input,
                session_id=session_id,
                conversation_history=conversation_history,
                **kwargs,
            )
            self._total_requests += 1
            latency = result.get("metadata", {}).get("latency_ms", 0)
            self._total_latency_ms += latency
            if result.get("metadata", {}).get("cache_hit"):
                self._cache_hits += 1
            return result

        except Exception as e:
            self._error_count += 1
            logger.error(f"AIOrchestrator.process error: {e}")
            raise

    # ── Stats & health ───────────────────────────────────────────────────────

    def get_stats(self) -> Dict[str, Any]:
        """Return cumulative operational statistics."""
        uptime = (datetime.now() - self.start_time).total_seconds()
        avg_latency = (
            self._total_latency_ms / max(self._total_requests, 1)
        )
        cache_rate = self._cache_hits / max(self._total_requests, 1)

        return {
            "uptime_seconds": round(uptime, 1),
            "initialized": self._initialized,
            "total_requests": self._total_requests,
            "avg_latency_ms": round(avg_latency, 1),
            "cache_hit_rate": round(cache_rate, 4),
            "error_count": self._error_count,
            "start_time": self.start_time.isoformat(),
            "services": {
                "kg": self._kg is not None,
                "gateway": self._gateway is not None,
                "pipeline": self._pipeline is not None,
            },
        }

    def is_healthy(self) -> bool:
        """Return True only when all critical sub-services are ready."""
        return (
            self._initialized
            and self._pipeline is not None
            and self._kg is not None
        )


# ── Module-level singleton ────────────────────────────────────────────────────

_orchestrator: Optional[AIOrchestrator] = None


async def get_orchestrator() -> AIOrchestrator:
    """Get or create the global orchestrator instance (auto-initialises)."""
    global _orchestrator
    if _orchestrator is None:
        _orchestrator = AIOrchestrator()
        await _orchestrator.initialize()
    return _orchestrator
