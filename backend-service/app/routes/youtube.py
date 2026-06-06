"""
YouTube API Routes — Video Search, Captions, and Curated Channels

Proxy endpoints that hide the YouTube Data API v3 key from the client.
All responses are cached via the 3-layer APICacheService.

Phase 1: YouTube Video Integration with Auto Subtitles.
"""

import asyncio
import logging
from typing import Optional
from urllib.parse import quote, urlparse

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
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

router = APIRouter(prefix="/youtube", tags=["YouTube"])

_YOUTUBE_API_ERROR_CODES = {
    400: status.HTTP_400_BAD_REQUEST,
    401: status.HTTP_401_UNAUTHORIZED,
    403: status.HTTP_503_SERVICE_UNAVAILABLE,
    404: status.HTTP_404_NOT_FOUND,
}

YOUTUBE_API_BASE = "https://www.googleapis.com/youtube/v3"


def _raise_youtube_api_error(response: httpx.Response) -> None:
    """Convert a non-200 YouTube API response into an HTTPException."""
    try:
        detail_json = response.json()
        msg = (
            detail_json.get("error", {}).get("message")
            or detail_json.get("error", {}).get("errors", [{}])[0].get("reason")
            or response.text[:200]
        )
    except Exception:
        msg = response.text[:200] or f"HTTP {response.status_code}"

    http_code = _YOUTUBE_API_ERROR_CODES.get(
        response.status_code, status.HTTP_503_SERVICE_UNAVAILABLE
    )
    logger.warning(f"YouTube API error {response.status_code}: {msg}")
    raise HTTPException(status_code=http_code, detail=f"YouTube API: {msg}")


# ============================================================================
# Curated Channel List (No API cost — thumbnails fetched from YouTube API)
# ============================================================================

CURATED_CHANNELS = [
    {
        "id": "UCHaHD477h-FeBbVh9Sh7syA",
        "name": "BBC Learning English",
        "description": "Learn English with the BBC. Improve grammar, vocabulary and pronunciation.",
        "level": "A2-B2",
        "thumbnail": "",
        "category": "general",
    },
    {
        "id": "UCsooa4yRKGN_zEE8iknghZA",
        "name": "TED-Ed",
        "description": "Lessons worth sharing. TED-Ed's commitment to creating lessons worth sharing.",
        "level": "B1-C1",
        "thumbnail": "",
        "category": "academic",
    },
    {
        "id": "UCz4tgANd4yy8Oe0iXCdSWfA",
        "name": "English with Lucy",
        "description": "Learn British English with Lucy. Grammar, vocabulary, and pronunciation.",
        "level": "A2-B2",
        "thumbnail": "",
        "category": "general",
    },
    {
        "id": "UCVBErcpqaokOf4fI5j73K_w",
        "name": "EngVid",
        "description": "Free English video lessons by experienced teachers.",
        "level": "A1-C1",
        "thumbnail": "",
        "category": "general",
    },
    {
        "id": "UCvn_XCl_mgQmt3sD753zdJA",
        "name": "Rachel's English",
        "description": "American English pronunciation training.",
        "level": "B1-C1",
        "thumbnail": "",
        "category": "pronunciation",
    },
    {
        "id": "UCKyTokYo0nK2OA-az-sDijA",
        "name": "VOA Learning English",
        "description": "Practice American English with slow-speed news.",
        "level": "A1-A2",
        "thumbnail": "",
        "category": "news",
    },
]


