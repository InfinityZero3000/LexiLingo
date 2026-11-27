"""The admin web's refresh token, kept where its scripts cannot read it.

A client opts in with ``"session": "cookie"`` in the JSON body. No new request header,
so the gateway's CORS allow-list does not have to change.
"""
from urllib.parse import urlsplit

from fastapi import HTTPException, Request, Response, status

from app.core.config import settings

COOKIE_NAME = "lexi_admin_refresh"
_PATH = f"{settings.API_V1_PREFIX}/auth"
_LOCAL_HOSTS = {"localhost", "127.0.0.1"}


def require_admin_web_origin(request: Request) -> None:
    """Only the admin web may start, renew or end a cookie session.

    CORS lets every lexilingo.me subdomain call this API with cookies, so without this a
    script on the learner site could renew an admin's session and read the access token.
    """
    origin = request.headers.get("origin") or ""
    if origin in settings.admin_web_origins:
        return
    if not settings.is_production and urlsplit(origin).hostname in _LOCAL_HOSTS:
        return
    raise HTTPException(status.HTTP_403_FORBIDDEN, "Cookie sessions are for the admin web only")


def set_refresh_cookie(response: Response, token: str, max_age_days: int) -> None:
    response.set_cookie(
        COOKIE_NAME, token, max_age=max_age_days * 86400, path=_PATH,
        httponly=True, secure=settings.is_production, samesite="strict",
    )


def clear_refresh_cookie(response: Response) -> None:
    response.delete_cookie(
        COOKIE_NAME, path=_PATH, httponly=True, secure=settings.is_production, samesite="strict"
    )
