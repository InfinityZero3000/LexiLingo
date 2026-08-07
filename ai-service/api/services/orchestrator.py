"""
AI Orchestrator Service

Real lifecycle manager for the TraceCAG pipeline and all sub-services.

Responsibilities:
  - Coordinate initialization order: KG → ModelGateway → TraceCAGPipeline
  - Expose process() as the single public entry point (delegates to pipeline)
  - Aggregate cumulative request stats (latency, cache hit rate, model usage)
  - Surface health across all sub-services
"""

import asyncio
import fcntl
import logging
import os
from datetime import datetime
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)
_kuzu_process_lock_file = None


def _get_kg_service_with_process_lock():
    """Own the shared Kuzu snapshot lock for this process lifetime."""
    global _kuzu_process_lock_file
    from api.core.config import settings
    from api.services.kg_service_v3 import get_kg_service

    lock_path = f"{os.path.abspath(settings.KUZU_DB_PATH)}.init.lock"
    os.makedirs(os.path.dirname(lock_path), exist_ok=True)
    if _kuzu_process_lock_file is None:
        lock_file = open(lock_path, "a", encoding="utf-8")
        try:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            lock_file.close()
            raise RuntimeError(
                "Kuzu snapshot is already owned; use one worker or a separate KUZU_DB_PATH"
            ) from exc
        _kuzu_process_lock_file = lock_file
    try:
        return get_kg_service()
    except BaseException:
        _release_kg_process_lock()
        raise


def _release_kg_process_lock() -> None:
    global _kuzu_process_lock_file
    if _kuzu_process_lock_file is not None:
        fcntl.flock(_kuzu_process_lock_file.fileno(), fcntl.LOCK_UN)
        _kuzu_process_lock_file.close()
        _kuzu_process_lock_file = None


class AIOrchestrator:
    """
    Lifecycle coordinator for the TraceCAG multi-agent pipeline.

    Init order (enforced in initialize()):
      1. KnowledgeGraphServiceV3   — KuzuDB schema + concept seeding
      2. ModelGateway              — lazy model registry + auto-unload scheduler
      3. TraceCAGPipeline          — LangGraph StateGraph compile
      4. RetrievalServiceV3        — graph analytics + concept embeddings
                                      (backgrounded — see initialize())

    All are singletons managed by their own modules; the Orchestrator holds
    references for health aggregation only (no ownership).
    """

    _instance: Optional["AIOrchestrator"] = None

    def __init__(self):
        self.start_time = datetime.now()
        self._initialized = False
        self._pipeline = None   # TraceCAGPipeline
        self._gateway = None    # ModelGateway
        self._kg = None         # KnowledgeGraphServiceV3
        self._retrieval_warmup_task: Optional[asyncio.Task] = None

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
            # Kuzu opens files, validates schema and may seed/rebuild the graph.
            # Those operations are synchronous and can take seconds on a cold
            # start; never run them on the ASGI event loop.
            self._kg = await asyncio.to_thread(_get_kg_service_with_process_lock)
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

        # 4. RetrievalServiceV3 (graph analytics + concept embeddings) and the
        # JIT GLiNER entity-extraction model — retrieve_node's other two lazy
        # singletons. Measured on the real production KG: RetrievalServiceV3's
        # constructor alone takes 170-480s (NetworkX centrality + embedding-
        # model cold load + ~15K concept embeddings), and GLiNER's cold load
        # adds another ~15s — neither runs during boot today, so retrieve_node
        # builds them lazily on whichever request hits it first, and that
        # user pays the full cost inline.
        #
        # Fired as a background task, NOT awaited: awaiting it here would
        # make this whole method (and the `asyncio.wait_for(..., timeout=45)`
        # in main.py's lifespan that calls it) take minutes, blowing past the
        # Docker HEALTHCHECK start-period (60s) and risking the container
        # being killed before it ever finishes warming. A live request that
        # arrives before this finishes still only pays each cost once — both
        # singletons already have their own lock (_get_retrieval_v3's lock;
        # JITGraphService._model_lock) that makes a racing request await the
        # same in-flight build instead of starting a duplicate.
        self._retrieval_warmup_task = asyncio.create_task(self._warm_retrieval_stack())
        self._retrieval_warmup_task.add_done_callback(self._log_retrieval_warmup)

        self._initialized = True
        logger.info("AIOrchestrator ready (kg + gateway + trace-cag; retrieval stack warming in background)")

    @staticmethod
    async def _warm_retrieval_stack() -> None:
        from api.services.trace_cag.retrieve import _get_retrieval_v3

        await _get_retrieval_v3()

        from api.services.jit_graph_service import get_jit_graph_service

        jit_cfg = get_jit_graph_service()._load_config()
        if jit_cfg.enabled:
            await get_jit_graph_service()._ensure_gliner_model(jit_cfg.model_name)

    @staticmethod
    def _log_retrieval_warmup(task: asyncio.Task) -> None:
        if task.cancelled():
            return
        exc = task.exception()
        if exc:
            logger.warning(f"AIOrchestrator: retrieval-stack background warmup failed: {exc}")
        else:
            logger.info(
                "AIOrchestrator: retrieval stack (graph analytics + embeddings + GLiNER) warmed"
            )

    async def shutdown(self) -> None:
        """Gracefully release resources."""
        if self._gateway and hasattr(self._gateway, "shutdown"):
            try:
                await self._gateway.shutdown()
            except Exception as e:
                logger.warning(f"AIOrchestrator: gateway shutdown error: {e}")

        self._initialized = False
        _release_kg_process_lock()
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
_orchestrator_lock = asyncio.Lock()
_orchestrator_init_task: Optional[asyncio.Task[AIOrchestrator]] = None


async def _initialize_orchestrator() -> AIOrchestrator:
    global _orchestrator
    candidate = AIOrchestrator()
    await candidate.initialize()
    _orchestrator = candidate
    return candidate


async def get_orchestrator() -> AIOrchestrator:
    """Get or create the global orchestrator instance (auto-initialises)."""
    global _orchestrator_init_task
    if _orchestrator is None:
        async with _orchestrator_lock:
            if _orchestrator is None and (
                _orchestrator_init_task is None or _orchestrator_init_task.done()
            ):
                _orchestrator_init_task = asyncio.create_task(
                    _initialize_orchestrator()
                )
        if _orchestrator is None:
            await asyncio.shield(_orchestrator_init_task)
    return _orchestrator
