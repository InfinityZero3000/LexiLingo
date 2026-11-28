"""Ships ai-service errors to backend-service's error monitor.

Recording is a deque append, so it cannot slow or fail a request. A background
task posts the buffer every few seconds and never raises. Only the route
template, status, exception type and code location leave the process, plus a
scrubbed message; bodies, query strings and headers are never read.
"""

from __future__ import annotations

import asyncio
import logging
import os
import re
import traceback
from collections import deque
from datetime import datetime, timezone
from typing import Any, Deque, Dict, List, Optional

import httpx
from fastapi import Request
from fastapi.responses import JSONResponse

from api.core.background import spawn
from api.core.config import settings

logger = logging.getLogger(__name__)

SERVICE = "ai-service"
BUFFER_SIZE = 500
BATCH_SIZE = 200
FLUSH_INTERVAL_SECONDS = 15.0
TIMEOUT_SECONDS = 5.0
MESSAGE_LIMIT = 300
UNMATCHED_ROUTE = "<unmatched>"
NO_RETRY_STATUSES = frozenset({401, 403, 422})
_SKIPPED_PATHS = ("/health", "/metrics", "/ping", "/live", "/docs", "/redoc", "/openapi.json")

_EMAIL = re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+")
_BEARER = re.compile(r"(?i)bearer\s+[\w.~+/=-]+")
_JWT = re.compile(r"eyJ[\w-]+\.[\w-]+\.[\w-]+")

_buffer: Deque[Dict[str, Any]] = deque(maxlen=BUFFER_SIZE)
_dropped = 0
_enabled = True
_rejection_logged = False
_task: Optional["asyncio.Task[None]"] = None


def scrub(text: Optional[str]) -> Optional[str]:
    if not text:
        return None
    text = _JWT.sub("[token]", _BEARER.sub("[token]", _EMAIL.sub("[email]", text)))
    return text[:MESSAGE_LIMIT]


def _skipped(path: str) -> bool:
    return any(path == p or path.startswith(p + "/") for p in _SKIPPED_PATHS)


def _route_template(scope: Dict[str, Any]) -> str:
    route = scope.get("route")
    return getattr(route, "path", None) or UNMATCHED_ROUTE


_API_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + os.sep


def _location(exc: BaseException) -> Optional[str]:
    frames = [
        f
        for f in traceback.extract_tb(exc.__traceback__)
        if f.filename.startswith(_API_DIR) and f.filename != __file__
    ]
    if not frames:
        return None
    return f"{os.path.basename(frames[-1].filename)}:{frames[-1].name}"


def _request_id(scope: Dict[str, Any]) -> Optional[str]:
    for key, value in scope.get("headers", ()):
        if key == b"x-request-id":
            return value.decode("latin-1")[:64] or None
    return None


def _enqueue(event: Dict[str, Any]) -> None:
    global _dropped
    if not _enabled:
        return
    if len(_buffer) == BUFFER_SIZE:
        _dropped += 1
    _buffer.append(event)


def _event(
    scope: Dict[str, Any],
    status: int,
    error_type: Optional[str],
    location: Optional[str],
    message: Optional[str],
) -> Dict[str, Any]:
    return {
        "occurred_at": datetime.now(timezone.utc).isoformat(),
        "method": scope.get("method", ""),
        "route": _route_template(scope),
        "status": status,
        "error_type": error_type,
        "location": location,
        "message": scrub(message),
        "request_id": _request_id(scope),
    }


class OpsErrorMiddleware:
    """Pure ASGI so streaming responses and the exception path are left alone."""

    def __init__(self, app: Any) -> None:
        self.app = app

    async def __call__(self, scope: Dict[str, Any], receive: Any, send: Any) -> None:
        if scope["type"] != "http" or _skipped(scope.get("path", "")):
            await self.app(scope, receive, send)
            return

        async def tracked_send(message: Dict[str, Any]) -> None:
            if message["type"] == "http.response.start" and message["status"] >= 400:
                try:
                    state = scope.get("state") or {}
                    if not state.get("ops_error_recorded"):
                        state["ops_error_recorded"] = True
                        _enqueue(
                            _event(scope, message["status"], None, None, state.get("ops_detail"))
                        )
                except Exception:
                    logger.debug("ops error capture failed", exc_info=True)
            await send(message)

        await self.app(scope, receive, tracked_send)


async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    try:
        state = request.scope.setdefault("state", {})
        if not _skipped(request.url.path) and not state.get("ops_error_recorded"):
            state["ops_error_recorded"] = True
            _enqueue(_event(request.scope, 500, type(exc).__name__, _location(exc), str(exc)))
    except Exception:
        logger.debug("ops error capture failed", exc_info=True)
    logger.error("Unhandled %s on %s %s", type(exc).__name__, request.method, request.url.path, exc_info=exc)
    return JSONResponse({"detail": "Internal server error"}, status_code=500)


def is_configured() -> bool:
    return bool(settings.LEARNER_STATE_INTERNAL_TOKEN and settings.LEARNER_STATE_API_URL)


async def flush_once(client: httpx.AsyncClient) -> None:
    global _dropped, _rejection_logged
    if not _buffer:
        return
    batch: List[Dict[str, Any]] = [_buffer.popleft() for _ in range(min(BATCH_SIZE, len(_buffer)))]
    dropped = _dropped
    try:
        response = await client.post(
            f"{settings.LEARNER_STATE_API_URL}/ops/errors:batch",
            json={"service": SERVICE, "dropped": dropped, "events": batch},
            headers={
                "X-LexiLingo-Service-Token": settings.LEARNER_STATE_INTERNAL_TOKEN,
                "X-LexiLingo-Audience": settings.LEARNER_STATE_INTERNAL_AUDIENCE,
            },
        )
        status: Optional[int] = response.status_code
    except httpx.HTTPError:
        status = None

    if status is not None and status < 300:
        _dropped -= dropped
        _rejection_logged = False
        return
    if status in NO_RETRY_STATUSES:
        _dropped -= dropped
        if not _rejection_logged:
            _rejection_logged = True
            logger.warning("Error batch rejected by backend-service (%s); dropping it", status)
        return

    _dropped += max(0, len(_buffer) + len(batch) - BUFFER_SIZE)
    _buffer.extendleft(reversed(batch))


async def _run(interval: float) -> None:
    async with httpx.AsyncClient(timeout=TIMEOUT_SECONDS) as client:
        while True:
            await asyncio.sleep(interval)
            try:
                await flush_once(client)
            except Exception:
                logger.warning("Ops error flush failed", exc_info=True)


def start_ops_error_reporter(interval: float = FLUSH_INTERVAL_SECONDS) -> bool:
    global _task, _enabled
    if not is_configured():
        _enabled = False
        logger.info("Ops error reporter disabled: LEARNER_STATE_API_URL/INTERNAL_TOKEN not set")
        return False
    _enabled = True
    _task = spawn(_run(interval), name="ops_error_reporter")
    return True


async def stop_ops_error_reporter() -> None:
    global _task
    task, _task = _task, None
    if task is None:
        return
    task.cancel()
    try:
        await task
    except asyncio.CancelledError:
        pass


def reset() -> None:
    global _dropped, _enabled, _rejection_logged
    _buffer.clear()
    _dropped = 0
    _enabled = True
    _rejection_logged = False