async def _fetch_channel_thumbnails(channel_ids: list[str]) -> dict[str, str]:
    """
    Fetch real thumbnail URLs for channels via YouTube channels.list API.
    Cost: 1 quota unit per 50 channels (very cheap).
    Returns: dict mapping channel_id -> thumbnail_url
    """
    if not settings.YOUTUBE_API_KEY or not channel_ids:
        return {}

    params = {
        "part": "snippet",
        "id": ",".join(channel_ids),
        "key": settings.YOUTUBE_API_KEY,
    }

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(f"{YOUTUBE_API_BASE}/channels", params=params)
            response.raise_for_status()
            data = response.json()

        thumbnails: dict[str, str] = {}
        for item in data.get("items", []):
            cid = item.get("id", "")
            snippet = item.get("snippet", {})
            # Prefer medium (240px) → default (120px)
            thumb = (
                snippet.get("thumbnails", {}).get("medium", {}).get("url")
                or snippet.get("thumbnails", {}).get("default", {}).get("url")
                or ""
            )
            # Only accept proper YouTube CDN URLs (path must start with /ytc/)
            parsed = urlparse(thumb)
            if cid and thumb and parsed.path.startswith("/ytc/"):
                thumbnails[cid] = thumb
        return thumbnails
    except Exception as e:
        logger.warning(f"Failed to fetch channel thumbnails: {e}")
        return {}


@router.get("/channels")
async def get_curated_channels(
    request: Request,
    category: Optional[str] = Query(None, description="Filter by category"),
    db: AsyncSession = Depends(get_db),
):
    """
    Get curated English learning YouTube channels with real thumbnails.

    Thumbnails are fetched from YouTube channels.list (1 quota unit, cached 7 days).
    Thumbnails are rewritten through the image proxy to avoid CORS issues in browsers.
    """
    channels = CURATED_CHANNELS
    if category:
        channels = [c for c in channels if c["category"] == category]

    # Fetch real thumbnails via cache
    cache_key = "youtube:channel_thumbnails:all:v4"
    cache_service = APICacheService(db)
    channel_ids = [c["id"] for c in CURATED_CHANNELS]  # always fetch all for cache

    try:
        thumb_result = await cache_service.get_or_fetch(
            cache_key=cache_key,
            api_name="youtube",
            fetch_fn=lambda: _fetch_channel_thumbnails(channel_ids),
            priority=Priority.LOW,
            redis_ttl=604800,   # 7 days
            db_ttl=2592000,     # 30 days
        )
        thumbnails: dict = thumb_result.data if thumb_result else {}
    except Exception:
        thumbnails = {}

    # Build proxy base for rewriting yt3 thumbnail URLs through the image proxy.
    base_url = str(request.base_url).rstrip("/")
    api_prefix = settings.API_V1_PREFIX.strip("/")

    def _proxy_thumbnail(url: str) -> str:
        if not url:
            return ""
        # Reject stale/malformed yt3 URLs — real YouTube CDN paths start with /ytc/
        parsed = urlparse(url)
        if "googleusercontent.com" in parsed.netloc and not parsed.path.startswith("/ytc/"):
            logger.warning("Rejected malformed thumbnail URL: %s", url)
            return ""
        return f"{base_url}/{api_prefix}/podcasts/proxy/image?url={quote(url)}"

    # Merge real thumbnails into channel data, proxying through the image endpoint.
    enriched = []
    for ch in channels:
        raw_thumb = thumbnails.get(ch["id"], "")
        enriched.append({
            **ch,
            "thumbnail": _proxy_thumbnail(raw_thumb),
        })

    return {
        "channels": enriched,
        "total": len(enriched),
    }


# ============================================================================
# Video Search (100 units per search.list call)
# ============================================================================

def _proxy_url(url: str, request: Request) -> str:
    if not url:
        return ""
    if "youtube.com" in url or "ytimg.com" in url or "googleusercontent.com" in url:
        base_url = str(request.base_url).rstrip("/")
        api_prefix = settings.API_V1_PREFIX.strip("/")
        return f"{base_url}/{api_prefix}/podcasts/proxy/image?url={quote(url)}"
    return url


