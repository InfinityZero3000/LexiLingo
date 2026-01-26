"""
Middleware for Rate Limiting, Error Handling, and Request Logging
Phase 1 & 5: System Reliability & Security
"""

import time
import logging
from typing import Callable
from collections import defaultdict
from datetime import datetime, timedelta

from fastapi import Request, Response, status
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

from app.schemas.common import ErrorResponse, ErrorDetail, RequestMeta, ErrorCodes

logger = logging.getLogger(__name__)


class RateLimitMiddleware(BaseHTTPMiddleware):
    """
    Simple in-memory rate limiting middleware.
    Phase 1: Protect against spam and brute force attacks.
    
    For production, consider using Redis for distributed rate limiting.
    """
    
    def __init__(
        self,
        app,
        requests_per_minute: int = 60,
        requests_per_hour: int = 1000,
    ):
        super().__init__(app)
        self.requests_per_minute = requests_per_minute
        self.requests_per_hour = requests_per_hour
        
        # In-memory storage: {client_ip: [(timestamp, count), ...]}
        self.request_counts_minute = defaultdict(list)
        self.request_counts_hour = defaultdict(list)
    
    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        """Rate limit based on client IP."""
        
        # Get client IP
        client_ip = request.client.host if request.client else "unknown"
        
        # Skip rate limiting for health check
        if request.url.path in ["/health", "/api/v1/health"]:
            return await call_next(request)
        
        # Current time
        now = datetime.utcnow()
        one_minute_ago = now - timedelta(minutes=1)
        one_hour_ago = now - timedelta(hours=1)
        
        # Clean old entries
        self.request_counts_minute[client_ip] = [
            ts for ts in self.request_counts_minute[client_ip]
            if ts > one_minute_ago
        ]
        self.request_counts_hour[client_ip] = [
            ts for ts in self.request_counts_hour[client_ip]
            if ts > one_hour_ago
        ]
        
        # Check rate limits
        minute_count = len(self.request_counts_minute[client_ip])
        hour_count = len(self.request_counts_hour[client_ip])
        
        if minute_count >= self.requests_per_minute:
            logger.warning(f"Rate limit exceeded (minute) for IP: {client_ip}")
            return self._rate_limit_response(
                f"Rate limit exceeded: {self.requests_per_minute} requests per minute"
            )
        
        if hour_count >= self.requests_per_hour:
            logger.warning(f"Rate limit exceeded (hour) for IP: {client_ip}")
            return self._rate_limit_response(
                f"Rate limit exceeded: {self.requests_per_hour} requests per hour"
            )
        
        # Record request
        self.request_counts_minute[client_ip].append(now)
        self.request_counts_hour[client_ip].append(now)
        
        # Add rate limit headers
        response = await call_next(request)
        response.headers["X-RateLimit-Limit-Minute"] = str(self.requests_per_minute)
        response.headers["X-RateLimit-Remaining-Minute"] = str(
            self.requests_per_minute - minute_count - 1
        )
        response.headers["X-RateLimit-Limit-Hour"] = str(self.requests_per_hour)
        response.headers["X-RateLimit-Remaining-Hour"] = str(
            self.requests_per_hour - hour_count - 1
        )
        
        return response
    
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
            content=error_response.model_dump(mode="json")
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
                    details={"type": type(exc).__name__}
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
        
        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id
        
        return response
