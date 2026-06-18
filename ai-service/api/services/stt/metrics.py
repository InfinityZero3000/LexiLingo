"""Small in-process STT metrics adapter."""

from collections import Counter
from threading import Lock


class STTMetrics:
    def __init__(self):
        self._counter = Counter()
        self._lock = Lock()

    def increment(self, name: str, value: int = 1) -> None:
        with self._lock:
            self._counter[name] += value

    def snapshot(self) -> dict[str, int]:
        with self._lock:
            return dict(self._counter)
