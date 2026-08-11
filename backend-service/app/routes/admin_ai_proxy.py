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

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query

from app.core.config import settings
from app.core.dependencies import get_current_admin, get_current_super_admin
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


async def _forward(method: str, path: str, *, params: dict | None = None, json: Any = None) -> Any:
    url = f"{settings.AI_SERVICE_URL.rstrip('/')}/admin{path}"
    try:
        async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
            resp = await client.request(method, url, params=params, json=json, headers=_admin_headers())
    except httpx.RequestError as exc:
        logger.error("ai-service admin proxy request failed: %s", exc)
        raise HTTPException(status_code=502, detail="ai-service unreachable") from exc

    if resp.status_code >= 400:
        raise HTTPException(status_code=resp.status_code, detail=resp.text)
    return resp.json()


@router.get("/topics")
async def list_topics(
    limit: int = Query(default=200, le=500),
    _admin: User = Depends(get_current_admin),
) -> Any:
    return await _forward("GET", "/topics", params={"limit": limit})


@router.post("/topics")
async def create_topic(
    payload: dict,
    _admin: User = Depends(get_current_admin),
) -> Any:
    return await _forward("POST", "/topics", json=payload)


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
