"""Temporary per-account lockout after repeated failed logins."""

import logging
import shutil
import socket
import subprocess
import time
from unittest.mock import patch

import bcrypt
import pytest
import redis.asyncio as aioredis

from app.core import login_lockout
from app.core.redis import RedisClient

BASE = "/api/v1/auth"
GOOD = "correct-horse-battery"
_GOOD_HASH = bcrypt.hashpw(GOOD.encode(), bcrypt.gensalt(rounds=4)).decode()
BAD = {"email": "test@example.com", "password": "wrong-password"}


# The shared fixtures carry a hash that matches no password; these give them a real one.
@pytest.fixture
async def test_user(test_user, db_session):
    test_user.hashed_password = _GOOD_HASH
    await db_session.commit()
    return test_user


@pytest.fixture
async def admin_user(admin_user, db_session):
    admin_user.hashed_password = _GOOD_HASH
    await db_session.commit()
    return admin_user


async def _fail(client, n=1, email="test@example.com", path="/login"):
    last = None
    for _ in range(n):
        last = await client.post(f"{BASE}{path}", json={"email": email, "password": "wrong-password"})
    return last


@pytest.mark.asyncio
async def test_locks_after_max_failures_with_retry_after(async_client, test_user):
    for _ in range(login_lockout.MAX_FAILURES - 1):
        assert (await async_client.post(f"{BASE}/login", json=BAD)).status_code == 401

    tenth = await async_client.post(f"{BASE}/login", json=BAD)
    assert tenth.status_code == 429
    assert int(tenth.headers["Retry-After"]) == login_lockout.LOCK_SECONDS

    # Even the right password is refused while locked.
    right = await async_client.post(f"{BASE}/login", json={"email": "test@example.com", "password": GOOD})
    assert right.status_code == 429
    assert 0 < int(right.headers["Retry-After"]) <= login_lockout.LOCK_SECONDS


@pytest.mark.asyncio
async def test_unknown_email_is_indistinguishable(async_client, test_user):
    known = await _fail(async_client, login_lockout.MAX_FAILURES)
    unknown = await _fail(async_client, login_lockout.MAX_FAILURES, email="nobody@example.com")

    assert known.status_code == unknown.status_code == 429
    assert known.json()["error"] == unknown.json()["error"]
    assert "Retry-After" in known.headers and "Retry-After" in unknown.headers

    # Below the threshold a known and an unknown email answer the same way too.
    first_known = await _fail(async_client, 1, email="test2@example.com")
    first_unknown = await _fail(async_client, 1, email="nobody2@example.com")
    assert first_known.status_code == first_unknown.status_code == 401
    assert first_known.json()["error"] == first_unknown.json()["error"]


@pytest.mark.asyncio
async def test_lock_expires(async_client, test_user):
    await _fail(async_client, login_lockout.MAX_FAILURES)
    assert (await async_client.post(f"{BASE}/login", json=BAD)).status_code == 429

    key = login_lockout.account_key("test@example.com")
    login_lockout._memory_locks[key] = time.time() - 1

    ok = await async_client.post(f"{BASE}/login", json={"email": "test@example.com", "password": GOOD})
    assert ok.status_code == 200


@pytest.mark.asyncio
async def test_failures_outside_the_window_do_not_add_up(async_client, test_user):
    await _fail(async_client, login_lockout.MAX_FAILURES - 1)
    key = login_lockout.account_key("test@example.com")
    count, _ = login_lockout._memory_failures[key]
    login_lockout._memory_failures[key] = (count, time.time() - 1)

    assert (await _fail(async_client, 1)).status_code == 401


@pytest.mark.asyncio
async def test_success_resets_the_counter(async_client, test_user):
    await _fail(async_client, login_lockout.MAX_FAILURES - 1)
    ok = await async_client.post(f"{BASE}/login", json={"email": "test@example.com", "password": GOOD})
    assert ok.status_code == 200

    # A fresh run of MAX-1 failures does not lock, so the counter really was reset.
    assert (await _fail(async_client, login_lockout.MAX_FAILURES - 1)).status_code == 401


@pytest.mark.asyncio
async def test_email_case_does_not_dodge_the_lock(async_client, test_user):
    await _fail(async_client, login_lockout.MAX_FAILURES - 1)
    assert (await _fail(async_client, 1, email="TEST@Example.com")).status_code == 429


@pytest.mark.asyncio
async def test_admin_login_shares_the_protection(async_client, admin_user):
    for _ in range(login_lockout.MAX_FAILURES - 1):
        assert (await _fail(async_client, 1, "admin@example.com", "/admin/login")).status_code == 401
    locked = await _fail(async_client, 1, "admin@example.com", "/admin/login")
    assert locked.status_code == 429
    assert "Retry-After" in locked.headers

    good = await async_client.post(
        f"{BASE}/admin/login", json={"email": "admin@example.com", "password": GOOD}
    )
    assert good.status_code == 429


@pytest.mark.asyncio
async def test_lockout_is_logged_without_the_email(async_client, test_user, caplog):
    with caplog.at_level(logging.WARNING, logger="app.core.login_lockout"):
        await _fail(async_client, login_lockout.MAX_FAILURES)
    lines = [r.getMessage() for r in caplog.records if "lockout" in r.getMessage().lower()]
    assert len(lines) == 1
    assert "test@example.com" not in lines[0]
    assert login_lockout.account_key("test@example.com")[:16] in lines[0]


@pytest.mark.asyncio
async def test_redis_failure_falls_back_to_memory(async_client, test_user):
    class Broken:
        async def eval(self, *a, **k):
            raise ConnectionError("down")

        async def ttl(self, *a, **k):
            raise ConnectionError("down")

        async def delete(self, *a, **k):
            raise ConnectionError("down")

    with patch.object(RedisClient, "get_instance", return_value=Broken(), autospec=True):
        last = await _fail(async_client, login_lockout.MAX_FAILURES)
    assert last.status_code == 429


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@pytest.fixture
async def real_redis():
    binary = shutil.which("redis-server")
    if not binary:
        pytest.skip("redis-server not installed")
    port = _free_port()
    proc = subprocess.Popen(
        [binary, "--port", str(port), "--save", "", "--appendonly", "no"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    client = aioredis.Redis(host="127.0.0.1", port=port, decode_responses=True)
    try:
        for _ in range(50):
            try:
                await client.ping()
                break
            except Exception:
                time.sleep(0.1)
        yield client
    finally:
        await client.aclose()
        proc.terminate()
        proc.wait(timeout=5)


@pytest.mark.asyncio
async def test_lockout_counts_and_expires_in_real_redis(async_client, test_user, real_redis):
    with patch.object(RedisClient, "get_instance", return_value=real_redis, autospec=True):
        last = await _fail(async_client, login_lockout.MAX_FAILURES)
        assert last.status_code == 429
        key = login_lockout.account_key("test@example.com")
        assert 0 < await real_redis.ttl(f"login:lock:{key}") <= login_lockout.LOCK_SECONDS
        assert await real_redis.get(f"login:fail:{key}") is None
        assert (await async_client.post(f"{BASE}/login", json=BAD)).status_code == 429

        await real_redis.delete(f"login:lock:{key}")
        ok = await async_client.post(f"{BASE}/login", json={"email": "test@example.com", "password": GOOD})
        assert ok.status_code == 200

        await _fail(async_client, 3)
        assert int(await real_redis.get(f"login:fail:{key}")) == 3
        await async_client.post(f"{BASE}/login", json={"email": "test@example.com", "password": GOOD})
        assert await real_redis.get(f"login:fail:{key}") is None
