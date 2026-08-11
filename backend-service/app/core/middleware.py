"""
Middleware for Rate Limiting, Error Handling, and Request Logging
Phase 1 & 5: System Reliability & Security
"""

import time
import logging
from typing import Callable, Dict, List, Optional
from collections import defaultdict
from datetime import datetime, timedelta, timezone

from fastapi import Request, Response, status
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

from app.schemas.common import ErrorResponse, ErrorDetail, RequestMeta, ErrorCodes
from app.core.logging_config import set_request_id

logger = logging.getLogger(__name__)


# ── Sensitive endpoints that get stricter per-route limits ──
# Scale with global limit: production tight values / development relaxed for load testing
def _build_strict_limits(is_dev: bool) -> Dict[str, int]:
    if is_dev:
        return {
            "/api/v1/auth/login": 300,          # relaxed — load testing from single IP
            "/api/v1/auth/register": 100,
            "/api/v1/auth/forgot-password": 50,
            "/api/v1/auth/admin/login": 100,
            "/api/v1/auth/admin/request-otp": 50,
            "/api/v1/auth/admin/verify-otp": 100,
        }
    return {
        "/api/v1/auth/login": 10,           # 10 req/min — brute-force protection
        "/api/v1/auth/register": 5,         # 5 req/min — signup abuse
        "/api/v1/auth/forgot-password": 3,  # 3 req/min — email bombing
        "/api/v1/auth/admin/login": 5,
        "/api/v1/auth/admin/request-otp": 3,
        "/api/v1/auth/admin/verify-otp": 5,
    }

try:
    from app.core.config import settings as _settings
    _STRICT_RATE_LIMITS: Dict[str, int] = _build_strict_limits(_settings.is_development)
except Exception:
    _STRICT_RATE_LIMITS = _build_strict_limits(False)


# ── Sensitive routes: fail CLOSED (503) instead of falling back to
# per-process memory counting when the distributed (Redis) limiter is
# unavailable. A per-process fallback across N worker replicas means an
# attacker can get up to N× the intended limit during a Redis outage —
# acceptable for ordinary traffic, not for brute-force-able auth/reward
# endpoints. (method, path) exact matches, plus prefix matches for
# path-parameterized/wildcard routes.
_SENSITIVE_ROUTES_EXACT = {
    ("POST", "/api/v1/auth/login"),
    ("POST", "/api/v1/auth/register"),
    ("POST", "/api/v1/auth/forgot-password"),
    ("POST", "/api/v1/auth/admin/login"),
    ("POST", "/api/v1/auth/admin/request-otp"),
    ("POST", "/api/v1/auth/admin/verify-otp"),
    ("POST", "/api/v1/xp/award"),
    ("POST", "/api/v1/challenges/daily/bonus/claim"),
}
_SENSITIVE_ROUTE_PREFIXES = (
    ("POST", "/api/v1/challenges/daily/"),  # /{challenge_id}/claim
    ("GET", "/api/v1/integrations/"),
)


def _is_sensitive_route(method: str, path: str) -> bool:
    if (method, path) in _SENSITIVE_ROUTES_EXACT:
        return True
    return any(
        method == prefix_method and path.startswith(prefix)
        for prefix_method, prefix in _SENSITIVE_ROUTE_PREFIXES
    )


class _RedisUnavailable(Exception):
    """Raised internally to distinguish a real Redis failure from a normal
    rate-limit rejection — never silently treated as 'allowed'."""


