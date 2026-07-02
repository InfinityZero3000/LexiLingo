"""
Podcast API Routes — English Learning Podcasts for Language Learners

Endpoints proxy PodcastIndex.org for search and parse RSS feeds directly
for episode listings. Curated list of English-learning podcasts is served
from hardcoded data (no API cost). All cacheable responses use APICacheService.

Phase 4: Podcast Feature.
"""

import calendar
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
import hashlib
import logging
import re
import time
import xml.etree.ElementTree as ET
from typing import Optional
from urllib.parse import urlparse, quote

import httpx
from fastapi import APIRouter, Body, Depends, HTTPException, Query, Response, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.services.api_cache_service import (
    APICacheService,
    QuotaExhaustedError,
    QuotaNearLimitError,
)
from app.services.quota_manager import Priority

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/podcasts", tags=["Podcasts"])

PODCASTINDEX_BASE = "https://api.podcastindex.org/api/1.0"

# ── CEFR Level Definitions ───────────────────────────────────────
CEFR_LEVELS = {
    "A1": {"label": "Beginner", "color": "#4CAF50"},
    "A2": {"label": "Elementary", "color": "#8BC34A"},
    "B1": {"label": "Intermediate", "color": "#FFC107"},
    "B2": {"label": "Upper Intermediate", "color": "#FF9800"},
    "C1": {"label": "Advanced", "color": "#FF5722"},
    "C2": {"label": "Proficiency", "color": "#9C27B0"},
}

# ── Curated English-Learning Podcasts by CEFR Level ─────────────
CURATED_PODCASTS = [
    # A1-A2 — slow, clear speech
    {
        "id": hashlib.md5(b"https://podcasts.files.bbci.co.uk/p02pc9s1.rss").hexdigest()[:12],
        "title": "BBC Learning English Stories",
        "author": "BBC Learning English",
        "description": (
            "Classic stories retold in clear, simple English. Each episode"
            " teaches vocabulary through short dramas perfect for beginners."
        ),
        "feed_url": "https://podcasts.files.bbci.co.uk/p02pc9s1.rss",
        "artwork_url": "http://ichef.bbci.co.uk/images/ic/3000x3000/p0hxqksj.jpg",
        "episode_count": 100,
        "categories": ["education", "stories"],
        "cefr_level": "A1",
        "language": "en",
    },
    {
        "id": hashlib.md5(b"https://podcasts.files.bbci.co.uk/p02pc9tn.rss").hexdigest()[:12],
        "title": "BBC 6 Minute English",
        "author": "BBC Learning English",
        "description": (
            "Every week we ask an interesting question about the world and discuss"
            " the answer in easy English. With vocabulary explanations."
        ),
        "feed_url": "https://podcasts.files.bbci.co.uk/p02pc9tn.rss",
        "artwork_url": "http://ichef.bbci.co.uk/images/ic/3000x3000/p0hxqkd0.jpg",
        "episode_count": 500,
        "categories": ["education", "learning"],
        "cefr_level": "A2",
        "language": "en",
    },
    # B1-B2 — normal conversational speed
    {
        "id": hashlib.md5(b"https://learningenglish.voanews.com/podcast/?zoneId=1689&pod_play_count=20").hexdigest()[:12],
        "title": "VOA Learning English",
        "author": "Voice of America",
        "description": (
            "Clear, slow-paced English news and stories using limited vocabulary."
            " Formerly VOA Special English — perfect for building fluency."
        ),
        "feed_url": "https://learningenglish.voanews.com/podcast/?zoneId=1689&pod_play_count=20",
        "artwork_url": "https://gdb.voanews.com/0684e143-ca54-4c31-bbc7-c26e19b2fb70.jpg",
        "episode_count": 250,
        "categories": ["education", "news"],
        "cefr_level": "B1",
        "language": "en",
    },
    {
        "id": hashlib.md5(b"https://feeds.feedburner.com/businessenglishpod").hexdigest()[:12],
        "title": "Business English Pod",
        "author": "Business English Pod",
        "description": (
            "Professional English for the workplace — presentations, meetings,"
            " negotiations, and everyday business communication skills."
        ),
        "feed_url": "https://feeds.feedburner.com/businessenglishpod",
        "artwork_url": "https://www.businessenglishpod.com/wordpress/wp-content/uploads/Business-English-Pod-iTunes-3000.jpeg",
        "episode_count": 350,
        "categories": ["education", "business"],
        "cefr_level": "B2",
        "language": "en",
    },
    # C1-C2 — native speed, complex topics
    {
        "id": hashlib.md5(b"https://feeds.npr.org/510298/podcast.xml").hexdigest()[:12],
        "title": "TED Radio Hour",
        "author": "NPR",
        "description": (
            "Idea-driven stories inspired by TED Talks, exploring the most"
            " profound questions of our time with the world's greatest thinkers."
        ),
        "feed_url": "https://feeds.npr.org/510298/podcast.xml",
        "artwork_url": "https://media.npr.org/assets/img/2022/09/23/ted-radio-hour_tile_npr-network-01_sq-3ca507bd2dfa5c26d7db5b41c2b981b24a8789fa.jpg?s=1400&c=66&f=jpg",
        "episode_count": 300,
        "categories": ["education", "technology", "society"],
        "cefr_level": "C1",
        "language": "en",
    },
    {
        "id": hashlib.md5(b"https://feeds.npr.org/500005/podcast.xml").hexdigest()[:12],
        "title": "NPR News Now",
        "author": "NPR",
        "description": (
            "Up-to-the-minute news from NPR, delivered at native English speed"
            " by professional broadcast journalists."
        ),
        "feed_url": "https://feeds.npr.org/500005/podcast.xml",
        "artwork_url": "https://media.npr.org/assets/img/2023/01/24/npr-news-now_tile_sq-2334a5fd44563fa94cdcdb27384b0f05987c2d15.jpg?s=1400&c=66&f=jpg",
        "episode_count": 3650,
        "categories": ["news"],
        "cefr_level": "C2",
        "language": "en",
    },
]