@router.get("/search")
async def search_videos(
    request: Request,
    q: str = Query(..., min_length=2, max_length=200, description="Search query"),
    max_results: int = Query(10, ge=1, le=25),
    channel_id: Optional[str] = Query(None, description="Filter by channel ID"),
    page_token: Optional[str] = Query(None, description="Pagination token"),
    db: AsyncSession = Depends(get_db),
):
    """
    Search YouTube videos (proxied through backend to hide API key).

    Quota cost: 100 units per search.list call.
    Cache: Redis 6h, DB 12h, SQLite 24h on client.
    """
    if not settings.YOUTUBE_API_KEY:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="YouTube API key not configured.",
        )

    cache_parts = [f"q:{q}", f"max:{max_results}"]
    if channel_id:
        cache_parts.append(f"ch:{channel_id}")
    if page_token:
        cache_parts.append(f"page:{page_token}")
    cache_key = f"youtube:search:{':'.join(cache_parts)}"

    cache_service = APICacheService(db)

    try:
        result = await cache_service.get_or_fetch(
            cache_key=cache_key,
            api_name="youtube",
            fetch_fn=lambda: _youtube_search(
                q=q,
                max_results=max_results,
                channel_id=channel_id,
                page_token=page_token,
            ),
            priority=Priority.HIGH,
            redis_ttl=21600,    # 6 hours
            db_ttl=43200,       # 12 hours
        )
        data_copy = dict(result.data) if result and result.data else {}
        if "videos" in data_copy:
            data_copy["videos"] = [
                {
                    **video,
                    "thumbnail_url": _proxy_url(video.get("thumbnail_url", ""), request),
                    "thumbnail_medium": _proxy_url(video.get("thumbnail_medium", ""), request),
                }
                for video in data_copy["videos"]
            ]
        return {
            "data": data_copy,
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
    except HTTPException:
        raise
    except httpx.TimeoutException:
        raise HTTPException(
            status_code=status.HTTP_504_GATEWAY_TIMEOUT,
            detail="YouTube API request timed out.",
        )
    except Exception as e:
        logger.error(f"Unexpected error in YouTube search: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="YouTube service temporarily unavailable.",
        )


# ============================================================================
# Video Captions — via youtube-transcript-api (no OAuth needed)
# ============================================================================

@router.get("/captions/{video_id}")
async def get_captions(
    video_id: str,
    lang: str = Query("en", description="Caption language code"),
    db: AsyncSession = Depends(get_db),
):
    """
    Fetch captions/subtitles for a YouTube video.

    Uses youtube-transcript-api (no OAuth, no quota cost).
    Cache: 7 days Redis, 1 year DB (captions rarely change).

    Returns list of caption segments with start/end times.
    """
    cache_key = f"youtube:captions:{video_id}:{lang}"
    cache_service = APICacheService(db)

    try:
        result = await cache_service.get_or_fetch(
            cache_key=cache_key,
            api_name="youtube",
            fetch_fn=lambda: _fetch_captions_transcript_api(video_id, lang),
            priority=Priority.HIGH,
            redis_ttl=604800,       # 7 days
            db_ttl=31536000,        # 1 year
        )
        return {
            "video_id": video_id,
            "language": lang,
            "segments": result.data if result else [],
            "source": result.source if result else "error",
            "is_stale": result.is_stale if result else False,
        }
    except QuotaExhaustedError as e:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=str(e),
        )


# ============================================================================
# Channel Videos (100 units per search.list)
# ============================================================================

async def _fetch_channel_videos_from_playlist(
    channel_id: str,
    max_results: int = 10,
    page_token: Optional[str] = None,
) -> dict:
    """
    Fetch channel videos from its uploads playlist (much cheaper than search).
    """
    if len(channel_id) > 1 and channel_id[1] == 'C':
        playlist_id = channel_id[0] + 'U' + channel_id[2:]
    else:
        playlist_id = channel_id

    params = {
        "part": "snippet",
        "playlistId": playlist_id,
        "maxResults": max_results,
        "key": settings.YOUTUBE_API_KEY,
    }
    if page_token:
        params["pageToken"] = page_token

    async with httpx.AsyncClient(timeout=15.0) as client:
        response = await client.get(f"{YOUTUBE_API_BASE}/playlistItems", params=params)
        if response.status_code != 200:
            logger.info(f"playlistItems failed for {channel_id}, falling back to search: {response.text[:200]}")
            return await _youtube_search(
                q="",
                max_results=max_results,
                channel_id=channel_id,
                page_token=page_token,
                require_captions=False,
            )
        data = response.json()

    videos = []
    for item in data.get("items", []):
        snippet = item.get("snippet", {})
        video_id = snippet.get("resourceId", {}).get("videoId", "")
        if not video_id:
            continue
        videos.append({
            "video_id": video_id,
            "title": snippet.get("title", ""),
            "description": snippet.get("description", ""),
            "channel_title": snippet.get("channelTitle", ""),
            "channel_id": snippet.get("channelId", ""),
            "published_at": snippet.get("publishedAt", ""),
            "thumbnail_url": snippet.get("thumbnails", {}).get("high", {}).get("url", ""),
            "thumbnail_medium": snippet.get("thumbnails", {}).get("medium", {}).get("url", ""),
        })

    return {
        "videos": videos,
        "next_page_token": data.get("nextPageToken"),
        "prev_page_token": data.get("prevPageToken"),
        "total_results": data.get("pageInfo", {}).get("totalResults", 0),
    }


