"""Server-side client for RevenueCat's subscriber REST API.

Used to verify entitlement state independently of whatever the Flutter
client reports — the client's local RevenueCat SDK state is a UX hint only,
never a security boundary.
"""

from __future__ import annotations

import httpx

from app.core.config import settings


class RevenueCatUnavailableError(RuntimeError):
    """Raised when RevenueCat could not be reached or returned a server error."""


class RevenueCatClient:
    _BASE_URL = "https://api.revenuecat.com/v1"

    def __init__(self) -> None:
        if not settings.REVENUECAT_SECRET_API_KEY:
            raise RuntimeError("REVENUECAT_SECRET_API_KEY is not configured")
        self._headers = {
            "Authorization": f"Bearer {settings.REVENUECAT_SECRET_API_KEY}",
        }
        self._timeout = httpx.Timeout(settings.REVENUECAT_TIMEOUT_SECONDS)

    async def get_subscriber_entitlements(self, app_user_id: str) -> dict[str, dict]:
        """Return RevenueCat's `entitlements` map for one subscriber.

        An unknown subscriber (never purchased) returns `{}`, not an error.
        Raises `RevenueCatUnavailableError` on timeout/transport/5xx so the
        caller can fail closed on new grants while preserving prior state.
        """
        async with httpx.AsyncClient(timeout=self._timeout) as client:
            try:
                response = await client.get(
                    f"{self._BASE_URL}/subscribers/{app_user_id}",
                    headers=self._headers,
                )
            except httpx.TransportError as exc:
                raise RevenueCatUnavailableError(str(exc)) from exc

        if response.status_code == 404:
            return {}
        if response.status_code >= 500:
            raise RevenueCatUnavailableError(
                f"RevenueCat returned {response.status_code}"
            )
        response.raise_for_status()

        payload = response.json()
        subscriber = payload.get("subscriber", {})
        return subscriber.get("entitlements", {})
