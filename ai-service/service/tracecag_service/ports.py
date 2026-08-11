"""Ports that decouple the service package from any one application."""

from __future__ import annotations

from typing import Any, Mapping, Protocol, runtime_checkable

from service.tracecag_service.schemas import TraceCAGRequest, TraceCAGResponse


@runtime_checkable
class TraceCAGAnalyzer(Protocol):
    """Analyzer contract implemented by real pipelines or test adapters."""

    async def analyze(
        self,
        request: TraceCAGRequest,
    ) -> TraceCAGResponse | Mapping[str, Any]:
        """Analyze a request and return either a normalized response or mapping."""


class SupportsClose(Protocol):
    """Optional async close hook used by adapters with external resources."""

    async def close(self) -> None:
        """Release adapter resources."""