@router.get("/channels/{channel_id}/videos")
async def get_channel_videos(
    request: Request,
    channel_id: str,
    max_results: int = Query(10, ge=1, le=50),
    page_token: Optional[str] = Query(None),
    db: AsyncSession = Depends(get_db),
):
    """
    Get latest videos from a specific YouTube channel.

    Quota cost: 100 units.
    Cache: Redis 12h, DB 24h.
    """
    if not settings.YOUTUBE_API_KEY:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="YouTube API key not configured.",
        )

    cache_parts = [f"ch:{channel_id}", f"max:{max_results}"]
    if page_token:
        cache_parts.append(f"page:{page_token}")
    cache_key = f"youtube:channel_videos:{':'.join(cache_parts)}"

    cache_service = APICacheService(db)

    try:
        result = await cache_service.get_or_fetch(
            cache_key=cache_key,
            api_name="youtube",
            fetch_fn=lambda: _fetch_channel_videos_from_playlist(
                channel_id=channel_id,
                max_results=max_results,
                page_token=page_token,
            ),
            priority=Priority.MEDIUM,
            redis_ttl=43200,    # 12 hours
            db_ttl=86400,       # 24 hours
        )
        data_copy = dict(result.data) if result and result.data else {}
        if "videos" in data_copy:
            data_copy["videos"] = [
                {
                    **video,
                    "thumbnail_url": _proxy_url(video.get("thumbnail_url", ""), request),
                    "thumbnail_medium": _proxy_url(video.get("thumbnail_medium", ""), request),
                }
                for video in data_copy["videos"]
            ]
        return {
            "channel_id": channel_id,
            "data": data_copy,
            "source": result.source,
            "is_stale": result.is_stale,
        }
    except (QuotaExhaustedError, QuotaNearLimitError) as e:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=str(e),
        )
    except HTTPException:
        raise
    except httpx.TimeoutException:
        raise HTTPException(
            status_code=status.HTTP_504_GATEWAY_TIMEOUT,
            detail="YouTube API request timed out.",
        )
    except Exception as e:
        logger.error(f"Unexpected error fetching channel videos {channel_id}: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="YouTube service temporarily unavailable.",
        )


# ============================================================================
# Word Translate / Dictionary Lookup (Free — no API key needed)
# ============================================================================

@router.get("/translate")
async def translate_word(
    word: str = Query(..., min_length=1, max_length=100),
    lang: str = Query("vi", description="Target language code (e.g. vi, fr, ja)"),
    db: AsyncSession = Depends(get_db),
):
    """
    Look up an English word: phonetic + definition + translation.

    Sources (no API keys needed):
    - https://api.dictionaryapi.dev  — English definition, IPA, examples
    - https://api.mymemory.translated.net — free translation (5 000 chars/day)

    Cache: 30-day Redis, 90-day DB (word meanings rarely change).
    Returns gracefully on lookup failure (empty fields, never 4xx/5xx).
    """
    clean_word = word.lower().strip()
    cache_key = f"youtube:translate:{clean_word}:{lang}"
    cache_service = APICacheService(db)

    try:
        result = await cache_service.get_or_fetch(
            cache_key=cache_key,
            api_name="youtube",
            fetch_fn=lambda: _fetch_word_data(clean_word, lang),
            priority=Priority.MEDIUM,
            redis_ttl=2592000,   # 30 days
            db_ttl=7776000,      # 90 days
        )
        return result.data if result else _empty_word_result(clean_word)
    except Exception as e:
        logger.warning(f"Word lookup failed for '{word}': {e}")
        return _empty_word_result(clean_word)


