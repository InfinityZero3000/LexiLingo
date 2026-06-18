"""
Serves /.well-known/ files required for Android App Links and iOS Universal Links.

Android: https://lexilingo.me/.well-known/assetlinks.json
iOS:     https://lexilingo.me/.well-known/apple-app-site-association
"""

from fastapi import APIRouter
from fastapi.responses import JSONResponse

from app.core.config import settings

router = APIRouter(tags=["Well-Known"])


@router.get("/.well-known/assetlinks.json", include_in_schema=False)
async def assetlinks() -> JSONResponse:
    payload = [
        {
            "relation": ["delegate_permission/common.handle_all_urls"],
            "target": {
                "namespace": "android_app",
                "package_name": "com.lexilingo.lexilingo_app",
                "sha256_cert_fingerprints": [settings.ANDROID_SHA256_FINGERPRINT],
            },
        }
    ]
    return JSONResponse(content=payload, media_type="application/json")


@router.get("/.well-known/apple-app-site-association", include_in_schema=False)
async def apple_app_site_association() -> JSONResponse:
    app_id = f"{settings.IOS_TEAM_ID}.{settings.IOS_BUNDLE_ID}"
    payload = {
        "applinks": {
            "apps": [],
            "details": [
                {
                    "appID": app_id,
                    "paths": [
                        "/vocabulary/review",
                        "/course/*",
                        "/lesson/*",
                        "/leaderboard",
                        "/achievement/*",
                        "/referral/*",
                        "/settings",
                    ],
                }
            ],
        }
    }
    return JSONResponse(content=payload, media_type="application/json")
