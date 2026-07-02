"""Lazy adapter from the portable service contract to this app's pipeline."""

from __future__ import annotations

import inspect
from typing import Any, Awaitable, Callable

from service.tracecag_service.config import TraceCAGServiceConfig
from service.tracecag_service.runtime import TraceCAGService
from service.tracecag_service.schemas import TraceCAGRequest, TraceCAGResponse


PipelineFactory = Callable[[], Any | Awaitable[Any]]


class LexiLingoTraceCAGAnalyzer:
    """Adapter for the existing `api.services.trace_cag` implementation.

    The import is intentionally lazy so the portable package can be imported in
    another project without importing FastAPI, Redis, KG, or model code.
    """

    def __init__(self, pipeline_factory: PipelineFactory | None = None) -> None:
        self._pipeline_factory = pipeline_factory
        self._pipeline: Any | None = None

    async def analyze(self, request: TraceCAGRequest) -> TraceCAGResponse:
        pipeline = await self._get_pipeline()
        result = await pipeline.analyze(**request.to_pipeline_kwargs())
        return TraceCAGResponse.from_mapping(
            result,
            raw_state=result if request.return_raw_state and isinstance(result, dict) else None,
        )

    async def _get_pipeline(self) -> Any:
        if self._pipeline is not None:
            return self._pipeline

        if self._pipeline_factory is not None:
            candidate = self._pipeline_factory()
            self._pipeline = await candidate if inspect.isawaitable(candidate) else candidate
            return self._pipeline

        from api.services.trace_cag.graph import get_trace_cag

        self._pipeline = await get_trace_cag()
        return self._pipeline


def create_lexilingo_service(
    *,
    config: TraceCAGServiceConfig | None = None,
    pipeline_factory: PipelineFactory | None = None,
) -> TraceCAGService:
    """Create a portable service bound to the current LexiLingo pipeline."""

    return TraceCAGService(
        analyzer=LexiLingoTraceCAGAnalyzer(pipeline_factory=pipeline_factory),
        config=config,
    )