CURATED_CATEGORIES = [
    {"id": "A1-A2", "label": "Beginner (A1-A2)", "description": "Slow, clear speech — perfect for new learners"},
    {"id": "B1-B2", "label": "Intermediate (B1-B2)", "description": "Normal conversational speed with some idioms"},
    {"id": "C1-C2", "label": "Advanced (C1-C2)", "description": "Native speed with complex vocabulary"},
]


def _proxy_podcast_urls(podcast: dict, request: Request) -> dict:
    """Rewrite podcast artwork_url to go through backend proxy to avoid CORS."""
    proxied = podcast.copy()
    artwork_url = podcast.get("artwork_url")
    if artwork_url:
        base_url = str(request.base_url).rstrip("/")
        api_prefix = settings.API_V1_PREFIX.strip("/")
        podcasts_prefix = router.prefix.strip("/")
        path_prefix = f"{api_prefix}/{podcasts_prefix}".strip("/")
        proxied["artwork_url"] = f"{base_url}/{path_prefix}/proxy/image?url={quote(artwork_url)}"
    return proxied


# CORS header included on every proxy response so browsers can load images even
# when app-level CORS middleware is disabled (edge handles it for the API, but
# edge proxies often strip CORS from error responses like 502/404/403).
_PROXY_CORS = {"Access-Control-Allow-Origin": "*"}