class RateLimitMiddleware(BaseHTTPMiddleware):
    """
    Distributed rate limiting middleware.

    Uses Redis (via RedisClient singleton) for distributed counters when
    available, falling back to in-memory counters so rate limiting still
    works during Redis outages or local development without Redis.

    Two tiers:
      * Global: requests_per_minute / requests_per_hour (all endpoints)
      * Strict: per-path override for sensitive endpoints (login, register…)
    """

    # Set to True in tests via monkeypatch.setattr(RateLimitMiddleware, "_testing", True)
    # This is read at dispatch time (not captured by BaseHTTPMiddleware), so monkeypatch works.
    _testing: bool = False

    def __init__(
        self,
        app,
        requests_per_minute: int = 60,
        requests_per_hour: int = 1000,
    ):
        super().__init__(app)
        self.requests_per_minute = requests_per_minute
        self.requests_per_hour = requests_per_hour

        # In-memory fallback storage (used only when Redis is unavailable)
        self._mem_minute: Dict[str, List[datetime]] = defaultdict(list)
        self._mem_hour: Dict[str, List[datetime]] = defaultdict(list)

    # ── helpers ──────────────────────────────────────────────

    @staticmethod
    def _client_ip(request: Request) -> str:
        # Only trust X-Forwarded-For when the direct peer is a configured trusted proxy.
        # Accepting the header unconditionally lets any client spoof their IP and
        # bypass all rate limiting.
        from app.core.config import settings
        peer_ip = request.client.host if request.client else None
        forwarded = request.headers.get("x-forwarded-for")
        if forwarded and peer_ip:
            trusted = {ip.strip() for ip in settings.TRUSTED_PROXIES.split(",") if ip.strip()}
            if trusted and peer_ip in trusted:
                return forwarded.split(",")[0].strip()
        return peer_ip or "unknown"

    # ── Redis-backed counting ────────────────────────────────

    async def _redis_check_and_increment(
        self, redis_client, key: str, limit: int, window_seconds: int
    ) -> tuple[bool, int]:
        """
        Atomically increment a sliding-window counter in Redis.
        Returns (allowed: bool, current_count: int).
        """
        pipe = redis_client.pipeline(transaction=True)
        try:
            pipe.incr(key)
            pipe.ttl(key)
            results = await pipe.execute()
            current = int(results[0])
            ttl = int(results[1])

            # First request in window — set expiry
            if ttl == -1:
                await redis_client.expire(key, window_seconds)

            return current <= limit, current
        except Exception as exc:
            raise _RedisUnavailable(str(exc)) from exc

    async def _check_redis(self, client_ip: str, path: str):
        """
        Check global + strict limits via Redis.
        Returns (allowed, minute_remaining, hour_remaining) or None if Redis
        is unavailable.
        """
        from app.core.redis import RedisClient
        redis_client = await RedisClient.get_instance()
        if redis_client is None:
            return None

        try:
            now_minute = int(time.time() // 60)
            now_hour = int(time.time() // 3600)

            min_key = f"rl:min:{client_ip}:{now_minute}"
            hr_key = f"rl:hr:{client_ip}:{now_hour}"

            min_ok, min_count = await self._redis_check_and_increment(
                redis_client, min_key, self.requests_per_minute, 60
            )
            hr_ok, hr_count = await self._redis_check_and_increment(
                redis_client, hr_key, self.requests_per_hour, 3600
            )

            if not min_ok:
                return False, 0, max(0, self.requests_per_hour - hr_count)
            if not hr_ok:
                return False, max(0, self.requests_per_minute - min_count), 0

            # Strict per-path limit (login, register, etc.)
            strict_limit = _STRICT_RATE_LIMITS.get(path)
            if strict_limit is not None:
                strict_key = f"rl:strict:{client_ip}:{path}:{now_minute}"
                strict_ok, _ = await self._redis_check_and_increment(
                    redis_client, strict_key, strict_limit, 60
                )
                if not strict_ok:
                    return False, 0, max(0, self.requests_per_hour - hr_count)

            return (
                True,
                max(0, self.requests_per_minute - min_count),
                max(0, self.requests_per_hour - hr_count),
            )
        except Exception as exc:
            logger.warning(f"Redis rate-limit check failed, falling back to memory: {exc}")
            return None

    # ── In-memory fallback ───────────────────────────────────

    def _check_memory(self, client_ip: str, path: str):
        """
        Fallback in-memory rate limiting (single-instance only).
        Returns (allowed, minute_remaining, hour_remaining).
        """
        now = datetime.now(timezone.utc)
        one_min_ago = now - timedelta(minutes=1)
        one_hr_ago = now - timedelta(hours=1)

        # Prune stale entries
        self._mem_minute[client_ip] = [
            ts for ts in self._mem_minute[client_ip] if ts > one_min_ago
        ]
        self._mem_hour[client_ip] = [
            ts for ts in self._mem_hour[client_ip] if ts > one_hr_ago
        ]

        min_count = len(self._mem_minute[client_ip])
        hr_count = len(self._mem_hour[client_ip])

        if min_count >= self.requests_per_minute:
            return False, 0, max(0, self.requests_per_hour - hr_count)
        if hr_count >= self.requests_per_hour:
            return False, max(0, self.requests_per_minute - min_count), 0

        # Strict per-path limit
        strict_limit = _STRICT_RATE_LIMITS.get(path)
        if strict_limit is not None:
            path_key = f"{client_ip}:{path}"
            self._mem_minute[path_key] = [
                ts for ts in self._mem_minute.get(path_key, []) if ts > one_min_ago
            ]
            if len(self._mem_minute[path_key]) >= strict_limit:
                return False, 0, max(0, self.requests_per_hour - hr_count)
            self._mem_minute[path_key].append(now)

        self._mem_minute[client_ip].append(now)
        self._mem_hour[client_ip].append(now)

        return (
            True,
            max(0, self.requests_per_minute - min_count - 1),
            max(0, self.requests_per_hour - hr_count - 1),
        )

    # ── dispatch ─────────────────────────────────────────────

    # Paths exempt from rate limiting
    _EXEMPT_PATHS = {
        "/health", "/health/ready", "/ping",
        "/api/v1/health", "/api/v1/health/ready", "/api/v1/ping",
        "/docs", "/redoc", "/openapi.json",
        "/",
    }

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        """Rate limit based on client IP with Redis → memory fallback."""
        if self.__class__._testing:
            return await call_next(request)

        # Skip preflight and exempt paths (health, docs, etc.)
        if request.method == "OPTIONS":
            return await call_next(request)
        if request.url.path in self._EXEMPT_PATHS:
            return await call_next(request)

        client_ip = self._client_ip(request)

        path = request.url.path
        method = request.method

        # Try Redis first, fallback to memory — except for sensitive routes,
        # which fail closed instead: a per-process memory fallback across
        # multiple worker replicas effectively multiplies the intended limit.
        result = await self._check_redis(client_ip, path)
        if result is None:
            if _is_sensitive_route(method, path):
                logger.error(
                    f"Distributed rate limiter unavailable for sensitive route "
                    f"{method} {path} — failing closed."
                )
                return self._unavailable_response()
            result = self._check_memory(client_ip, path)

        allowed, min_remaining, hr_remaining = result

        if not allowed:
            logger.warning(f"Rate limit exceeded for IP: {client_ip} on {path}")
            return self._rate_limit_response(
                "Too many requests. Please try again later."
            )

        response = await call_next(request)
        response.headers["X-RateLimit-Limit-Minute"] = str(self.requests_per_minute)
        response.headers["X-RateLimit-Remaining-Minute"] = str(min_remaining)
        response.headers["X-RateLimit-Limit-Hour"] = str(self.requests_per_hour)
        response.headers["X-RateLimit-Remaining-Hour"] = str(hr_remaining)
        return response

    def _unavailable_response(self) -> JSONResponse:
        """503 for sensitive routes when the distributed limiter can't be reached."""
        error_response = ErrorResponse(
            error=ErrorDetail(
                code=ErrorCodes.RATE_LIMITED,
                message="Service temporarily unavailable. Please try again shortly.",
                details={"retry_after_seconds": 5},
            )
        )
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content=error_response.model_dump(mode="json"),
            headers={"Retry-After": "5"},
        )

    def _rate_limit_response(self, message: str) -> JSONResponse:
        """Return standardized rate limit error response."""
        error_response = ErrorResponse(
            error=ErrorDetail(
                code=ErrorCodes.RATE_LIMITED,
                message=message,
                details={"retry_after_seconds": 60}
            )
        )
        return JSONResponse(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            content=error_response.model_dump(mode="json"),
            headers={"Retry-After": "60"},
        )


class ErrorHandlerMiddleware(BaseHTTPMiddleware):
    """
    Global error handler middleware.
    Phase 5: Catch unhandled exceptions and return standardized error responses.
    """
    
    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        """Catch and handle exceptions."""
        try:
            response = await call_next(request)
            return response
        except Exception as exc:
            logger.exception(f"Unhandled exception: {exc}")
            
            error_response = ErrorResponse(
                error=ErrorDetail(
                    code=ErrorCodes.INTERNAL_ERROR,
                    message="An internal server error occurred",
                )
            )
            
            return JSONResponse(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                content=error_response.model_dump(mode="json")
            )


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    """
    Request/Response logging middleware.
    Phase 5: Observability and monitoring.
    """
    
    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        """Log request and response details."""
        
        # Start timer
        start_time = time.time()
        
        # Log request
        logger.info(
            f"Request: {request.method} {request.url.path} "
            f"from {request.client.host if request.client else 'unknown'}"
        )
        
        # Process request
        try:
            response = await call_next(request)
        except Exception as exc:
            # Log error
            duration_ms = (time.time() - start_time) * 1000
            logger.error(
                f"Request failed: {request.method} {request.url.path} "
                f"Duration: {duration_ms:.2f}ms Error: {exc}"
            )
            raise
        
        # Calculate duration
        duration_ms = (time.time() - start_time) * 1000
        
        # Log response
        logger.info(
            f"Response: {request.method} {request.url.path} "
            f"Status: {response.status_code} "
            f"Duration: {duration_ms:.2f}ms"
        )
        
        # Add timing header
        response.headers["X-Response-Time"] = f"{duration_ms:.2f}ms"
        
        return response


class RequestIDMiddleware(BaseHTTPMiddleware):
    """
    Add unique request ID to each request.
    Phase 1: Essential for tracking and debugging.
    """
    
    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        """Add request ID to request state."""
        import uuid
        
        request_id = str(uuid.uuid4())
        request.state.request_id = request_id
        set_request_id(request_id)

        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id
        
        return response


class PrivateNetworkAccessMiddleware(BaseHTTPMiddleware):
    """
    Handle Chrome's Private Network Access (CORS-RFC1918) for all requests.
    
    Chrome 94+ requires Access-Control-Allow-Private-Network: true header
    on BOTH the OPTIONS preflight AND the actual request response.
    Without this header on the actual request, Chrome blocks it with 'Failed to fetch'.
    """

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        # Check if this is a private network access request
        has_pna_header = (
            request.headers.get("access-control-request-private-network") == "true"
        )
        
        response = await call_next(request)
        
        # Add PNA header to response if request had it (for both OPTIONS and actual requests)
        if has_pna_header or request.method == "OPTIONS":
            response.headers["Access-Control-Allow-Private-Network"] = "true"
        
        return response


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """
    Middleware to add defense-in-depth secure security headers to all responses.
    """
    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-XSS-Protection"] = "1; mode=block"
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; frame-ancestors 'none'; object-src 'none';"
        )
        response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        return response
