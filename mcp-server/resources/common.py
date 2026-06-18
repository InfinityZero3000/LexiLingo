from datetime import datetime, timezone
from typing import Any

from utils.api_client import UpstreamServiceError


def source(service: str, store: str, entity: str) -> dict[str, Any]:
    return {
        "service": service,
        "store": store,
        "entity": entity,
        "cache": None,
    }


def freshness(status: str = "fresh") -> dict[str, Any]:
    return {
        "status": status,
        "observed_at": datetime.now(timezone.utc).isoformat(),
        "source_updated_at": None,
        "age_seconds": None,
        "ttl_seconds": None,
    }


def upstream_error(exc: Exception) -> dict[str, Any]:
    if isinstance(exc, UpstreamServiceError):
        status = exc.status_code
        if status == 401:
            code = "UPSTREAM_UNAUTHORIZED"
        elif status == 403:
            code = "UPSTREAM_FORBIDDEN"
        elif status == 404:
            code = "UPSTREAM_NOT_FOUND"
        elif status == 429:
            code = "UPSTREAM_RATE_LIMITED"
        else:
            code = "UPSTREAM_UNAVAILABLE"
        return {
            "code": code,
            "message": "The upstream service could not provide this resource.",
            "retryable": exc.retryable,
            "upstream_status": status,
        }
    return {
        "code": "RESOURCE_UNAVAILABLE",
        "message": "The resource could not be loaded.",
        "retryable": False,
        "upstream_status": None,
    }
