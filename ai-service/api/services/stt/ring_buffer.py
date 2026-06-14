"""Fixed-capacity byte ring buffer for recent PCM audio."""

from collections import deque


class AudioRingBuffer:
    def __init__(self, max_bytes: int):
        if max_bytes <= 0:
            raise ValueError("max_bytes must be positive")
        self.max_bytes = max_bytes
        self._chunks: deque[bytes] = deque()
        self._size = 0

    def append(self, data: bytes) -> None:
        if not data:
            return
        if len(data) >= self.max_bytes:
            self._chunks.clear()
            self._chunks.append(data[-self.max_bytes :])
            self._size = self.max_bytes
            return
        self._chunks.append(data)
        self._size += len(data)
        while self._size > self.max_bytes and self._chunks:
            excess = self._size - self.max_bytes
            head = self._chunks[0]
            if len(head) <= excess:
                self._chunks.popleft()
                self._size -= len(head)
            else:
                self._chunks[0] = head[excess:]
                self._size -= excess

    def getvalue(self) -> bytes:
        return b"".join(self._chunks)

    def __len__(self) -> int:
        return self._size
