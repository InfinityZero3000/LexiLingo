"""Public runtime wrapper for portable TRACE-CAG analyzers."""

from __future__ import annotations

import asyncio
from collections.abc import Iterable
from typing import Any

from service.tracecag_service.config import TraceCAGServiceConfig
from service.tracecag_service.ports import TraceCAGAnalyzer
from service.tracecag_service.schemas import TraceCAGRequest, TraceCAGResponse


class TraceCAGService:
    """Small stable facade around a pluggable TRACE-CAG analyzer."""

    def __init__(
        self,
        analyzer: TraceCAGAnalyzer,
        config: TraceCAGServiceConfig | None = None,
    ) -> None:
        self.analyzer = analyzer
        self.config = config or TraceCAGServiceConfig()

    async def analyze(
        self,
        request: TraceCAGRequest,
    ) -> TraceCAGResponse:
        """Run one analysis call with validation, timeout, and normalization."""

        validation_error = self._validate(request)
        if validation_error:
            return self._error_response(request, validation_error, error_type="validation")

        try:
            result = await asyncio.wait_for(
                self.analyzer.analyze(request),
                timeout=self.config.timeout_seconds,
            )
            response = TraceCAGResponse.from_mapping(result)
            self._stamp_metadata(response, request)
            if self.config.include_raw_state_by_default and response.raw_state is None:
                response.raw_state = response.extra.pop("raw_state", None)
            return response
        except asyncio.TimeoutError:
            return self._error_response(request, "TRACE-CAG service timed out", error_type="timeout")
        except Exception as exc:
            return self._error_response(request, str(exc), error_type="runtime")

    async def analyze_text(
        self,
        text: str,
        *,
        session_id: str | None = None,
        **kwargs: Any,
    ) -> TraceCAGResponse:
        """Convenience entry point for simple text-only integrations."""

        request = TraceCAGRequest.from_text(
            text,
            session_id=session_id or self.config.default_session_id,
            **kwargs,
        )
        return await self.analyze(request)

    async def analyze_many(
        self,
        requests: Iterable[TraceCAGRequest],
    ) -> list[TraceCAGResponse]:
        """Analyze multiple requests with bounded concurrency."""

        semaphore = asyncio.Semaphore(max(1, self.config.max_concurrency))

        async def _run(item: TraceCAGRequest) -> TraceCAGResponse:
            async with semaphore:
                return await self.analyze(item)

        return await asyncio.gather(*[_run(request) for request in requests])

    async def close(self) -> None:
        """Close the adapter when it provides an async close hook."""

        close = getattr(self.analyzer, "close", None)
        if close is not None:
            await close()

    def _validate(self, request: TraceCAGRequest) -> str | None:
        if not self.config.strict_validation:
            return None
        if not request.user_input or not request.user_input.strip():
            return "user_input is required"
        if not request.session_id or not request.session_id.strip():
            return "session_id is required"
        if request.input_type not in {"text", "voice"}:
            return "input_type must be 'text' or 'voice'"
        if request.cache_policy not in {"on", "off"}:
            return "cache_policy must be 'on' or 'off'"
        return None

    def _stamp_metadata(
        self,
        response: TraceCAGResponse,
        request: TraceCAGRequest,
    ) -> None:
        response.metadata = {
            **response.metadata,
            "service": {
                "name": self.config.service_name,
                "version": self.config.version,
                "adapter": type(self.analyzer).__name__,
            },
            "request": {
                "session_id": request.session_id,
                "input_type": request.input_type,
            },
        }

    def _error_response(
        self,
        request: TraceCAGRequest,
        message: str,
        *,
        error_type: str,
    ) -> TraceCAGResponse:
        response = TraceCAGResponse(
            tutor_response="",
            error=message,
            metadata={
                "path": "error",
                "cache_hit": False,
                "cache_decision": "full",
                "cache_layer": "none",
                "error_type": error_type,
            },
        )
        self._stamp_metadata(response, request)
        return response

