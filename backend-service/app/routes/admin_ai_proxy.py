"""Admin proxy to ai-service's X-Admin-Key-gated endpoints.

The ai-service admin routes (topic-chat management, AI config) are only
protected by a static `X-Admin-Key` header — see ai-service/api/routes/admin.py.
That key must never reach a browser. This router re-exposes the same
operations behind the backend's own JWT + role checks, and injects the key
server-side when forwarding to ai-service.
"""

from __future__ import annotations

import logging
import os
from typing import Any
from urllib.parse import quote

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query

from app.core.config import settings
from app.core.dependencies import get_current_super_admin, require_resource
from app.models.user import User

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/admin/ai-proxy", tags=["Admin AI Proxy"])

_TIMEOUT = httpx.Timeout(15.0)


def _admin_headers() -> dict[str, str]:
    # Matches app.clients.ai_service_client's convention for this same key.
    api_key = os.getenv("AI_ADMIN_API_KEY", "").strip()
    if not api_key:
        raise HTTPException(status_code=503, detail="AI admin proxy is not configured on this server")
    return {"X-Admin-Key": api_key}


_DRAFT_TIMEOUT = httpx.Timeout(60.0)


async def _forward(
    method: str,
    path: str,
    *,
    params: dict | None = None,
    json: Any = None,
    timeout: httpx.Timeout = _TIMEOUT,
    prefix: str = "/admin",
) -> Any:
    url = f"{settings.AI_SERVICE_URL.rstrip('/')}{prefix}{path}"
    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            resp = await client.request(method, url, params=params, json=json, headers=_admin_headers())
    except httpx.RequestError as exc:
        logger.error("ai-service admin proxy request failed: %s", exc)
        raise HTTPException(status_code=502, detail="ai-service unreachable") from exc

    if resp.status_code >= 400:
        raise HTTPException(status_code=resp.status_code, detail=resp.text)
    return resp.json()


@router.get("/monitoring/chat")
async def chat_monitoring(
    window: str = Query(default="24h", pattern="^(1h|24h|7d)$"),
    _admin: User = Depends(require_resource("ops")),
) -> Any:
    return await _forward("GET", "/monitoring/chat", params={"window": window}, prefix="/ai")


@router.get("/monitoring/observation-spool")
async def observation_spool_monitoring(
    _admin: User = Depends(require_resource("ops")),
) -> Any:
    return await _forward("GET", "/monitoring/observation-spool", prefix="/ai")


@router.get("/monitoring/llm-keys")
async def llm_key_monitoring(
    _admin: User = Depends(require_resource("ops")),
) -> Any:
    return await _forward("GET", "/monitoring/llm-keys", prefix="/ai")


@router.get("/monitoring/dashboard")
async def dashboard_monitoring(
    _admin: User = Depends(require_resource("ops")),
) -> Any:
    return await _forward("GET", "/monitoring/dashboard", prefix="/ai")


@router.get("/topics")
async def list_topics(
    limit: int = Query(default=200, le=500),
    _admin: User = Depends(require_resource("topics")),
) -> Any:
    return await _forward("GET", "/topics", params={"limit": limit})


@router.post("/topics")
async def create_topic(
    payload: dict,
    _admin: User = Depends(require_resource("topics")),
) -> Any:
    return await _forward("POST", "/topics", json=payload)


@router.post("/topics/suggest-meta")
async def suggest_topic_meta(
    payload: dict,
    _admin: User = Depends(require_resource("topics")),
) -> Any:
    return await _forward("POST", "/topics/suggest-meta", json=payload)


@router.post("/topics/draft")
async def draft_topic(
    payload: dict,
    _admin: User = Depends(require_resource("topics")),
) -> Any:
    return await _forward("POST", "/topics/draft", json=payload, timeout=_DRAFT_TIMEOUT)


@router.get("/topics/{story_id}")
async def get_topic(
    story_id: str,
    _admin: User = Depends(require_resource("topics")),
) -> Any:
    return await _forward("GET", f"/topics/{quote(story_id, safe='')}")


@router.get("/config")
async def get_ai_config(
    _admin: User = Depends(get_current_super_admin),
) -> Any:
    return await _forward("GET", "/config")


@router.put("/config")
async def update_ai_config(
    payload: dict,
    _admin: User = Depends(get_current_super_admin),
) -> Any:
    return await _forward("PUT", "/config", json=payload)
