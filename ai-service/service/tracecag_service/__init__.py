"""Portable TRACE-CAG service package.

The package is intentionally additive. Importing it does not import the
existing FastAPI app or `api.services.trace_cag`; use the LexiLingo adapter
when you want to bind this contract to the current application pipeline.
"""

from service.tracecag_service.config import TraceCAGServiceConfig
from service.tracecag_service.runtime import TraceCAGService
from service.tracecag_service.schemas import TraceCAGRequest, TraceCAGResponse

__all__ = [
    "TraceCAGRequest",
    "TraceCAGResponse",
    "TraceCAGService",
    "TraceCAGServiceConfig",
]

