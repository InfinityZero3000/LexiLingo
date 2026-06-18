"""
HTTP client for proxying requests to ai-service and backend-service.

The mcp-server is a lightweight stdio server for IDE integration.
Instead of loading heavy ML models locally, it proxies to:
- ai-service (port 8001) for STT, TTS, chat via local models
- backend-service (port 8000) for user data, lessons, progress
- Gemini API directly for lightweight AI tasks
"""

import logging
import os
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)

AI_SERVICE_URL = os.getenv("AI_SERVICE_URL", "http://localhost:8001").rstrip("/")
BACKEND_SERVICE_URL = os.getenv(
    "BACKEND_SERVICE_URL", "http://localhost:8000"
).rstrip("/")

_client = None


class UpstreamServiceError(RuntimeError):
    def __init__(self, service: str, status_code: int | None, retryable: bool):
        super().__init__(f"{service} request failed")
        self.service = service
        self.status_code = status_code
        self.retryable = retryable


def _auth_headers() -> Dict[str, str]:
    token = os.getenv("LEXILINGO_ACCESS_TOKEN", "").strip()
    return {"Authorization": f"Bearer {token}"} if token else {}


async def get_client():
    """Get or create async HTTP client (lazy import httpx)"""
    global _client

    if _client is not None and not _client.is_closed:
        return _client

    try:
        import httpx
        _client = httpx.AsyncClient(timeout=120.0)  # Ollama can take 40-90s on CPU
        return _client
    except ImportError:
        raise ImportError(
            "httpx not installed. Run: pip install httpx"
        )


async def call_ai_service(
    method: str,
    path: str,
    json: Dict[str, Any] = None,
    data: Any = None,
    files: Any = None,
) -> Dict[str, Any]:
    """
    Call ai-service API endpoint.

    Args:
        method: HTTP method (GET, POST, etc.)
        path: API path (e.g., /api/v1/chat/messages)
        json: JSON body
        data: Form data
        files: File uploads

    Returns:
        Parsed JSON response

    Raises:
        ConnectionError: If ai-service is not available
    """
    import httpx

    client = await get_client()
    url = f"{AI_SERVICE_URL}{path}"

    try:
        response = await client.request(
            method, url, json=json, data=data, files=files, headers=_auth_headers()
        )
        response.raise_for_status()
        return response.json()
    except httpx.ConnectError:
        logger.warning(f"ai-service not available at {AI_SERVICE_URL}")
        raise UpstreamServiceError("ai-service", None, True)
    except httpx.HTTPStatusError as e:
        status_code = e.response.status_code
        logger.error("ai-service returned status %s", status_code)
        raise UpstreamServiceError(
            "ai-service", status_code, status_code >= 500 or status_code == 429
        ) from e
    except Exception as e:
        logger.error(f"ai-service call failed: {e}")
        raise


async def call_ai_service_raw(
    method: str,
    path: str,
    json: Dict[str, Any] = None,
    files: Any = None,
) -> bytes:
    """
    Call ai-service and return raw bytes (for audio responses).
    """
    import httpx

    client = await get_client()
    url = f"{AI_SERVICE_URL}{path}"

    try:
        response = await client.request(
            method, url, json=json, files=files, headers=_auth_headers()
        )
        response.raise_for_status()
        return response.content
    except httpx.ConnectError:
        raise UpstreamServiceError("ai-service", None, True)
    except Exception as e:
        logger.error(f"ai-service raw call failed: {e}")
        raise


async def call_backend_service(
    method: str,
    path: str,
    json: Dict[str, Any] = None,
) -> Dict[str, Any]:
    """
    Call backend-service API endpoint.
    """
    import httpx

    client = await get_client()
    url = f"{BACKEND_SERVICE_URL}{path}"

    try:
        response = await client.request(
            method, url, json=json, headers=_auth_headers()
        )
        response.raise_for_status()
        return response.json()
    except httpx.ConnectError:
        logger.warning(f"backend-service not available at {BACKEND_SERVICE_URL}")
        raise UpstreamServiceError("backend-service", None, True)
    except httpx.HTTPStatusError as e:
        status_code = e.response.status_code
        logger.error("backend-service returned status %s", status_code)
        raise UpstreamServiceError(
            "backend-service",
            status_code,
            status_code >= 500 or status_code == 429,
        ) from e
    except Exception as e:
        logger.error(f"backend-service call failed: {e}")
        raise


async def check_ai_service_health() -> bool:
    """Check if ai-service is available"""
    try:
        client = await get_client()
        resp = await client.get(f"{AI_SERVICE_URL}/health", timeout=5.0)
        return resp.status_code == 200
    except Exception:
        return False


async def check_backend_service_health() -> bool:
    """Check if backend-service is available"""
    try:
        client = await get_client()
        resp = await client.get(f"{BACKEND_SERVICE_URL}/health", timeout=5.0)
        return resp.status_code == 200
    except Exception:
        return False


async def cleanup():
    """Close HTTP client"""
    global _client
    if _client and not _client.is_closed:
        await _client.aclose()
        _client = None
