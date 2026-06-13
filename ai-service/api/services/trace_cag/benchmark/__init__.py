"""
Benchmark-only logic for TraceCAG.

Importing from this package in production code paths adds no overhead — all
benchmark functions are guarded by ``benchmark_task`` checks in the callers.
"""

from .adaptive import report_adaptive_benchmark_feedback, get_adaptive_controller_snapshot
from .ranking import _build_benchmark_candidates, _rank_benchmark_candidates

__all__ = [
    "report_adaptive_benchmark_feedback",
    "get_adaptive_controller_snapshot",
    "_build_benchmark_candidates",
    "_rank_benchmark_candidates",
]
