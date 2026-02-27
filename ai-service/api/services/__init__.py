"""
Services package initialization

Export all service classes
"""

try:
    from api.services.context_manager import ContextManager, PromptBuilder
except ImportError:
    ContextManager = None  # type: ignore
    PromptBuilder = None  # type: ignore

try:
    from api.services.dl_model_service import DLModelService, get_dl_model_service
except ImportError:
    DLModelService = None  # type: ignore
    get_dl_model_service = None  # type: ignore

try:
    from api.services.resource_manager import ResourceManager, get_resource_manager
except ImportError:
    ResourceManager = None  # type: ignore
    get_resource_manager = None  # type: ignore

try:
    from api.services.metrics import ExecutionMetrics, get_metrics
except ImportError:
    ExecutionMetrics = None  # type: ignore
    get_metrics = None  # type: ignore

# New GraphCAG pipeline (replaces AIOrchestrator) - requires langgraph
try:
    from api.services.graph_cag import GraphCAGPipeline, get_graph_cag
except ImportError:
    GraphCAGPipeline = None  # type: ignore
    get_graph_cag = None  # type: ignore

# New AI services - require optional heavy deps (numpy, torch, etc.)
try:
    from api.services.hubert_service import HuBERTService, get_hubert_service
except ImportError:
    HuBERTService = None  # type: ignore
    get_hubert_service = None  # type: ignore

try:
    from api.services.llama_vietnamese_service import LLaMAVietnameseService, get_llama_vietnamese_service
except ImportError:
    LLaMAVietnameseService = None  # type: ignore
    get_llama_vietnamese_service = None  # type: ignore

try:
    from api.services.qwen_engine import QwenEngine, get_qwen_engine
except ImportError:
    QwenEngine = None  # type: ignore
    get_qwen_engine = None  # type: ignore

__all__ = [
    "ContextManager",
    "PromptBuilder",
    "DLModelService",
    "get_dl_model_service",
    "ResourceManager",
    "get_resource_manager",
    "ExecutionMetrics",
    "get_metrics",
    # New GraphCAG
    "GraphCAGPipeline",
    "get_graph_cag",
    # AI Services
    "HuBERTService",
    "get_hubert_service",
    "LLaMAVietnameseService",
    "get_llama_vietnamese_service",
    "QwenEngine",
    "get_qwen_engine",
]