@router.get("/proxy/image", summary="Proxy podcast artwork images to bypass CORS")
async def proxy_image(url: str = Query(..., description="The image URL to proxy")):
    """
    Proxy podcast artwork images from any public host to bypass browser CORS.
    Includes SSRF protection and validates that the content is an image.
    """
    try:
        parsed_url = urlparse(url)
        if parsed_url.scheme not in ("http", "https"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Only HTTP/HTTPS image URLs are allowed.",
                headers=_PROXY_CORS,
            )
        host = (parsed_url.hostname or "").lower()

        # SSRF protection: block private/local hosts
        private_prefixes = ("localhost", "127.", "0.0.0.0", "10.", "192.168.", "172.16.",
                            "172.17.", "172.18.", "172.19.", "172.20.", "172.21.",
                            "172.22.", "172.23.", "172.24.", "172.25.", "172.26.",
                            "172.27.", "172.28.", "172.29.", "172.30.", "172.31.",
                            "169.254.", "fc00", "fd", "fe80")
        if any(host == p or host.startswith(p) for p in private_prefixes):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Internal/private URLs are not allowed.",
                headers=_PROXY_CORS,
            )

        # Resolve hostname and verify the IP is public
        from ipaddress import ip_address
        import socket
        try:
            resolved_ip = socket.getaddrinfo(host, None, socket.AF_UNSPEC, socket.SOCK_STREAM)[0][4][0]
            if ip_address(resolved_ip).is_private or ip_address(resolved_ip).is_loopback:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Internal/private URLs are not allowed.",
                    headers=_PROXY_CORS,
                )
        except (socket.gaierror, ValueError):
            pass  # DNS resolution failed or invalid IP, httpx will fail

    except HTTPException:
        raise
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid URL.",
            headers=_PROXY_CORS,
        )

    # 5s timeout — keeps FastAPI response time below nginx's proxy_read_timeout
    # so the 502 is generated by FastAPI (with CORS headers) not by nginx (without).
    async with httpx.AsyncClient(timeout=5.0) as client:
        try:
            resp = await client.get(
                url,
                # Browser-like UA avoids 403 from CDNs that block non-browser clients.
                headers={
                    "User-Agent": (
                        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                        "AppleWebKit/537.36 (KHTML, like Gecko) "
                        "Chrome/120.0.0.0 Safari/537.36"
                    ),
                    "Accept": "image/webp,image/avif,image/*,*/*;q=0.8",
                },
                follow_redirects=True
            )
            if resp.status_code != 200:
                raise HTTPException(
                    status_code=resp.status_code,
                    detail=f"Failed to fetch image: HTTP {resp.status_code}",
                    headers=_PROXY_CORS,
                )

            # Content-type check: only allow images
            content_type = resp.headers.get("content-type", "")
            if content_type and not content_type.startswith("image/"):
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="URL did not return an image content type.",
                    headers=_PROXY_CORS,
                )

            return Response(
                content=resp.content,
                media_type=content_type or "image/jpeg",
                headers={
                    **_PROXY_CORS,
                    "Cache-Control": "public, max-age=86400",
                },
            )
        except HTTPException:
            raise
        except Exception as e:
            logger.error("Error proxying podcast image %s: %s", url, e)
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Image proxy error",
                headers=_PROXY_CORS,
            )


# ============================================================================
# 1. Search Podcasts
# ============================================================================

@router.get("/search")
async def search_podcasts(
    request: Request,
    q: str = Query(..., description="Search query"),
    max_results: int = Query(10, ge=1, le=50, description="Max number of results"),
    db: AsyncSession = Depends(get_db),
):
    """
    Search for podcasts by keyword via PodcastIndex.org.

    Flow:
    1. Build HMAC-SHA1 auth headers for PodcastIndex
    2. Call /search/byterm
    3. Normalize and estimate CEFR level per podcast
    4. Cache: Redis 3h, DB 24h

    Public endpoint — no authentication required.
    """
    if not settings.PODCASTINDEX_KEY or not settings.PODCASTINDEX_SECRET:
        logger.warning("PodcastIndex API keys not configured, falling back to curated list.")
        grouped = _group_curated_by_cefr()
        proxied_curated = [_proxy_podcast_urls(p, request) for p in CURATED_PODCASTS]
        return {
            "podcasts": proxied_curated,
            "source": "curated_fallback",
            "is_stale": False,
            "note": "PodcastIndex API not configured. Showing curated list.",
            "categories": grouped,
        }

    q_normalized = q.strip().lower()
    cache_key = f"podcasts:search:{hashlib.md5(f'{q_normalized}:{max_results}'.encode()).hexdigest()[:16]}"
    cache_service = APICacheService(db)

    try:
        result = await cache_service.get_or_fetch(
            cache_key=cache_key,
            api_name="podcastindex",
            fetch_fn=lambda: _fetch_podcast_search(q=q, max_results=max_results),
            priority=Priority.MEDIUM,
            redis_ttl=10800,    # 3 hours
            db_ttl=86400,       # 24 hours
        )

        podcasts = result.data.get("podcasts", [])
        proxied_podcasts = []
        for podcast in podcasts:
            p_copy = podcast.copy()
            if "cefr_level" not in p_copy or not p_copy["cefr_level"]:
                p_copy["cefr_level"] = _estimate_cefr(p_copy.get("description", ""))
            p_copy["cefr_info"] = CEFR_LEVELS.get(p_copy["cefr_level"], {})
            proxied_podcasts.append(_proxy_podcast_urls(p_copy, request))

        return {
            "podcasts": proxied_podcasts,
            "source": result.source,
            "is_stale": result.is_stale,
        }

    except QuotaExhaustedError as e:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=str(e),
            headers={"Retry-After": e.reset_time},
        )
    except QuotaNearLimitError as e:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=str(e),
        )


