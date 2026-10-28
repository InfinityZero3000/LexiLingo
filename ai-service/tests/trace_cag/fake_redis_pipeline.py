"""A Redis pipeline stand-in for fakes built on AsyncMock.

`LearnerProfileCache.get_profile` reads level, errors and sessions through `redis.pipeline()`. An
AsyncMock's `pipeline` returns a coroutine, which `async with` rejects, so a fake that only
stubs `get`/`lrange` silently drove input_node down its Redis-failure path.
"""

from unittest.mock import MagicMock


class EmptyPipeline:
    """Answers the profile read for a learner with no stored data."""

    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        return False

    def get(self, key):
        return self

    def lrange(self, key, start, stop):
        return self

    async def execute(self):
        return [None, [], []]


def with_empty_pipeline(redis):
    redis.pipeline = MagicMock(side_effect=lambda **_kwargs: EmptyPipeline())
    return redis
