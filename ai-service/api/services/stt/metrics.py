"""Small in-process STT metrics adapter."""

from collections import Counter, defaultdict, deque
from threading import Lock

_LATENCY_WINDOW = 200


class STTMetrics:
    def __init__(self):
        self._counter = Counter()
        self._latencies: dict[str, deque[float]] = defaultdict(
            lambda: deque(maxlen=_LATENCY_WINDOW)
        )
        self._lock = Lock()

    def increment(self, name: str, value: int = 1) -> None:
        with self._lock:
            self._counter[name] += value

    def record_latency(self, name: str, value: float) -> None:
        with self._lock:
            self._latencies[name].append(value)

    def latency_stats(self, name: str) -> dict[str, float]:
        with self._lock:
            samples = list(self._latencies.get(name, []))
        if not samples:
            return {"count": 0, "min": 0.0, "max": 0.0, "avg": 0.0, "p95": 0.0}
        samples.sort()
        count = len(samples)
        p95_idx = max(0, int(count * 0.95) - 1)
        return {
            "count": count,
            "min": samples[0],
            "max": samples[-1],
            "avg": sum(samples) / count,
            "p95": samples[p95_idx],
        }

    def snapshot(self) -> dict[str, int]:
        with self._lock:
            return dict(self._counter)

    def all_latency_stats(self) -> dict[str, dict[str, float]]:
        with self._lock:
            names = list(self._latencies.keys())
        return {name: self.latency_stats(name) for name in names}
