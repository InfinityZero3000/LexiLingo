"""Writes one generic audit row for every successful admin write request."""
import logging

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

from app.core.database import AsyncSessionLocal, get_db
from app.services.admin_audit import build_audit_log, describe_request

logger = logging.getLogger(__name__)

_WRITE_METHODS = frozenset({"POST", "PUT", "PATCH", "DELETE"})


class AdminAuditMiddleware(BaseHTTPMiddleware):
    """`get_current_admin` / `get_current_super_admin` mark the request with the
    acting admin; reads and failed writes are not recorded."""

    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)
        try:
            if request.method in _WRITE_METHODS and response.status_code < 400:
                actor_id = getattr(request.state, "admin_actor_id", None)
                if actor_id is not None and not getattr(request.state, "audit_done", False):
                    await self._persist(request, actor_id)
        except Exception as exc:  # an audit failure must never fail the admin's request
            logger.warning("Generic admin audit row not written: %s", exc)
        return response

    @staticmethod
    async def _persist(request: Request, actor_id) -> None:
        action, resource_type, resource_id, template = describe_request(request)
        entry = build_audit_log(
            actor_id=actor_id,
            action=action,
            resource_type=resource_type,
            resource_id=resource_id,
            details=f"{request.method} {template}",
            request=request,
        )
        # Tests (and any caller) that override get_db must see the row in their own session.
        override = request.app.dependency_overrides.get(get_db)
        if override is not None:
            generator = override()
            session = await generator.__anext__()
            try:
                session.add(entry)
                await session.commit()
            finally:
                await generator.aclose()
            return
        async with AsyncSessionLocal() as session:
            session.add(entry)
            await session.commit()
