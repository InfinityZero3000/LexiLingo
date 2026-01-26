"""
Optimization Configuration

Centralized configuration for performance optimization settings.
"""

from pydantic import BaseModel, Field
from typing import Optional


class OptimizationConfig(BaseModel):
    """
    Configuration for performance optimization.
    
    Controls caching, timeouts, memory management, and monitoring behavior.
    """
    
    # ============================================================
    # CACHE SETTINGS
    # ============================================================
    
    enable_response_cache: bool = Field(
        True,
        description="Enable response caching for faster repeated queries"
    )
    
    cache_ttl_seconds: int = Field(
        604800,  # 7 days
        description="Time-to-live for cached responses in seconds"
    )
    
    # ============================================================
    # TIMEOUT SETTINGS
    # ============================================================
    
    qwen_timeout_ms: int = Field(
        500,
        description="Qwen inference timeout in milliseconds"
    )
    
    llama_timeout_ms: int = Field(
        500,
        description="LLaMA3-VI inference timeout in milliseconds"
    )
    
    hubert_timeout_ms: int = Field(
        300,
        description="HuBERT pronunciation analysis timeout (non-critical)"
    )
    
    # ============================================================
    # MEMORY MANAGEMENT
    # ============================================================
    
    max_memory_gb: float = Field(
        8.0,
        description="Maximum memory budget in GB"
    )
    
    enable_auto_memory_management: bool = Field(
        True,
        description="Automatically unload low-priority models when memory is low"
    )
    
    memory_warning_threshold_percent: float = Field(
        85.0,
        description="Warn when system memory usage exceeds this percentage"
    )
    
    # ============================================================
    # PERFORMANCE TARGETS
    # ============================================================
    
    target_latency_ms: int = Field(
        350,
        description="Target P95 latency in milliseconds"
    )
    
    target_cache_hit_rate: float = Field(
        0.4,
        description="Target cache hit rate (0.0 to 1.0)"
    )
    
    target_error_rate: float = Field(
        0.01,
        description="Target error rate (0.0 to 1.0)"
    )
    
    # ============================================================
    # LOGGING
    # ============================================================
    
    log_level: str = Field(
        "INFO",
        description="Logging level: DEBUG, INFO, WARNING, ERROR, CRITICAL"
    )
    
    enable_structured_logging: bool = Field(
        True,
        description="Use JSON structured logging format"
    )
    
    enable_performance_logging: bool = Field(
        True,
        description="Log detailed performance metrics"
    )
    
    log_file: Optional[str] = Field(
        None,
        description="Optional path to log file"
    )
    
    # ============================================================
    # MONITORING & TELEMETRY
    # ============================================================
    
    enable_telemetry: bool = Field(
        True,
        description="Enable telemetry and metrics collection"
    )
    
    telemetry_retention_minutes: int = Field(
        60,
        description="How long to keep metrics in memory (minutes)"
    )
    
    enable_health_checks: bool = Field(
        True,
        description="Enable periodic system health checks"
    )
    
    # ============================================================
    # CONCURRENCY
    # ============================================================
    
    max_concurrent_requests: int = Field(
        10,
        description="Maximum number of concurrent requests to process"
    )
    
    enable_request_queuing: bool = Field(
        True,
        description="Queue requests when limit is reached (vs reject immediately)"
    )
    
    class Config:
        """Pydantic config."""
        json_schema_extra = {
            "example": {
                "enable_response_cache": True,
                "cache_ttl_seconds": 604800,
                "qwen_timeout_ms": 500,
                "max_memory_gb": 8.0,
                "target_latency_ms": 350,
                "log_level": "INFO",
                "enable_telemetry": True
            }
        }


# Default configuration instance
default_config = OptimizationConfig()


def get_optimization_config() -> OptimizationConfig:
    """
    Get optimization configuration.
    
    Can be extended to load from environment variables or config file.
    
    Returns:
        OptimizationConfig instance
    """
    # TODO: Load from environment or config file
    return default_config
