"""Services package initialization."""

try:
    from api.services.context_manager import ContextManager, PromptBuilder
except ImportError:
    ContextManager = None  # type: ignore
    PromptBuilder = None  # type: ignore

try:
    from api.services.metrics import ExecutionMetrics, get_metrics
except ImportError:
    ExecutionMetrics = None  # type: ignore
    get_metrics = None  # type: ignore

# TraceCAG pipeline (requires langgraph)
try:
    from api.services.trace_cag import TraceCAGPipeline, get_trace_cag
except ImportError:
    TraceCAGPipeline = None  # type: ignore
    get_trace_cag = None  # type: ignore

try:
    from api.services.hubert_service import HuBERTService, get_hubert_service
except ImportError:
    HuBERTService = None  # type: ignore
    get_hubert_service = None  # type: ignore

__all__ = [
    "ContextManager",
    "PromptBuilder",
    "ExecutionMetrics",
    "get_metrics",
    "TraceCAGPipeline",
    "get_trace_cag",
    "HuBERTService",
    "get_hubert_service",
]
