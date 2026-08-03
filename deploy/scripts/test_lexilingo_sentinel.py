#!/usr/bin/env python3
"""Minimal self-check for lexilingo-sentinel.py's decision logic.

No docker/ufw/root required — subprocess calls are monkeypatched.
Run directly: python3 deploy/scripts/test_lexilingo_sentinel.py
"""

import importlib.util
import json
import sys
import tempfile
from pathlib import Path
from unittest import mock

_SPEC = importlib.util.spec_from_file_location(
    "lexilingo_sentinel", Path(__file__).parent / "lexilingo-sentinel.py"
)
sentinel = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(sentinel)


def test_is_bad():
    assert sentinel._is_bad("running", "healthy") is False
    assert sentinel._is_bad("running", "none") is False  # no healthcheck defined
    assert sentinel._is_bad("running", "unhealthy") is True
    assert sentinel._is_bad("exited", "none") is True
    assert sentinel._is_bad("created", "none") is True
    assert sentinel._is_bad("missing", "missing") is True
    print("test_is_bad OK")


def test_check_scanners_blocks_after_threshold():
    with tempfile.TemporaryDirectory() as tmp:
        log_path = Path(tmp) / "security.log"
        state_path = Path(tmp) / "state.json"
        sentinel.SECURITY_LOG_PATH = log_path
        sentinel.SCANNER_STATE_PATH = state_path
        sentinel.SCANNER_BLOCK_THRESHOLD = 3
        sentinel._scanner_state = None

        lines = [json.dumps({"remote_addr": "1.2.3.4", "status": 444}) for _ in range(2)]
        lines += [json.dumps({"remote_addr": "9.9.9.9", "status": 200})]  # not a scanner hit
        log_path.write_text("\n".join(lines) + "\n")

        blocked = []

        def fake_run(cmd, timeout=10):
            if cmd[:2] == ["ufw", "status"]:
                return mock.Mock(returncode=0, stdout="", stderr="")
            if cmd[:2] == ["ufw", "insert"]:
                blocked.append(cmd[5])  # ["ufw","insert","1","deny","from",ip,...]
                return mock.Mock(returncode=0, stdout="", stderr="")
            raise AssertionError(f"unexpected command: {cmd}")

        with mock.patch.object(sentinel, "run", fake_run), mock.patch.object(sentinel, "alert"):
            sentinel.check_scanners()
            assert blocked == [], f"should not block below threshold yet, got {blocked}"

            # One more 444 hit pushes 1.2.3.4 to the threshold (3).
            with log_path.open("a") as fh:
                fh.write(json.dumps({"remote_addr": "1.2.3.4", "status": 444}) + "\n")
            sentinel.check_scanners()
            assert blocked == ["1.2.3.4"], f"expected block at threshold, got {blocked}"

            # Second pass over the same (now-blocked) IP must not re-block.
            with log_path.open("a") as fh:
                fh.write(json.dumps({"remote_addr": "1.2.3.4", "status": 444}) + "\n")
            sentinel.check_scanners()
            assert blocked == ["1.2.3.4"], f"must not double-block, got {blocked}"

    print("test_check_scanners_blocks_after_threshold OK")


def test_check_disk_cooldown_prevents_thrash():
    calls = []

    def fake_run(cmd, timeout=10):
        if cmd[0] == "df":
            return mock.Mock(returncode=0, stdout="Use%\n90%\n")
        if cmd[:3] == ["docker", "system", "prune"]:
            calls.append("prune")
            return mock.Mock(returncode=0, stdout="", stderr="")
        raise AssertionError(f"unexpected command: {cmd}")

    sentinel._last_prune_ts = 0.0
    with mock.patch.object(sentinel, "run", fake_run), mock.patch.object(sentinel, "alert"):
        sentinel.check_disk()
        sentinel.check_disk()  # immediate second call: cooldown must block this
    assert calls == ["prune"], f"expected exactly one prune due to cooldown, got {calls}"
    print("test_check_disk_cooldown_prevents_thrash OK")


if __name__ == "__main__":
    test_is_bad()
    test_check_scanners_blocks_after_threshold()
    test_check_disk_cooldown_prevents_thrash()
    print("All self-checks passed.")
