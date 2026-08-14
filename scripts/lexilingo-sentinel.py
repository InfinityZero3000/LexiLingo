#!/usr/bin/env python3
"""LexiLingo Auto-Healing & Sentinel Agent.

Rewritten after the deployed copy at /opt/lexilingo/scripts/lexilingo-sentinel.py
was lost with no backup and no VCS history. Reconstructed from:
- journalctl history of the old process (message formats, ~30s check cadence,
  the container/disk/scanner alert categories it used to emit)
- docker-compose.yml healthcheck definitions (which containers matter, and
  that Docker already computes their health status)
- gateway/nginx/templates/default.conf (nginx itself returns 444 for confirmed
  scanner/exploit-probe traffic; security.log line schema)
- live `ufw status numbered` output, which still had rules the old process
  added (format: `deny from <ip> comment "scanner {hits}hits {MonYYYY}"`)

Runs with stdlib only (no `docker`/`requests` package on the host's bare
python3) — everything shells out to the `docker`, `ufw`, and `df` CLIs.

Deliberate changes from the reconstructed original:
- Container restarts require N consecutive unhealthy checks (UNHEALTHY_GRACE_CHECKS)
  instead of acting on the first bad reading. The prior version's immediate-restart
  behavior is what turned a slow-but-legitimate startup (a large one-time KG sync)
  into a restart-loop that never let the sync finish — see 2026-08 incident.
- Disk-prune has a cooldown (DISK_PRUNE_COOLDOWN_SECONDS). The old logs show it
  re-running `docker system prune` every ~30s for several minutes while usage kept
  climbing anyway (something else was actively writing faster than prune reclaimed)
  — pure wasted work. Now it prunes at most once per cooldown window and says so
  plainly if usage didn't improve.
"""

from __future__ import annotations

import json
import subprocess
import time
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

# ── Config ──────────────────────────────────────────────────────────────────

CHECK_INTERVAL_SECONDS = 30
UNHEALTHY_GRACE_CHECKS = 3  # ~90s sustained-bad before restarting a container

CONTAINERS = [
    "lexilingo-gateway",
    "lexilingo-postgres",
    "lexilingo-mongodb",
    "lexilingo-redis",
    "lexilingo-backend-service",
    "lexilingo-reminder-worker",
    "lexilingo-reminder-beat",
    "lexilingo-ai-service",
    "lexilingo-kong",
    "lexilingo-grafana",
    "lexilingo-prometheus",
    "lexilingo-jaeger",
    "lexilingo-otel-collector",
]

DISK_MOUNT = "/"
DISK_THRESHOLD_PERCENT = 85
DISK_PRUNE_COOLDOWN_SECONDS = 300

SECURITY_LOG_PATH = Path("/opt/lexilingo/gateway/nginx/logs/security.log")
SCANNER_BLOCK_THRESHOLD = 20  # cumulative confirmed-scanner (444) hits per IP
SCANNER_STATE_PATH = Path("/opt/lexilingo/.deploy/sentinel_scanner_state.json")

DOCKER_TIMEOUT_SECONDS = 10


def _now() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="microseconds")


def log(message: str) -> None:
    print(f"[{_now()}] {message}", flush=True)


def alert(level: str, message: str) -> None:
    log(f"ALERT [{level}]: {message}")


def run(cmd: list[str], timeout: int = DOCKER_TIMEOUT_SECONDS) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


# ── Container health / auto-restart ──────────────────────────────────────────

_unhealthy_streak: dict[str, int] = defaultdict(int)


def _container_state(name: str) -> tuple[str, str]:
    """Return (status, status_detail) e.g. ("running", "Up 3 hours (unhealthy)")."""
    fmt = "{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}"
    result = run(["docker", "inspect", "--format", fmt, name])
    if result.returncode != 0:
        return "missing", "missing"
    status, _, health = result.stdout.strip().partition("|")
    return status, health


def _is_bad(status: str, health: str) -> bool:
    if status in ("missing", "exited", "created", "dead", "paused"):
        return True
    if status == "running" and health == "unhealthy":
        return True
    return False


def check_containers() -> None:
    for name in CONTAINERS:
        try:
            status, health = _container_state(name)
        except subprocess.TimeoutExpired:
            log(f"Error querying docker: Timeout expired ({name})")
            continue
        except Exception as exc:  # noqa: BLE001 - never let one bad container kill the loop
            log(f"Error querying docker for {name}: {exc}")
            continue

        if not _is_bad(status, health):
            _unhealthy_streak[name] = 0
            continue

        _unhealthy_streak[name] += 1
        if _unhealthy_streak[name] < UNHEALTHY_GRACE_CHECKS:
            continue

        detail = f"{status}" + (f"/{health}" if health != "none" else "")
        alert(
            "CRITICAL",
            f"Container `{name}` is down/unhealthy (State: `{status}`, Health: `{health}`). "
            f"Attempting auto-healing restart...",
        )
        try:
            restart = run(["docker", "restart", name], timeout=60)
            if restart.returncode == 0:
                alert("WARNING", f"Successfully restarted container `{name}`.")
            else:
                alert("CRITICAL", f"Failed to restart container `{name}`: {restart.stderr.strip()}")
        except Exception as exc:  # noqa: BLE001
            alert("CRITICAL", f"Failed to restart container `{name}`: {exc}")
        _unhealthy_streak[name] = 0


# ── Disk space monitoring + prune ────────────────────────────────────────────

_last_prune_ts = 0.0


def _disk_usage_percent() -> float:
    result = run(["df", "--output=pcent", DISK_MOUNT], timeout=5)
    line = result.stdout.strip().splitlines()[-1].strip().rstrip("%")
    return float(line)


