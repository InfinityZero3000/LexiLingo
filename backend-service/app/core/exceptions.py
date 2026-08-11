"""
Standardized Exception Handlers
Returns error responses in the consistent ErrorResponse envelope format.
"""

import logging
from fastapi import Request, status, HTTPException
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.core.config import settings
from app.schemas.common import ErrorResponse, ErrorDetail, ErrorCodes, RequestMeta

logger = logging.getLogger(__name__)


async def http_exception_handler(request: Request, exc: HTTPException) -> JSONResponse:
    """Handle FastAPI's built-in HTTPException."""
    error_code = ErrorCodes.INTERNAL_ERROR

    # Map status codes to standard error codes
    if exc.status_code == status.HTTP_400_BAD_REQUEST:
        error_code = ErrorCodes.INVALID_INPUT
    elif exc.status_code == status.HTTP_401_UNAUTHORIZED:
        error_code = ErrorCodes.AUTH_INVALID
    elif exc.status_code == status.HTTP_403_FORBIDDEN:
        error_code = ErrorCodes.AUTH_FORBIDDEN
    elif exc.status_code == status.HTTP_404_NOT_FOUND:
        error_code = ErrorCodes.NOT_FOUND
    elif exc.status_code == status.HTTP_409_CONFLICT:
        error_code = ErrorCodes.CONFLICT
    elif exc.status_code == status.HTTP_429_TOO_MANY_REQUESTS:
        error_code = ErrorCodes.RATE_LIMITED

    error_response = ErrorResponse(
        error=ErrorDetail(
            code=error_code,
            message=str(exc.detail),
            details=getattr(exc, "details", None)
        ),
        meta=RequestMeta(
            request_id=getattr(request.state, "request_id", "unknown")
        )
    )
    
    return JSONResponse(
        status_code=exc.status_code,
        content=error_response.model_dump(mode="json"),
        headers=getattr(exc, "headers", None)
    )


async def validation_exception_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
    """Handle Pydantic validation errors."""
    error_response = ErrorResponse(
        error=ErrorDetail(
            code=ErrorCodes.VALIDATION_ERROR,
            message="Validation failed",
            details={"errors": exc.errors()}
        ),
        meta=RequestMeta(
            request_id=getattr(request.state, "request_id", "unknown")
        )
    )
    
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
        content=error_response.model_dump(mode="json")
    )


async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """Catch-all for any unhandled exceptions."""
    logger.exception(f"Unhandled exception: {exc}")
    
    error_response = ErrorResponse(
        error=ErrorDetail(
            code=ErrorCodes.INTERNAL_ERROR,
            message="An internal server error occurred",
            details={"type": type(exc).__name__, **({"message": str(exc)} if settings.DEBUG else {})}
        ),
        meta=RequestMeta(
            request_id=getattr(request.state, "request_id", "unknown")
        )
    )
    
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content=error_response.model_dump(mode="json")
    )
