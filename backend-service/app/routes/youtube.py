"""
YouTube API Routes — Video Search, Captions, and Curated Channels

Proxy endpoints that hide the YouTube Data API v3 key from the client.
All responses are cached via the 3-layer APICacheService.

Phase 1: YouTube Video Integration with Auto Subtitles.
"""

import logging
from typing import Optional

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query, status
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

YOUTUBE_API_BASE = "https://www.googleapis.com/youtube/v3"


# ============================================================================
# Curated Channel List (No API cost)
# ============================================================================

CURATED_CHANNELS = [
    {
        "id": "UCHaHD477h-FeBbrgBrwTDpA",
        "name": "BBC Learning English",
        "description": "Learn English with the BBC. Improve grammar, vocabulary and pronunciation.",
        "level": "A2-B2",
        "thumbnail": "https://yt3.googleusercontent.com/BBCLearningEnglish",
        "category": "general",
    },
    {
        "id": "UCsooa4yRKGN_zEE8iknghZA",
        "name": "TED-Ed",
        "description": "Lessons worth sharing. TED-Ed's commitment to creating lessons worth sharing.",
        "level": "B1-C1",
        "thumbnail": "https://yt3.googleusercontent.com/TEDEd",
        "category": "academic",
    },
    {
        "id": "UCz4tgANd4yy8Oe0iXCdSWfA",
        "name": "English with Lucy",
        "description": "Learn British English with Lucy. Grammar, vocabulary, and pronunciation.",
        "level": "A2-B2",
        "thumbnail": "https://yt3.googleusercontent.com/EnglishWithLucy",
        "category": "general",
    },
    {
        "id": "UCVBErcpqaokOf4fI5j73K_w",
        "name": "EngVid",
        "description": "Free English video lessons by experienced teachers.",
        "level": "A1-C1",
        "thumbnail": "https://yt3.googleusercontent.com/EngVid",
        "category": "general",
    },
    {
        "id": "UCvn_XCl_mgQmt3sD753MZ0Q",
        "name": "Rachel's English",
        "description": "American English pronunciation training.",
        "level": "B1-C1",
        "thumbnail": "https://yt3.googleusercontent.com/RachelsEnglish",
        "category": "pronunciation",
    },
    {
        "id": "UCkowKaGPT_yWCebvqN0wBmA",
        "name": "VOA Learning English",
        "description": "Practice American English with slow-speed news.",
        "level": "A1-A2",
        "thumbnail": "https://yt3.googleusercontent.com/VOALearningEnglish",
        "category": "news",
    },
]


@router.get("/channels")
async def get_curated_channels(
    category: Optional[str] = Query(None, description="Filter by category"),
):
    """
    Get curated English learning YouTube channels.
    
    No API cost — returns hardcoded curated list.
    """
    channels = CURATED_CHANNELS
    if category:
        channels = [c for c in channels if c["category"] == category]
    
    return {
        "channels": channels,
        "total": len(channels),
    }


# ============================================================================
# Video Search (100 units per search.list call)
# ============================================================================

@router.get("/search")
async def search_videos(
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
    
    # Build cache key
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
            priority=Priority.HIGH,  # User-initiated search
            redis_ttl=21600,    # 6 hours
            db_ttl=43200,       # 12 hours
        )
        return {
            "data": result.data,
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
# Video Captions (2 units for captions.list)
# ============================================================================

@router.get("/captions/{video_id}")
async def get_captions(
    video_id: str,
    lang: str = Query("en", description="Caption language code"),
    db: AsyncSession = Depends(get_db),
):
    """
    Fetch and parse captions/subtitles for a YouTube video.
    
    Quota cost: ~7 units (captions.list + download).
    Cache: Permanent (captions don't change).
    
    Returns list of caption segments with start/end times.
    """
    if not settings.YOUTUBE_API_KEY:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="YouTube API key not configured.",
        )
    
    cache_key = f"youtube:captions:{video_id}:{lang}"
    cache_service = APICacheService(db)
    
    try:
        result = await cache_service.get_or_fetch(
            cache_key=cache_key,
            api_name="youtube",
            fetch_fn=lambda: _fetch_captions(video_id, lang),
            priority=Priority.HIGH,
            redis_ttl=604800,       # 7 days
            db_ttl=31536000,        # 1 year (permanent)
        )
        return {
            "video_id": video_id,
            "language": lang,
            "segments": result.data,
            "source": result.source,
            "is_stale": result.is_stale,
        }
    except QuotaExhaustedError as e:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=str(e),
        )


