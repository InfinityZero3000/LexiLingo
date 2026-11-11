"""Backup health for the admin dashboard, read from the status files the backup scripts write."""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

BACKUP_STALE_AFTER = 8 * 3600  # the timer fires every 6 hours
VERIFY_STALE_AFTER = 8 * 24 * 3600  # the verify timer is weekly


def _json(path: Path) -> dict | None:
    try:
        data = json.loads(path.read_text())
        return data if isinstance(data, dict) else None
    except (OSError, ValueError):
        return None


def _parse(value: Any) -> datetime | None:
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None


def _age(at: datetime | None, now: datetime) -> int | None:
    return int((now - at).total_seconds()) if at else None


def _failure_marker(state_dir: Path) -> datetime | None:
    try:
        for line in (state_dir / "backup-failure.state").read_text().splitlines():
            if line.startswith("timestamp_utc="):
                return _parse(line.split("=", 1)[1])
    except OSError:
        pass
    return None


def read_backup_status(state_dir: str | Path, now: datetime | None = None) -> dict:
    now = now or datetime.now(timezone.utc)
    state_dir = Path(state_dir)
    if not state_dir.is_dir():
        return {"state": "unavailable", "backup": None, "verify": None, "failure_marker_at": None}

    backup = _json(state_dir / "backup-last.json")
    verify = _json(state_dir / "verify-last.json")
    marker = _failure_marker(state_dir)

    backup_at = _parse(backup.get("at")) if backup else None
    if backup is None:
        backup_state = "never"
    elif backup.get("result") != "ok":
        backup_state = "failed"
    elif (_age(backup_at, now) or 0) > BACKUP_STALE_AFTER:
        backup_state = "stale"
    else:
        backup_state = "ok"

    verify_at = _parse(verify.get("at")) if verify else None
    if verify is None:
        verify_state = "never"
    elif verify.get("result") != "ok":
        verify_state = "failed"
    elif (_age(verify_at, now) or 0) > VERIFY_STALE_AFTER:
        verify_state = "stale"
    else:
        verify_state = "ok"

    # The alert marker is never cleared, so it only counts while no good backup is newer than it.
    unrecovered = bool(marker and (backup_state != "ok" or (backup_at and marker > backup_at)))

    return {
        "state": backup_state,
        "backup": {**backup, "age_seconds": _age(backup_at, now)} if backup else None,
        "verify": {**verify, "state": verify_state, "age_seconds": _age(verify_at, now)} if verify else {"state": "never"},
        "failure_marker_at": marker.isoformat() if unrecovered else None,
    }