# ============================================================================
# 2. Curated Podcast List
# ============================================================================

@router.get("/curated")
async def get_curated_podcasts(request: Request):
    """
    Return a handpicked list of English-learning podcasts grouped by CEFR level.

    No external API call — static data, no rate limiting needed.
    Returns podcasts in each CEFR band with category metadata.
    """
    grouped = _group_curated_by_cefr()
    proxied_curated = [_proxy_podcast_urls(p, request) for p in CURATED_PODCASTS]
    return {
        "podcasts": proxied_curated,
        "categories": grouped,
    }


# ============================================================================
# 3. Podcast Episodes from RSS Feed
# ============================================================================

@router.get("/episodes")
async def get_podcast_episodes(
    request: Request,
    feed_url: str = Query(..., description="RSS feed URL (URL-encoded)"),
    limit: int = Query(20, ge=1, le=50, description="Number of episodes to return"),
    db: AsyncSession = Depends(get_db),
):
    """
    Fetch episode list by parsing the podcast's RSS feed directly.

    No API quota consumed — RSS feeds are freely accessible.
    Uses feedparser if installed; falls back to httpx + xml.etree.ElementTree.

    Cache: Redis 3h, DB 24h.
    Public endpoint — no authentication required.
    """
    feed_url = feed_url.strip()

    # SSRF protection: only allow public HTTP/HTTPS URLs
    _parsed = urlparse(feed_url)
    if _parsed.scheme not in ("http", "https"):
        raise HTTPException(status_code=400, detail="Only HTTP/HTTPS feed URLs are allowed")
    _host = (_parsed.hostname or "").lower()
    # Use ipaddress module for robust private IP detection
    from ipaddress import ip_address
    import socket
    _private_prefixes = ("localhost", "127.", "0.0.0.0", "10.", "192.168.", "172.16.",
                         "172.17.", "172.18.", "172.19.", "172.20.", "172.21.",
                         "172.22.", "172.23.", "172.24.", "172.25.", "172.26.",
                         "172.27.", "172.28.", "172.29.", "172.30.", "172.31.",
                         "169.254.", "fc00", "fd", "fe80")
    if any(_host == p or _host.startswith(p) for p in _private_prefixes):
        raise HTTPException(status_code=400, detail="Internal/private feed URLs are not allowed")
    # Additional check: resolve hostname and verify the IP is public
    try:
        resolved_ip = socket.getaddrinfo(_host, None, socket.AF_UNSPEC, socket.SOCK_STREAM)[0][4][0]
        if ip_address(resolved_ip).is_private or ip_address(resolved_ip).is_loopback:
            raise HTTPException(status_code=400, detail="Internal/private feed URLs are not allowed")
    except (socket.gaierror, ValueError):
        pass  # Allow if DNS resolution fails—httpx will handle the error

    cache_key = f"podcasts:episodes:{hashlib.md5(f'{feed_url}:{limit}'.encode()).hexdigest()[:16]}"
    cache_service = APICacheService(db)

    try:
        result = await cache_service.get_or_fetch(
            cache_key=cache_key,
            api_name="rss_feed",
            fetch_fn=lambda: _fetch_rss_episodes(feed_url=feed_url, limit=limit),
            priority=Priority.MEDIUM,
            redis_ttl=10800,    # 3 hours
            db_ttl=86400,       # 24 hours
        )

        episodes = result.data.get("episodes", [])
        base_url = str(request.base_url).rstrip("/")
        api_prefix = settings.API_V1_PREFIX.strip("/")
        podcasts_prefix = router.prefix.strip("/")
        path_prefix = f"{api_prefix}/{podcasts_prefix}".strip("/")

        proxied_episodes = []
        for ep in episodes:
            proxied_ep = ep.copy()
            img_url = ep.get("image_url")
            if img_url:
                proxied_ep["image_url"] = f"{base_url}/{path_prefix}/proxy/image?url={quote(img_url)}"
            proxied_episodes.append(proxied_ep)

        return {
            "episodes": proxied_episodes,
            "podcast_title": result.data.get("podcast_title", ""),
            "podcast_description": result.data.get("podcast_description", ""),
            "feed_url": feed_url,
            "source": result.source,
            "is_stale": result.is_stale,
        }

    except QuotaExhaustedError as e:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=str(e),
            headers={"Retry-After": e.reset_time},
        )
    except QuotaNearLimitError as e:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=str(e),
        )
    except httpx.TimeoutException:
        logger.warning(f"RSS feed timed out: {feed_url}")
        raise HTTPException(
            status_code=status.HTTP_504_GATEWAY_TIMEOUT,
            detail=f"RSS feed timed out after 20 seconds: {feed_url}",
        )
    except httpx.HTTPStatusError as e:
        logger.warning(f"RSS feed HTTP error {e.response.status_code}: {feed_url}")
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"RSS feed returned HTTP {e.response.status_code}",
        )
    except Exception as e:
        logger.error(f"Failed to fetch podcast episodes from {feed_url}: {e}")
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Failed to fetch RSS feed: {str(e)}",
        )