def check_disk() -> None:
    global _last_prune_ts
    try:
        usage = _disk_usage_percent()
    except Exception as exc:  # noqa: BLE001
        log(f"Error reading disk usage: {exc}")
        return

    if usage < DISK_THRESHOLD_PERCENT:
        return

    now = time.monotonic()
    if now - _last_prune_ts < DISK_PRUNE_COOLDOWN_SECONDS:
        return
    _last_prune_ts = now

    alert(
        "WARNING",
        f"Disk space usage is high: {usage:.2f}% (Threshold: {DISK_THRESHOLD_PERCENT}%). "
        f"Triggering docker system prune...",
    )
    try:
        # `until=24h` spares images built in the last day. Plain -af deletes
        # every image no *running* container uses, which silently ate the
        # :rollback tags deploy-one-shot.sh creates — so on 2026-08-14 a failed
        # ai-service deploy had no image to roll back to and the service stayed
        # down through a 25-minute rebuild. Old cruft is still reclaimed.
        run(
            ["docker", "system", "prune", "-af", "--filter", "until=24h"],
            timeout=120,
        )
    except Exception as exc:  # noqa: BLE001
        alert("CRITICAL", f"Docker prune failed: {exc}")
        return

    try:
        after = _disk_usage_percent()
    except Exception as exc:  # noqa: BLE001
        log(f"Error reading disk usage after prune: {exc}")
        return

    alert("WARNING", f"Docker prune completed. Disk usage changed from {usage:.2f}% to {after:.2f}%.")
    if after >= usage:
        alert(
            "WARNING",
            f"Docker prune did not reduce disk usage ({usage:.2f}% -> {after:.2f}%); "
            f"something else is actively writing this disk faster than prune reclaims it.",
        )


# ── Nginx scanner detection + ufw auto-block ─────────────────────────────────

def _load_scanner_state() -> dict:
    if SCANNER_STATE_PATH.exists():
        try:
            return json.loads(SCANNER_STATE_PATH.read_text())
        except Exception:  # noqa: BLE001
            pass
    return {"offset": 0, "inode": None, "hit_counts": {}, "blocked_ips": []}


def _save_scanner_state(state: dict) -> None:
    SCANNER_STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    SCANNER_STATE_PATH.write_text(json.dumps(state))


def _refresh_blocked_ips_from_ufw(state: dict) -> None:
    """Seed blocked_ips from live ufw rules once, so a state-file loss doesn't
    cause duplicate `ufw deny` rules for IPs already blocked."""
    try:
        result = run(["ufw", "status"], timeout=10)
    except Exception:  # noqa: BLE001
        return
    for line in result.stdout.splitlines():
        if "DENY" in line and "scanner" in line:
            parts = line.split()
            for token in parts:
                if token.count(".") == 3:
                    if token not in state["blocked_ips"]:
                        state["blocked_ips"].append(token)


_scanner_state: dict | None = None


def check_scanners() -> None:
    global _scanner_state
    if not SECURITY_LOG_PATH.exists():
        return

    if _scanner_state is None:
        _scanner_state = _load_scanner_state()
        _refresh_blocked_ips_from_ufw(_scanner_state)

    state = _scanner_state
    try:
        current_stat = SECURITY_LOG_PATH.stat()
    except Exception as exc:  # noqa: BLE001
        log(f"Error stat-ing security.log: {exc}")
        return

    # Logrotate replaces the file; a changed inode means start over from 0.
    if state.get("inode") != current_stat.st_ino:
        state["inode"] = current_stat.st_ino
        state["offset"] = 0

    if current_stat.st_size < state["offset"]:
        state["offset"] = 0  # truncated

    newly_blocked: dict[str, int] = {}
    try:
        with SECURITY_LOG_PATH.open("r", encoding="utf-8", errors="replace") as fh:
            fh.seek(state["offset"])
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    record = json.loads(line)
                except Exception:  # noqa: BLE001
                    continue
                if record.get("status") != 444:
                    continue
                ip = record.get("remote_addr")
                if not ip or ip in state["blocked_ips"]:
                    continue
                state["hit_counts"][ip] = state["hit_counts"].get(ip, 0) + 1
                if state["hit_counts"][ip] >= SCANNER_BLOCK_THRESHOLD:
                    newly_blocked[ip] = state["hit_counts"][ip]
            state["offset"] = fh.tell()
    except Exception as exc:  # noqa: BLE001
        log(f"Error reading security.log: {exc}")
        return

    for ip, hits in newly_blocked.items():
        comment = f"scanner {hits}hits {datetime.now().strftime('%b%Y')}"
        try:
            result = run(["ufw", "insert", "1", "deny", "from", ip, "comment", comment], timeout=10)
            if result.returncode == 0:
                state["blocked_ips"].append(ip)
                alert("CRITICAL", f"Nginx Security Alert: Detected DDoS/Scanner pattern. Auto-blocked IPs: ['{ip}']")
            else:
                log(f"Failed to block {ip} via ufw: {result.stderr.strip()}")
        except Exception as exc:  # noqa: BLE001
            log(f"Failed to block {ip} via ufw: {exc}")

    _save_scanner_state(state)


# ── Main loop ─────────────────────────────────────────────────────────────────

def main() -> None:
    log("LexiLingo Sentinel Daemon started.")
    while True:
        try:
            check_containers()
        except Exception as exc:  # noqa: BLE001
            log(f"check_containers crashed: {exc}")
        try:
            check_disk()
        except Exception as exc:  # noqa: BLE001
            log(f"check_disk crashed: {exc}")
        try:
            check_scanners()
        except Exception as exc:  # noqa: BLE001
            log(f"check_scanners crashed: {exc}")
        time.sleep(CHECK_INTERVAL_SECONDS)


if __name__ == "__main__":
    main()
