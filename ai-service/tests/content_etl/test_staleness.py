from __future__ import annotations

import os
import time

from api.core.config import settings
from api.services.content_etl.staleness import stale_active_sources


def _touch_active(root, name: str, age_days: float) -> None:
    active_dir = root / "active"
    active_dir.mkdir(parents=True, exist_ok=True)
    path = active_dir / f"{name}.json"
    path.write_text("{}")
    mtime = time.time() - age_days * 86400
    os.utime(path, (mtime, mtime))


def test_recent_snapshot_is_not_stale(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "CONTENT_ETL_STORAGE_ROOT", str(tmp_path))
    _touch_active(tmp_path, "oewn", age_days=1)
    assert stale_active_sources(max_age_days=30) == []


def test_old_snapshot_is_flagged_stale(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "CONTENT_ETL_STORAGE_ROOT", str(tmp_path))
    _touch_active(tmp_path, "oewn", age_days=45)
    _touch_active(tmp_path, "cmudict", age_days=5)
    assert stale_active_sources(max_age_days=30) == ["oewn"]


def test_missing_active_dir_returns_empty(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "CONTENT_ETL_STORAGE_ROOT", str(tmp_path / "does-not-exist"))
    assert stale_active_sources() == []