# ============================================================================
# 4. Transcript
# ============================================================================

def _find_episode_for_transcript(
    episodes: list[dict],
    episode_guid: str,
    audio_url: str,
) -> dict | None:
    for episode in episodes:
        if str(episode.get("guid") or "") == episode_guid:
            return episode
        if audio_url and str(episode.get("audio_url") or "") == audio_url:
            return episode
    return None


def _build_transcript_artifact(
    *,
    feed_url: str,
    episode_guid: str,
    audio_url: str,
    episode: dict | None = None,
) -> dict:
    """Build a cached learner transcript from RSS metadata.

    This is intentionally synchronous and cheap. A later background worker can
    replace `source=rss_summary` with an STT artifact while preserving fields.
    """
    title = _strip_html((episode or {}).get("title") or "Podcast episode")
    description = _strip_html((episode or {}).get("description") or "")
    duration_seconds = int((episode or {}).get("duration_seconds") or 0)

    summary = description or (
        "Transcript audio is not available yet, but this episode can still be "
        "used for listening practice with the notes below."
    )
    summary = re.sub(r"\s+", " ", summary).strip()
    if len(summary) > 900:
        summary = f"{summary[:897]}..."

    segments = [
        {
            "start_seconds": 0,
            "end_seconds": min(duration_seconds, 45) if duration_seconds else 45,
            "speaker": "host",
            "text": f"Episode focus: {title}.",
        },
        {
            "start_seconds": 45 if duration_seconds > 45 else 0,
            "end_seconds": min(duration_seconds, 180) if duration_seconds else 180,
            "speaker": "host",
            "text": summary,
        },
        {
            "start_seconds": min(duration_seconds, 180) if duration_seconds else 180,
            "end_seconds": duration_seconds if duration_seconds > 180 else 240,
            "speaker": "learning_note",
            "text": (
                "Listen once for the main idea, then replay short sections and "
                "write down useful phrases before checking the episode notes."
            ),
        },
    ]

    transcript = "\n\n".join(segment["text"] for segment in segments if segment["text"])
    return {
        "message": "Transcript generated from episode metadata",
        "status": "ready",
        "feed_url": feed_url,
        "episode_guid": episode_guid,
        "audio_url": audio_url,
        "title": title,
        "transcript": transcript,
        "segments": segments,
        "duration_seconds": duration_seconds,
        "source": "rss_summary" if episode else "request_metadata",
        "requires_stt": False,
    }

