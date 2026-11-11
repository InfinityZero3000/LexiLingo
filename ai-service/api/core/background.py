"""Fire-and-forget tasks that cannot be garbage-collected mid-run.

The event loop keeps only a weak reference to a task, so `asyncio.create_task(coro())` without a stored reference may be
collected before it finishes (the asyncio docs say so). A long loop such as the content-ETL staleness watch would then stop
without a trace. `spawn` holds the reference and logs an exception nobody awaits.
"""
from __future__ import annotations

import asyncio
import logging
from typing import Any, Coroutine, Optional, Set

logger = logging.getLogger(__name__)
_TASKS: Set["asyncio.Task[Any]"] = set()


def _finished(task: "asyncio.Task[Any]") -> None:
    _TASKS.discard(task)
    if not task.cancelled() and task.exception() is not None:
        logger.error("background task %r failed: %s", task.get_name(), task.exception(), exc_info=task.exception())


def spawn(coro: Coroutine[Any, Any, Any], *, name: Optional[str] = None) -> "asyncio.Task[Any]":
    task = asyncio.create_task(coro, name=name)
    _TASKS.add(task)
    task.add_done_callback(_finished)
    return task