# ============================================================================
# Channel Videos (100 units per search.list)
# ============================================================================

@router.get("/channels/{channel_id}/videos")
async def get_channel_videos(
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
            fetch_fn=lambda: _youtube_search(
                q="",
                max_results=max_results,
                channel_id=channel_id,
                page_token=page_token,
            ),
            priority=Priority.MEDIUM,  # Auto-load when user opens channel
            redis_ttl=43200,    # 12 hours
            db_ttl=86400,       # 24 hours
        )
        return {
            "channel_id": channel_id,
            "data": result.data,
            "source": result.source,
            "is_stale": result.is_stale,
        }
    except (QuotaExhaustedError, QuotaNearLimitError) as e:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=str(e),
        )


# ============================================================================
# Internal API Call Functions
# ============================================================================

async def _youtube_search(
    q: str,
    max_results: int = 10,
    channel_id: Optional[str] = None,
    page_token: Optional[str] = None,
) -> dict:
    """Call YouTube Data API v3 search.list endpoint."""
    params = {
        "part": "snippet",
        "type": "video",
        "maxResults": max_results,
        "key": settings.YOUTUBE_API_KEY,
        "relevanceLanguage": "en",
        "videoCaption": "closedCaption",  # Only videos with captions
    }
    if q:
        params["q"] = q
    if channel_id:
        params["channelId"] = channel_id
    if page_token:
        params["pageToken"] = page_token
    
    async with httpx.AsyncClient(timeout=15.0) as client:
        response = await client.get(f"{YOUTUBE_API_BASE}/search", params=params)
        response.raise_for_status()
        data = response.json()
    
    # Transform to cleaner format
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


async def _fetch_captions(video_id: str, lang: str = "en") -> list[dict]:
    """
    Fetch and parse captions for a YouTube video.
    
    Strategy:
    1. Try YouTube Data API captions.list → get caption track URL
    2. Download and parse the caption track (SRT/VTT format)
    3. Return list of segments: [{start_ms, end_ms, text}, ...]
    """
    # Step 1: List available caption tracks
    params = {
        "part": "snippet",
        "videoId": video_id,
        "key": settings.YOUTUBE_API_KEY,
    }
    
    async with httpx.AsyncClient(timeout=15.0) as client:
        response = await client.get(f"{YOUTUBE_API_BASE}/captions", params=params)
        response.raise_for_status()
        data = response.json()
    
    # Find matching language track
    tracks = data.get("items", [])
    target_track = None
    for track in tracks:
        track_lang = track.get("snippet", {}).get("language", "")
        if track_lang == lang:
            target_track = track
            break
    
    if not target_track:
        # Try auto-generated captions (ASR)
        for track in tracks:
            if track.get("snippet", {}).get("trackKind") == "ASR":
                target_track = track
                break
    
    if not target_track:
        # No captions available — return empty
        logger.info(f"No {lang} captions found for video {video_id}")
        return []
    
    # Step 2: Try to get captions via timedtext API (no OAuth needed)
    try:
        timedtext_url = (
            f"https://www.youtube.com/api/timedtext"
            f"?v={video_id}&lang={lang}&fmt=json3"
        )
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(timedtext_url)
            if resp.status_code == 200:
                caption_data = resp.json()
                return _parse_json3_captions(caption_data)
    except Exception as e:
        logger.warning(f"Timedtext API failed for {video_id}: {e}")
    
    # Step 3: Fallback — return track metadata only
    return [{
        "track_id": target_track.get("id", ""),
        "language": lang,
        "kind": target_track.get("snippet", {}).get("trackKind", ""),
        "name": target_track.get("snippet", {}).get("name", ""),
        "segments": [],
        "note": "Full caption download requires OAuth. Track metadata only.",
    }]


def _parse_json3_captions(data: dict) -> list[dict]:
    """Parse YouTube JSON3 caption format into segments."""
    segments = []
    events = data.get("events", [])
    
    for event in events:
        start_ms = event.get("tStartMs", 0)
        duration_ms = event.get("dDurationMs", 0)
        
        # Reconstruct text from segments
        segs = event.get("segs", [])
        text = "".join(seg.get("utf8", "") for seg in segs).strip()
        
        if text and text != "\n":
            segments.append({
                "start_ms": start_ms,
                "end_ms": start_ms + duration_ms,
                "text": text,
            })
    
    return segments
