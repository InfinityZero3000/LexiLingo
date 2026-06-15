"""Abstract SourceAdapter protocol for ETL adapters."""

from __future__ import annotations

from pathlib import Path
from typing import Any, Protocol, runtime_checkable


@runtime_checkable
class SourceAdapter(Protocol):
    """Protocol all ETL source adapters must satisfy."""

    source_name: str
    adapter_version: int

    def parse(self, raw_path: Path) -> list[dict[str, Any]]:
        """Parse raw file and return a list of record dicts.

        Each record must contain at minimum ``record_id``.
        Invalid rows should not be silently dropped — raise ValueError
        so the pipeline can quarantine them.
        """
        ...