def _empty_word_result(word: str) -> dict:
    return {
        "word": word,
        "translation": "",
        "phonetic": "",
        "part_of_speech": "",
        "definition": "",
        "examples": [],
    }


async def _fetch_word_data(word: str, lang: str = "vi") -> dict:
    """Fetch definition (Free Dictionary API) + translation (MyMemory) concurrently."""
    dict_url = f"https://api.dictionaryapi.dev/api/v2/entries/en/{word}"
    trans_url = "https://api.mymemory.translated.net/get"

    async with httpx.AsyncClient(timeout=10.0) as client:
        dict_resp, trans_resp = await asyncio.gather(
            client.get(dict_url),
            client.get(trans_url, params={"q": word, "langpair": f"en|{lang}"}),
            return_exceptions=True,
        )

    phonetic = ""
    part_of_speech = ""
    definition = ""
    examples: list[str] = []

    if isinstance(dict_resp, httpx.Response) and dict_resp.status_code == 200:
        try:
            entries = dict_resp.json()
            if entries and isinstance(entries, list):
                entry = entries[0]
                phonetic = entry.get("phonetic", "")
                if not phonetic:
                    for p in entry.get("phonetics", []):
                        if p.get("text"):
                            phonetic = p["text"]
                            break
                meanings = entry.get("meanings", [])
                if meanings:
                    m = meanings[0]
                    part_of_speech = m.get("partOfSpeech", "")
                    defs = m.get("definitions", [])
                    if defs:
                        definition = defs[0].get("definition", "")
                    for d in defs[:3]:
                        ex = d.get("example")
                        if ex:
                            examples.append(ex)
        except Exception:
            pass

    translation = ""
    if isinstance(trans_resp, httpx.Response) and trans_resp.status_code == 200:
        try:
            trans_data = trans_resp.json()
            translation = trans_data.get("responseData", {}).get("translatedText", "")
        except Exception:
            pass

    return {
        "word": word,
        "translation": translation,
        "phonetic": phonetic,
        "part_of_speech": part_of_speech,
        "definition": definition,
        "examples": examples,
    }


# ============================================================================
# Internal API Call Functions
# ============================================================================

async def _youtube_search(
    q: str,
    max_results: int = 10,
    channel_id: Optional[str] = None,
    page_token: Optional[str] = None,
    require_captions: bool = True,
) -> dict:
    """Call YouTube Data API v3 search.list endpoint."""
    params: dict = {
        "part": "snippet",
        "type": "video",
        "maxResults": max_results,
        "key": settings.YOUTUBE_API_KEY,
        "relevanceLanguage": "en",
    }
    # Apply caption filter only for keyword searches — not for channel browsing,
    # which would exclude videos with only auto-generated captions.
    if require_captions:
        params["videoCaption"] = "closedCaption"
    if q:
        params["q"] = q
    if channel_id:
        params["channelId"] = channel_id
    if page_token:
        params["pageToken"] = page_token

    async with httpx.AsyncClient(timeout=15.0) as client:
        response = await client.get(f"{YOUTUBE_API_BASE}/search", params=params)
        if response.status_code != 200:
            _raise_youtube_api_error(response)
        data = response.json()

    videos = []
    for item in data.get("items", []):
        snippet = item.get("snippet", {})
        video_id = item.get("id", {}).get("videoId", "")
        videos.append({
            "video_id": video_id,
            "title": snippet.get("title", ""),
            "description": snippet.get("description", ""),
            "channel_title": snippet.get("channelTitle", ""),
            "channel_id": snippet.get("channelId", ""),
            "published_at": snippet.get("publishedAt", ""),
            "thumbnail_url": snippet.get("thumbnails", {}).get("high", {}).get("url", ""),
            "thumbnail_medium": snippet.get("thumbnails", {}).get("medium", {}).get("url", ""),
        })

    return {
        "videos": videos,
        "next_page_token": data.get("nextPageToken"),
        "prev_page_token": data.get("prevPageToken"),
        "total_results": data.get("pageInfo", {}).get("totalResults", 0),
    }