@router.post("/transcript")
async def generate_transcript(
    feed_url: str = Body(..., description="RSS feed URL"),
    episode_guid: str = Body(..., description="Episode GUID"),
    audio_url: str = Body(..., description="Direct audio file URL"),
    db: AsyncSession = Depends(get_db),
):
    """
    Get or generate a transcript artifact for a podcast episode.

    Phase 1 uses RSS metadata to create a learner-facing transcript artifact
    quickly. Full audio download + STT can replace the artifact source later.
    """
    fingerprint = hashlib.sha1(
        f"{feed_url}|{episode_guid}|{audio_url}".encode("utf-8")
    ).hexdigest()[:16]
    cache_key = f"podcasts:transcript:{fingerprint}"
    cache_service = APICacheService(db)

    async def _generate() -> dict:
        episode: dict | None = None
        try:
            feed = await _fetch_rss_episodes(feed_url=feed_url, limit=50)
            episode = _find_episode_for_transcript(
                feed.get("episodes", []),
                episode_guid=episode_guid,
                audio_url=audio_url,
            )
        except Exception as exc:
            logger.info("Podcast transcript RSS lookup skipped for %s: %s", episode_guid, exc)

        return _build_transcript_artifact(
            feed_url=feed_url,
            episode_guid=episode_guid,
            audio_url=audio_url,
            episode=episode,
        )

    try:
        result = await cache_service.get_or_fetch(
            cache_key=cache_key,
            api_name="podcasts_transcript",
            fetch_fn=_generate,
            priority=Priority.LOW,
            redis_ttl=86400,
            db_ttl=2592000,
        )
        return result.data
    except Exception as e:
        logger.error("Podcast transcript error for %s: %s", episode_guid, e)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Podcast transcript temporarily unavailable.",
        )


# ============================================================================
# Internal — PodcastIndex API
# ============================================================================

def _build_podcastindex_headers() -> dict:
    """
    Build HMAC-SHA1 authentication headers for PodcastIndex API.

    Required headers:
      X-Auth-Date    — current Unix timestamp (str)
      X-Auth-Key     — API key
      Authorization  — SHA1(api_key + api_secret + unix_timestamp)
    """
    api_key = settings.PODCASTINDEX_KEY
    api_secret = settings.PODCASTINDEX_SECRET
    epoch = str(int(time.time()))

    hash_input = f"{api_key}{api_secret}{epoch}".encode("utf-8")
    auth_hash = hashlib.sha1(hash_input).hexdigest()

    return {
        "X-Auth-Date": epoch,
        "X-Auth-Key": api_key,
        "Authorization": auth_hash,
        "User-Agent": "LexiLingo/1.0",
    }


async def _fetch_podcast_search(q: str, max_results: int) -> dict:
    """Call PodcastIndex /search/byterm and normalize results."""
    headers = _build_podcastindex_headers()
    params = {"q": q, "max": max_results}

    async with httpx.AsyncClient(timeout=15.0) as client:
        response = await client.get(
            f"{PODCASTINDEX_BASE}/search/byterm",
            headers=headers,
            params=params,
        )
        response.raise_for_status()
        data = response.json()

    if data.get("status") != "true" and data.get("status") is not True:
        raise Exception(f"PodcastIndex error: {data.get('description', 'Unknown')}")

    podcasts = []
    for item in data.get("feeds", []):
        podcast_id = (
            str(item.get("podcastGuid", ""))
            or hashlib.md5((item.get("url", "")).encode()).hexdigest()[:12]
        )
        podcasts.append({
            "id": podcast_id,
            "title": item.get("title", ""),
            "author": item.get("author", ""),
            "description": _strip_html(item.get("description", "")),
            "feed_url": item.get("url", ""),
            "artwork_url": item.get("artwork", "") or item.get("image", ""),
            "episode_count": item.get("episodeCount", 0),
            "categories": list(item.get("categories", {}).values()) if item.get("categories") else [],
            "cefr_level": None,    # estimated post-fetch
            "language": item.get("language", "en"),
        })

    return {"podcasts": podcasts}


# ============================================================================
# Internal — RSS Feed Parsing
# ============================================================================

