"""Bounded rotating temporary PCM storage."""

from __future__ import annotations

import os
import time
from pathlib import Path


class TempAudioWriter:
    def __init__(
        self,
        directory: str,
        session_id: str,
        max_file_bytes: int = 960_000,
        max_files: int = 3,
    ):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True)
        self.session_id = session_id
        self.max_file_bytes = max_file_bytes
        self.max_files = max_files
        self._index = 0
        self._files: list[Path] = []
        self._handle = None
        self._size = 0

    @property
    def paths(self) -> list[Path]:
        return list(self._files)

    def write(self, pcm16: bytes) -> None:
        if not pcm16:
            return
        if self._handle is None or self._size + len(pcm16) > self.max_file_bytes:
            self._rotate()
        self._handle.write(pcm16)
        self._handle.flush()
        self._size += len(pcm16)

    def _rotate(self) -> None:
        if self._handle:
            self._handle.close()
        path = self.directory / f"{self.session_id}-{self._index:04d}.pcm"
        self._index += 1
        self._files.append(path)
        while len(self._files) > self.max_files:
            self._files.pop(0).unlink(missing_ok=True)
        self._handle = path.open("wb")
        self._size = 0

    def close(self, delete: bool = True) -> None:
        if self._handle:
            self._handle.close()
            self._handle = None
        if delete:
            for path in self._files:
                path.unlink(missing_ok=True)


def cleanup_stale_audio(directory: str, ttl_seconds: int) -> int:
    cutoff = time.time() - ttl_seconds
    removed = 0
    for path in Path(directory).glob("*.pcm"):
        if path.stat().st_mtime < cutoff:
            os.unlink(path)
            removed += 1
    return removed