async def _fetch_captions_transcript_api(video_id: str, lang: str = "en") -> list[dict]:
    """
    Fetch captions using youtube-transcript-api.

    No OAuth needed — uses public transcript endpoints.
    Tries requested language first, then falls back to English variants.
    """
    try:
        from youtube_transcript_api import YouTubeTranscriptApi
        from dataclasses import asdict

        # Run sync library in a thread pool to avoid blocking the event loop
        loop = asyncio.get_running_loop()
        transcript = await loop.run_in_executor(
            None,
            lambda: _get_transcript_sync(video_id, lang),
        )

        if transcript is None:
            logger.info(f"Transcript is None for {video_id}, falling back to timedtext")
            return await _fetch_captions_timedtext(video_id, lang)

        segments = []
        for entry in transcript:
            try:
                entry_dict = asdict(entry)
            except TypeError:
                entry_dict = entry

            start_ms = int(entry_dict.get("start", 0) * 1000)
            duration_ms = int(entry_dict.get("duration", 0) * 1000)
            text = entry_dict.get("text", "").strip()
            if text and text != "\n":
                segments.append({
                    "start_ms": start_ms,
                    "end_ms": start_ms + duration_ms,
                    "text": text,
                })

        return segments

    except Exception as e:
        logger.info(f"Transcript API failed for {video_id}: {e}, falling back to timedtext")
        return await _fetch_captions_timedtext(video_id, lang)


def _get_transcript_sync(video_id: str, lang: str) -> list | None:
    """Sync wrapper for YouTubeTranscriptApi (runs in thread pool)."""
    try:
        from youtube_transcript_api import YouTubeTranscriptApi, NoTranscriptFound
        import requests

        session = requests.Session()
        session.proxies = {"https": "http://172.21.0.1:8888", "http": "http://172.21.0.1:8888"}
        api = YouTubeTranscriptApi(http_client=session)

        # Try requested lang, then en, then any available
        lang_variants = [lang, "en", "en-US", "en-GB"]
        # Deduplicate while preserving order
        seen: set[str] = set()
        langs_to_try: list[str] = []
        for l in lang_variants:
            if l not in seen:
                seen.add(l)
                langs_to_try.append(l)

        try:
            return api.fetch(video_id, languages=langs_to_try)
        except Exception as e:
            logger.info(f"youtube-transcript-api fetch failed, trying list transcripts: {e}")
            try:
                transcript_list = api.list(video_id)
                for transcript in transcript_list:
                    if transcript.is_generated:
                        return transcript.fetch()
            except Exception as e2:
                logger.info(f"youtube-transcript-api list failed: {e2}")
            return None
    except Exception as e:
        logger.info(f"youtube-transcript-api call failed inside _get_transcript_sync: {e}")
        return None


async def _fetch_captions_timedtext(video_id: str, lang: str = "en") -> list[dict]:
    """Fallback: YouTube timedtext API (may be blocked server-side)."""
    try:
        timedtext_url = (
            f"https://www.youtube.com/api/timedtext"
            f"?v={video_id}&lang={lang}&fmt=json3"
        )
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(timedtext_url)
            if resp.status_code == 200:
                caption_data = resp.json()
                return _parse_json3_captions(caption_data)
    except Exception as e:
        logger.warning(f"Timedtext API failed for {video_id}: {e}")
    return []


def _parse_json3_captions(data: dict) -> list[dict]:
    """Parse YouTube JSON3 caption format into segments."""
    segments = []
    for event in data.get("events", []):
        start_ms = event.get("tStartMs", 0)
        duration_ms = event.get("dDurationMs", 0)
        segs = event.get("segs", [])
        text = "".join(seg.get("utf8", "") for seg in segs).strip()
        if text and text != "\n":
            segments.append({
                "start_ms": start_ms,
                "end_ms": start_ms + duration_ms,
                "text": text,
            })
    return segments