async def _fetch_rss_episodes(feed_url: str, limit: int) -> dict:
    """
    Fetch and parse a podcast RSS feed.

    Tries feedparser first (richer parsing); falls back to httpx +
    xml.etree.ElementTree when feedparser is not installed.
    """
    try:
        import feedparser  # type: ignore
        return await _parse_with_feedparser(feed_url, limit)
    except ImportError:
        logger.debug("feedparser not available, using xml.etree.ElementTree fallback")
        return await _parse_with_elementtree(feed_url, limit)


async def _parse_with_feedparser(feed_url: str, limit: int) -> dict:
    """Parse RSS feed using feedparser library."""
    import feedparser  # type: ignore

    # feedparser is synchronous — run in executor to avoid blocking event loop
    import asyncio
    loop = asyncio.get_event_loop()
    feed = await loop.run_in_executor(None, feedparser.parse, feed_url)

    podcast_title = feed.feed.get("title", "")
    podcast_description = _strip_html(feed.feed.get("summary", "") or feed.feed.get("description", ""))

    episodes = []
    for entry in feed.entries[:limit]:
        # Locate audio enclosure
        audio_url = ""
        for enc in entry.get("enclosures", []):
            if enc.get("type", "").startswith("audio"):
                audio_url = enc.get("href", "") or enc.get("url", "")
                break

        # Duration
        duration_str = entry.get("itunes_duration", "") or ""
        duration_seconds = _parse_duration(duration_str)

        # Published date
        published_at = ""
        if entry.get("published_parsed"):
            try:
                epoch = calendar.timegm(entry.published_parsed)
                published_at = datetime.fromtimestamp(epoch, tz=timezone.utc).isoformat()
            except Exception:
                pass
        
        if not published_at and entry.get("updated_parsed"):
            try:
                epoch = calendar.timegm(entry.updated_parsed)
                published_at = datetime.fromtimestamp(epoch, tz=timezone.utc).isoformat()
            except Exception:
                pass

        if not published_at:
            raw_date = entry.get("published") or entry.get("updated") or ""
            if raw_date:
                try:
                    dt = parsedate_to_datetime(raw_date)
                    published_at = dt.isoformat()
                except Exception:
                    published_at = raw_date

        # Episode number
        ep_number_raw = entry.get("itunes_episode", None)
        episode_number = int(ep_number_raw) if ep_number_raw else None

        episodes.append({
            "guid": entry.get("id", "") or entry.get("link", ""),
            "title": entry.get("title", ""),
            "audio_url": audio_url,
            "duration_seconds": duration_seconds,
            "published_at": published_at,
            "description": _strip_html(entry.get("summary", "") or entry.get("description", "")),
            "episode_number": episode_number,
            "image_url": entry.get("image", {}).get("href", "") if isinstance(entry.get("image"), dict) else None,
            "cefr_level": None,
        })

    return {
        "episodes": episodes,
        "podcast_title": podcast_title,
        "podcast_description": podcast_description,
    }


