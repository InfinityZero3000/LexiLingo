"""Audit trail for admin actions.

Two layers write to the same table: `AdminAuditMiddleware` records every
successful admin write generically, so no endpoint can forget to be audited,
and `record_admin_action` adds a meaningful row (what changed, why) for the
sensitive operations. A route that calls the latter marks the request so the
generic row is not written twice.
"""
from __future__ import annotations

import json
import re
from typing import Any
from uuid import UUID

from fastapi import Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.rbac import AuditLog

_ACTION_BY_METHOD = {"POST": "create", "PUT": "update", "PATCH": "update", "DELETE": "delete"}
_VERSION_SEGMENT = re.compile(r"^v\d+$")


def client_ip(request: Request | None) -> str | None:
    if request is None:
        return None
    # Reuse the rate limiter's rule: X-Forwarded-For counts only from a trusted proxy.
    from app.core.middleware import RateLimitMiddleware

    return RateLimitMiddleware._client_ip(request)[:50]


def describe_request(request: Request) -> tuple[str, str, str | None, str]:
    """(action, resource_type, resource_id, route template) for a write request."""
    route = request.scope.get("route")
    template = getattr(route, "path", None) or request.url.path
    parts = [p for p in template.strip("/").split("/") if p and not p.startswith("{")]
    while parts and (parts[0] in ("api", "admin") or _VERSION_SEGMENT.match(parts[0])):
        parts.pop(0)
    resource_type = (parts[0] if parts else "api")[:50]
    path_params = request.scope.get("path_params") or {}
    resource_id = str(next(iter(path_params.values()))) if path_params else None
    action = _ACTION_BY_METHOD.get(request.method, request.method.lower())
    return action, resource_type, resource_id, template


def build_audit_log(
    *,
    actor_id: UUID | None,
    action: str,
    resource_type: str,
    resource_id: str | None,
    details: Any,
    request: Request | None,
) -> AuditLog:
    if details is not None and not isinstance(details, str):
        details = json.dumps(details, ensure_ascii=False, default=str)
    user_agent = request.headers.get("user-agent") if request is not None else None
    return AuditLog(
        user_id=actor_id,
        action=action[:50],
        resource_type=resource_type[:50],
        resource_id=str(resource_id)[:255] if resource_id is not None else None,
        details=details,
        ip_address=client_ip(request),
        user_agent=user_agent[:500] if user_agent else None,
    )


def record_admin_action(
    db: AsyncSession,
    admin: Any,
    action: str,
    resource_type: str,
    resource_id: Any = None,
    details: Any = None,
    request: Request | None = None,
) -> AuditLog:
    """Queue a descriptive audit row; the caller's commit persists it with the change."""
    entry = build_audit_log(
        actor_id=getattr(admin, "id", None),
        action=action,
        resource_type=resource_type,
        resource_id=resource_id,
        details=details,
        request=request,
    )
    db.add(entry)
    if request is not None:
        request.state.audit_done = True
    return entry
