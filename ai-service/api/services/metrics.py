"""
Execution Metrics Tracker

Tracks performance metrics for AI pipeline:
- Latency per component
- Cache hit rates
- Error rates
- Resource usage
"""

import logging
from typing import Dict, List, Any, Optional
from datetime import datetime, timedelta
from collections import defaultdict
import statistics

logger = logging.getLogger(__name__)


class ExecutionMetrics:
    """
    Track performance metrics cho AI Orchestrator.
    
    Metrics tracked:
    - Request counts và latency
    - Cache hit rates
    - Error rates và types
    - Component-level performance
    """
    
    def __init__(self, history_limit: int = 1000):
        """
        Initialize metrics tracker.
        
        Args:
            history_limit: Max number of records to keep in memory
        """
        self.history_limit = history_limit
        
        # Overall metrics
        self.total_requests = 0
        self.cache_hits = 0
        self.total_errors = 0
        
        # Latency tracking
        self.latencies: List[float] = []  # in milliseconds
        
        # Component-level metrics
        self.component_latencies: Dict[str, List[float]] = defaultdict(list)
        self.component_errors: Dict[str, int] = defaultdict(int)
        
        # Error tracking
        self.error_types: Dict[str, int] = defaultdict(int)
        
        # Model usage tracking
        self.model_usage: Dict[str, int] = defaultdict(int)
        
        # Time-based metrics
        self.start_time = datetime.utcnow()
        self.hourly_requests: Dict[str, int] = defaultdict(int)
        
        logger.info("ExecutionMetrics initialized")
    
    def record_request(
        self,
        latency_ms: float,
        models_used: List[str],
        success: bool = True,
        cached: bool = False
    ):
        """
        Record a request.
        
        Args:
            latency_ms: Total latency in milliseconds
            models_used: List of models used in this request
            success: Whether request succeeded
            cached: Whether response was from cache
        """
        self.total_requests += 1
        
        # Record cache hit
        if cached:
            self.cache_hits += 1
        
        # Record latency
        if success and not cached:
            self.latencies.append(latency_ms)
            self._trim_history(self.latencies)
        
        # Record model usage
        for model in models_used:
            self.model_usage[model] += 1
        
        # Record hourly request
        hour_key = datetime.utcnow().strftime("%Y-%m-%d %H:00")
        self.hourly_requests[hour_key] += 1
        
        logger.debug(
            f"Request recorded: {latency_ms:.1f}ms, "
            f"models={models_used}, cached={cached}"
        )
    
    def record_cache_hit(self):
        """Record a cache hit."""
        self.cache_hits += 1
    
    def record_error(self, error_type: str, component: Optional[str] = None):
        """
        Record an error.
        
        Args:
            error_type: Type of error (e.g., "timeout", "model_failure")
            component: Component that failed (e.g., "qwen", "hubert")
        """
        self.total_errors += 1
        self.error_types[error_type] += 1
        
        if component:
            self.component_errors[component] += 1
        
        logger.warning(f"Error recorded: {error_type} in {component}")
    
    def record_component_latency(self, component: str, latency_ms: float):
        """
        Record latency for specific component.
        
        Args:
            component: Component name (e.g., "qwen", "hubert", "stt")
            latency_ms: Latency in milliseconds
        """
        self.component_latencies[component].append(latency_ms)
        self._trim_history(self.component_latencies[component])
    
    def get_stats(self) -> Dict[str, Any]:
        """
        Get aggregated statistics.
        
        Returns:
            Dict with all metrics
        """
        uptime = (datetime.utcnow() - self.start_time).total_seconds()
        
        return {
            "overview": {
                "total_requests": self.total_requests,
                "total_errors": self.total_errors,
                "cache_hits": self.cache_hits,
                "uptime_seconds": int(uptime),
                "requests_per_minute": self._calculate_rpm()
            },
            "success_rate": {
                "success_count": self.total_requests - self.total_errors,
                "error_count": self.total_errors,
                "success_rate_percent": self._calculate_success_rate()
            },
            "cache": {
                "hit_count": self.cache_hits,
                "total_cacheable": self.total_requests,
                "hit_rate_percent": self._calculate_cache_hit_rate()
            },
            "latency": self._get_latency_stats(),
            "components": self._get_component_stats(),
            "errors": {
                "by_type": dict(self.error_types),
                "by_component": dict(self.component_errors)
            },
            "models": {
                "usage_count": dict(self.model_usage),
                "most_used": self._get_most_used_model()
            }
        }
    
    def _get_latency_stats(self) -> Dict[str, float]:
        """Calculate latency statistics."""
        if not self.latencies:
            return {
                "avg_ms": 0.0,
                "min_ms": 0.0,
                "max_ms": 0.0,
                "p50_ms": 0.0,
                "p95_ms": 0.0,
                "p99_ms": 0.0
            }
        
        sorted_latencies = sorted(self.latencies)
        
        return {
            "avg_ms": round(statistics.mean(self.latencies), 2),
            "min_ms": round(min(self.latencies), 2),
            "max_ms": round(max(self.latencies), 2),
            "p50_ms": round(self._percentile(sorted_latencies, 0.50), 2),
            "p95_ms": round(self._percentile(sorted_latencies, 0.95), 2),
            "p99_ms": round(self._percentile(sorted_latencies, 0.99), 2)
        }
    
    def _get_component_stats(self) -> Dict[str, Dict[str, float]]:
        """Get per-component statistics."""
        stats = {}
        
        for component, latencies in self.component_latencies.items():
            if not latencies:
                continue
            
            stats[component] = {
                "avg_ms": round(statistics.mean(latencies), 2),
                "p95_ms": round(self._percentile(sorted(latencies), 0.95), 2),
                "error_count": self.component_errors.get(component, 0)
            }
        
        return stats
    
    def _calculate_success_rate(self) -> float:
        """Calculate success rate percentage."""
        if self.total_requests == 0:
            return 100.0
        
        success_count = self.total_requests - self.total_errors
        return round((success_count / self.total_requests) * 100, 2)
    
    def _calculate_cache_hit_rate(self) -> float:
        """Calculate cache hit rate percentage."""
        if self.total_requests == 0:
            return 0.0
        
        return round((self.cache_hits / self.total_requests) * 100, 2)
    
    def _calculate_rpm(self) -> float:
        """Calculate requests per minute."""
        uptime_minutes = (datetime.utcnow() - self.start_time).total_seconds() / 60
        if uptime_minutes == 0:
            return 0.0
        
        return round(self.total_requests / uptime_minutes, 2)
    
    def _get_most_used_model(self) -> Optional[str]:
        """Get most frequently used model."""
        if not self.model_usage:
            return None
        
        return max(self.model_usage.items(), key=lambda x: x[1])[0]
    
    def _percentile(self, data: List[float], p: float) -> float:
        """
        Calculate percentile.
        
        Args:
            data: Sorted list of values
            p: Percentile (0.0 to 1.0)
            
        Returns:
            Percentile value
        """
        if not data:
            return 0.0
        
        index = int(len(data) * p)
        index = min(index, len(data) - 1)
        
        return data[index]
    
    def _trim_history(self, history: List[float]):
        """Trim history to keep memory bounded."""
        if len(history) > self.history_limit:
            # Keep only most recent entries
            del history[:-self.history_limit]
    
    def get_summary_text(self) -> str:
        """Get human-readable summary."""
        stats = self.get_stats()
        
        return f"""
Performance Metrics Summary:
---------------------------
Total Requests: {stats['overview']['total_requests']}
Success Rate: {stats['success_rate']['success_rate_percent']}%
Cache Hit Rate: {stats['cache']['hit_rate_percent']}%
Avg Latency: {stats['latency']['avg_ms']}ms
P95 Latency: {stats['latency']['p95_ms']}ms
Errors: {stats['overview']['total_errors']}
Uptime: {stats['overview']['uptime_seconds']}s
        """.strip()
    
    def reset(self):
        """Reset all metrics (for testing)."""
        self.total_requests = 0
        self.cache_hits = 0
        self.total_errors = 0
        self.latencies.clear()
        self.component_latencies.clear()
        self.component_errors.clear()
        self.error_types.clear()
        self.model_usage.clear()
        self.hourly_requests.clear()
        self.start_time = datetime.utcnow()
        
        logger.info("Metrics reset")


# Singleton instance
_metrics: Optional[ExecutionMetrics] = None


def get_metrics() -> ExecutionMetrics:
    """
    Get ExecutionMetrics singleton.
    
    Returns:
        ExecutionMetrics instance
    """
    global _metrics
    
    if _metrics is None:
        _metrics = ExecutionMetrics()
    
    return _metrics