async def _parse_with_elementtree(feed_url: str, limit: int) -> dict:
    """Parse RSS feed using httpx fetch + xml.etree.ElementTree fallback."""
    async with httpx.AsyncClient(timeout=20.0, follow_redirects=True) as client:
        response = await client.get(
            feed_url,
            headers={"User-Agent": "LexiLingo/1.0 RSS Reader"},
        )
        response.raise_for_status()
        xml_content = response.text

    try:
        root = ET.fromstring(xml_content)
    except ET.ParseError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Failed to parse RSS feed XML: {exc}",
        )

    # Namespaces commonly found in podcast RSS
    ns = {
        "itunes": "http://www.itunes.com/dtds/podcast-1.0.dtd",
        "content": "http://purl.org/rss/1.0/modules/content/",
    }

    channel = root.find("channel")
    if channel is None:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="RSS feed does not contain a <channel> element.",
        )

    podcast_title = _elem_text(channel, "title")
    podcast_description = _strip_html(
        _elem_text(channel, "description")
        or _elem_text(channel, "itunes:summary", ns)
    )

    episodes = []
    for item in channel.findall("item")[:limit]:
        # Enclosure (audio URL)
        audio_url = ""
        enclosure = item.find("enclosure")
        if enclosure is not None:
            mime = enclosure.get("type", "")
            if "audio" in mime or not mime:
                audio_url = enclosure.get("url", "")

        # Duration
        duration_str = _elem_text(item, "itunes:duration", ns) or ""
        duration_seconds = _parse_duration(duration_str)

        # Episode number
        ep_num_str = _elem_text(item, "itunes:episode", ns)
        episode_number = int(ep_num_str) if ep_num_str and ep_num_str.isdigit() else None

        # Image
        image_elem = item.find("itunes:image", ns)
        image_url = image_elem.get("href", "") if image_elem is not None else None

        # Description — prefer itunes:summary over description for plain text
        raw_desc = (
            _elem_text(item, "itunes:summary", ns)
            or _elem_text(item, "description")
            or ""
        )

        raw_date = _elem_text(item, "pubDate") or ""
        published_at = ""
        if raw_date:
            try:
                dt = parsedate_to_datetime(raw_date)
                published_at = dt.isoformat()
            except Exception:
                published_at = raw_date

        episodes.append({
            "guid": _elem_text(item, "guid") or _elem_text(item, "link") or "",
            "title": _elem_text(item, "title") or "",
            "audio_url": audio_url,
            "duration_seconds": duration_seconds,
            "published_at": published_at,
            "description": _strip_html(raw_desc),
            "episode_number": episode_number,
            "image_url": image_url or None,
            "cefr_level": None,
        })

    return {
        "episodes": episodes,
        "podcast_title": podcast_title,
        "podcast_description": podcast_description,
    }


# ============================================================================
# Internal — Helpers
# ============================================================================

def _elem_text(element, tag: str, ns: Optional[dict] = None) -> str:
    """Safely extract text from an XML element child."""
    child = element.find(tag, ns) if ns else element.find(tag)
    if child is not None and child.text:
        return child.text.strip()
    return ""


def _strip_html(html: str) -> str:
    """Remove HTML tags from a string using a simple regex."""
    if not html:
        return ""
    return re.sub(r"<[^>]+>", "", html).strip()


def _parse_duration(duration_str: str) -> int:
    """
    Convert podcast duration string to total seconds.

    Accepts:
      "HH:MM:SS"  →  hours * 3600 + minutes * 60 + seconds
      "MM:SS"     →  minutes * 60 + seconds
      "SSS"       →  integer seconds (some feeds use bare seconds)
    """
    if not duration_str:
        return 0
    duration_str = duration_str.strip()
    parts = duration_str.split(":")
    try:
        if len(parts) == 3:
            return int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
        elif len(parts) == 2:
            return int(parts[0]) * 60 + int(parts[1])
        elif len(parts) == 1:
            return int(parts[0])
    except (ValueError, IndexError):
        pass
    return 0


def _estimate_cefr(text: str) -> str:
    """
    Estimate CEFR level from a text snippet using simple heuristics.

    Factors: word count, average word length.
    Mirrors the same heuristic used in news.py for consistency.
    In production, replace with AI grading via /ai/grade_text.
    """
    if not text:
        return "B1"

    words = text.split()
    word_count = len(words)
    if word_count == 0:
        return "B1"

    avg_word_length = sum(len(w) for w in words) / word_count
    complexity_score = (avg_word_length - 3) * 10 + (word_count / 50)

    if complexity_score < 10:
        return "A1"
    elif complexity_score < 20:
        return "A2"
    elif complexity_score < 35:
        return "B1"
    elif complexity_score < 50:
        return "B2"
    elif complexity_score < 70:
        return "C1"
    else:
        return "C2"


def _group_curated_by_cefr() -> list:
    """Return curated podcasts grouped by CEFR band for the UI."""
    bands = {
        "A1-A2": [],
        "B1-B2": [],
        "C1-C2": [],
    }
    for podcast in CURATED_PODCASTS:
        level = podcast.get("cefr_level", "B1")
        if level in ("A1", "A2"):
            bands["A1-A2"].append(podcast["id"])
        elif level in ("B1", "B2"):
            bands["B1-B2"].append(podcast["id"])
        else:
            bands["C1-C2"].append(podcast["id"])

    return [
        {**cat, "podcast_ids": bands[cat["id"]]}
        for cat in CURATED_CATEGORIES
    ]
