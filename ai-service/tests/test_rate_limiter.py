from api.core.rate_limiter import _sum_token_members


def test_tpm_members_sum_token_counts_not_timestamp_scores():
    members = [b"1000.0-400-a-tokens", b"1001.0-600-b-tokens"]
    assert _sum_token_members(members) == 1000


import asyncio
import time

from api.core.rate_limiter import RedisRateLimiter, voice_rpm_cap


class _Redis:
    def __init__(self, zsets):
        self.zsets = zsets

    def pipeline(self, transaction=True):
        return _Pipe(self)


class _Pipe:
    def __init__(self, redis):
        self._redis, self._ops = redis, []

    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        return False

    def zremrangebyscore(self, name, min, max):
        self._ops.append(lambda: 0)
        return self

    def zcard(self, name):
        self._ops.append(lambda: len(self._redis.zsets.get(name, {})))
        return self

    def zrange(self, name, start, end):
        self._ops.append(lambda: list(self._redis.zsets.get(name, {})))
        return self

    def zcount(self, name, min, max):
        self._ops.append(lambda: sum(1 for s in self._redis.zsets.get(name, {}).values() if float(min) <= s <= float(max)))
        return self

    async def execute(self):
        return [op() for op in self._ops]


def _limiter(zsets):
    return RedisRateLimiter(_Redis(zsets), "groq:key0", rpm_limit=30, tpm_limit=6000, rpd_limit=14400)


def test_blocked_by_names_the_window_that_refuses():
    limiter = _limiter({})

    assert limiter.blocked_by(0, 0, 0, 600) is None
    assert limiter.blocked_by(27, 0, 0, 600) == "rpm"
    assert limiter.blocked_by(0, 4800, 0, 600) == "tpm"
    assert limiter.blocked_by(0, 4799, 0, 600) is None
    assert limiter.blocked_by(0, 0, 12960, 600) == "rpd"


def test_the_same_counts_give_the_same_answer_as_can_request():
    now = time.time()
    zsets = {"groq:key0:tpm": {f"{now}-4900-1-tokens": now}}
    limiter = _limiter(zsets)

    counts = asyncio.run(limiter.window_counts())

    assert counts == (0, 4900, 0)
    assert (limiter.blocked_by(*counts, 600) is None) is asyncio.run(limiter.can_request(600))
    assert limiter.blocked_by(*counts, 0) is None


def test_voice_cap_is_one_formula():
    assert voice_rpm_cap(30, 0.9) == 27
    assert voice_rpm_cap(1, 0.1) == 1
