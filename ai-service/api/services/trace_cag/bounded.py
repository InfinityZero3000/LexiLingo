"""Size-bounded dict for the in-process cache indexes.

The response cache, the L1 bucket index and the dependency-token registry live in module
globals. Only the response cache had a cap, so the other two grew with every distinct
user and every cached answer until the process restarted.
"""

from __future__ import annotations

from collections import OrderedDict
from typing import Any, Callable, Hashable, Optional


class LRUDict(OrderedDict):
    """A dict that drops its least recently used items once it holds more than ``max_items``.

    Reads through ``[]``, ``get`` and ``setdefault`` refresh recency, so a hot key outlives a
    cold one. ``on_evict(key, value)`` runs for every item dropped by the cap, never for an
    explicit ``pop``, ``del`` or ``clear``, and must not touch this dict. ``can_evict(key)``
    lets a caller pin keys; if every key is pinned the dict is allowed to overshoot rather
    than lose one.
    """

    def __init__(
        self,
        max_items: int,
        *,
        on_evict: Optional[Callable[[Hashable, Any], None]] = None,
        can_evict: Optional[Callable[[Hashable], bool]] = None,
    ) -> None:
        super().__init__()
        self.max_items = max(1, int(max_items))
        self._on_evict = on_evict
        self._can_evict = can_evict

    def __setitem__(self, key: Hashable, value: Any) -> None:
        super().__setitem__(key, value)
        self.move_to_end(key)
        self._trim()

    def __getitem__(self, key: Hashable) -> Any:
        value = super().__getitem__(key)
        self.move_to_end(key)
        return value

    def get(self, key: Hashable, default: Any = None) -> Any:
        if key in self:
            return self[key]
        return default

    def setdefault(self, key: Hashable, default: Any = None) -> Any:
        if key in self:
            return self[key]
        self[key] = default
        return default

    def _trim(self) -> None:
        skipped = 0
        while len(self) > self.max_items and skipped < len(self):
            key = next(iter(self))
            if self._can_evict is not None and not self._can_evict(key):
                # Pinned: move it to the young end so the next trim does not scan it again.
                self.move_to_end(key)
                skipped += 1
                continue
            value = super().__getitem__(key)
            del self[key]
            if self._on_evict is not None:
                self._on_evict(key, value)
