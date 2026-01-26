"""
Telemetry Service

Centralized metrics collection and monitoring for performance tracking.
Tracks request latencies, cache hit rates, error rates, and custom metrics.
"""

import time
import logging
from typing import Dict, List, Any, Optional
from collections import defaultdict, deque
from dataclasses import dataclass, field
from datetime import datetime, timedelta
import statistics

logger = logging.getLogger(__name__)


@dataclass
class PerformanceMetric:
    """Single performance metric data point."""
    name: str
    value: float
    unit: str
    timestamp: datetime
    tags: Dict[str, str] = field(default_factory=dict)


class TelemetryService:
    """
    Centralized telemetry and metrics collection.
    
    Features:
    - Time-series metrics with automatic cleanup
    - Counters for events (requests, errors, cache hits)
    - Gauges for current values (memory usage, active connections)
    - Histograms for distribution analysis
    - Performance target checking
    
    Usage:
        telemetry = get_telemetry()
        telemetry.record_metric("request_latency_ms", 250)
        telemetry.increment_counter("total_requests")
        telemetry.set_gauge("active_models", 3)
    """
    
    def __init__(self, retention_minutes: int = 60):
        """
        Initialize telemetry service.
        
        Args:
            retention_minutes: How long to keep metrics in memory
        """
        self.retention_minutes = retention_minutes
        
        # Time-series data (recent metrics with timestamps)
        self.metrics: Dict[str, deque] = defaultdict(lambda: deque(maxlen=1000))
        
        # Counters (monotonically increasing)
        self.counters: Dict[str, int] = defaultdict(int)
        
        # Gauges (current snapshot values)
        self.gauges: Dict[str, float] = {}
        
        # Histogram data (for percentile calculations)
        self.histograms: Dict[str, List[float]] = defaultdict(list)
        
        logger.info(f"Telemetry service initialized with {retention_minutes}min retention")
    
    def record_metric(
        self,
        name: str,
        value: float,
        unit: str = "ms",
        tags: Optional[Dict[str, str]] = None
    ):
        """
        Record a metric value.
        
        Args:
            name: Metric name (e.g., "request_latency_ms")
            value: Numeric value
            unit: Unit of measurement (e.g., "ms", "bytes", "count")
            tags: Optional tags for metric (e.g., {"model": "qwen", "endpoint": "analyze"})
        """
        metric = PerformanceMetric(
            name=name,
            value=value,
            unit=unit,
            timestamp=datetime.utcnow(),
            tags=tags or {}
        )
        
        self.metrics[name].append(metric)
        self.histograms[name].append(value)
        
        # Cleanup old metrics
        self._cleanup_old_metrics(name)
        
        logger.debug(f"Recorded metric: {name}={value}{unit}")
    
    def increment_counter(self, name: str, value: int = 1):
        """
        Increment a counter.
        
        Args:
            name: Counter name
            value: Amount to increment by
        """
        self.counters[name] += value
        logger.debug(f"Incremented counter: {name} += {value} (total: {self.counters[name]})")
    
    def set_gauge(self, name: str, value: float):
        """
        Set a gauge value (current snapshot).
        
        Args:
            name: Gauge name
            value: Current value
        """
        self.gauges[name] = value
        logger.debug(f"Set gauge: {name}={value}")
    
    def get_statistics(self, metric_name: str) -> Dict[str, float]:
        """
        Get statistical summary for a metric.
        
        Args:
            metric_name: Name of metric
            
        Returns:
            Dict with min, max, mean, median, p95, p99
        """
        values = self.histograms.get(metric_name, [])
        
        if not values:
            return {}
        
        sorted_values = sorted(values)
        
        return {
            "count": len(values),
            "min": min(values),
            "max": max(values),
            "mean": round(statistics.mean(values), 2),
            "median": round(statistics.median(values), 2),
            "p50": round(self._percentile(sorted_values, 0.50), 2),
            "p95": round(self._percentile(sorted_values, 0.95), 2),
            "p99": round(self._percentile(sorted_values, 0.99), 2),
            "stddev": round(statistics.stdev(values), 2) if len(values) > 1 else 0.0
        }
    
    def get_dashboard_data(self) -> Dict[str, Any]:
        """
        Get comprehensive dashboard data.
        
        Returns:
            Dict with all metrics, counters, gauges, and metadata
        """
        return {
            "metrics": {
                name: self.get_statistics(name)
                for name in self.histograms.keys()
            },
            "counters": dict(self.counters),
            "gauges": dict(self.gauges),
            "performance_checks": self.check_performance_targets(),
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }
    
    def check_performance_targets(self) -> Dict[str, Any]:
        """
        Check if performance targets are being met.
        
        Returns:
            Dict with target checks and current values
        """
        checks = {}
        
        # Latency target: P95 < 350ms
        latency_stats = self.get_statistics("request_latency_ms")
        if latency_stats:
            p95_latency = latency_stats.get("p95", 0)
            checks["latency_under_350ms"] = {
                "passed": p95_latency < 350,
                "target": 350,
                "actual": p95_latency,
                "unit": "ms"
            }
        
        # Cache hit rate: >40%
        total_requests = self.counters.get("total_requests", 0)
        cache_hits = self.counters.get("cache_hits", 0)
        
        if total_requests > 0:
            hit_rate = cache_hits / total_requests
            checks["cache_hit_rate_over_40pct"] = {
                "passed": hit_rate > 0.4,
                "target": 0.4,
                "actual": round(hit_rate, 3),
                "unit": "ratio"
            }
        
        # Error rate: <1%
        errors = self.counters.get("errors", 0)
        if total_requests > 0:
            error_rate = errors / total_requests
            checks["error_rate_under_1pct"] = {
                "passed": error_rate < 0.01,
                "target": 0.01,
                "actual": round(error_rate, 4),
                "unit": "ratio"
            }
        
        return checks
    
    def get_recent_metrics(
        self,
        metric_name: str,
        minutes: int = 5
    ) -> List[PerformanceMetric]:
        """
        Get recent metric values.
        
        Args:
            metric_name: Name of metric
            minutes: How many minutes back to retrieve
            
        Returns:
            List of recent metric data points
        """
        cutoff = datetime.utcnow() - timedelta(minutes=minutes)
        metrics_queue = self.metrics.get(metric_name, deque())
        
        return [
            metric for metric in metrics_queue
            if metric.timestamp >= cutoff
        ]
    
    def _cleanup_old_metrics(self, name: str):
        """Remove metrics older than retention period."""
        cutoff = datetime.utcnow() - timedelta(minutes=self.retention_minutes)
        
        metrics_queue = self.metrics[name]
        while metrics_queue and metrics_queue[0].timestamp < cutoff:
            metrics_queue.popleft()
    
    def _percentile(self, sorted_data: List[float], p: float) -> float:
        """
        Calculate percentile from sorted data.
        
        Args:
            sorted_data: Pre-sorted list of values
            p: Percentile (0.0 to 1.0)
            
        Returns:
            Percentile value
        """
        if not sorted_data:
            return 0.0
        
        index = int(len(sorted_data) * p)
        return sorted_data[min(index, len(sorted_data) - 1)]
    
    def reset(self):
        """Reset all metrics (useful for testing)."""
        self.metrics.clear()
        self.counters.clear()
        self.gauges.clear()
        self.histograms.clear()
        logger.info("Telemetry service reset")


# Singleton instance
_telemetry_service: Optional[TelemetryService] = None


def get_telemetry(retention_minutes: int = 60) -> TelemetryService:
    """
    Get telemetry service singleton.
    
    Args:
        retention_minutes: Metric retention time (only used on first call)
        
    Returns:
        TelemetryService instance
    """
    global _telemetry_service
    
    if _telemetry_service is None:
        _telemetry_service = TelemetryService(retention_minutes=retention_minutes)
    
    return _telemetry_service
