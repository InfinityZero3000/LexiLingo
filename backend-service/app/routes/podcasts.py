"""
Podcast API Routes — English Learning Podcasts for Language Learners

Endpoints proxy PodcastIndex.org for search and parse RSS feeds directly
for episode listings. Curated list of English-learning podcasts is served
from hardcoded data (no API cost). All cacheable responses use APICacheService.

Phase 4: Podcast Feature.
"""

import hashlib
import logging
import re
import time
import xml.etree.ElementTree as ET
from typing import Optional

import httpx
from fastapi import APIRouter, Body, Depends, HTTPException, Query, status
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
        "id": hashlib.md5(b"https://feeds.megaphone.fm/bbclearningenglish").hexdigest()[:12],
        "title": "BBC 6 Minute English",
        "author": "BBC Learning English",
        "description": (
            "Every week we ask an interesting question about the world and discuss"
            " the answer in easy, B1-level English. With vocabulary explanations."
        ),
        "feed_url": "https://feeds.megaphone.fm/bbclearningenglish",
        "artwork_url": "https://ichef.bbci.co.uk/images/ic/1200x1200/p09jnvlt.jpg",
        "episode_count": 0,
        "categories": ["education", "learning"],
        "cefr_level": "A2",
        "language": "en",
    },
    {
        "id": hashlib.md5(b"https://www.eslpod.com/eslpod/website/simple_sound/eslpodcast.rss").hexdigest()[:12],
        "title": "ESL Pod",
        "author": "Dr. Jeff McQuillan",
        "description": (
            "Slow, clear English conversations with detailed explanations of"
            " vocabulary and grammar, perfect for beginner ESL learners."
        ),
        "feed_url": "https://www.eslpod.com/eslpod/website/simple_sound/eslpodcast.rss",
        "artwork_url": "https://cdn.eslpod.com/img/icon.jpg",
        "episode_count": 0,
        "categories": ["education", "esl"],
        "cefr_level": "A1",
        "language": "en",
    },
    # B1-B2 — normal conversational speed
    {
        "id": hashlib.md5(b"https://allears.libsyn.com/rss").hexdigest()[:12],
        "title": "All Ears English",
        "author": "Lindsay McMahon & Michelle Kaplan",
        "description": (
            "Real English conversations about American culture, idioms, and"
            " expressions. Connection NOT perfection is our motto."
        ),
        "feed_url": "https://allears.libsyn.com/rss",
        "artwork_url": "https://ssl-static.libsyn.com/p/assets/7/2/b/7/72b739d4b0c1e2f3/AEE_New_2022_AlbumArt.jpg",
        "episode_count": 0,
        "categories": ["education", "english"],
        "cefr_level": "B1",
        "language": "en",
    },
    {
        "id": hashlib.md5(b"https://culips.com/feed/podcast").hexdigest()[:12],
        "title": "Culips ESL Podcast",
        "author": "Culips",
        "description": (
            "Authentic English conversations about everyday topics with full"
            " transcripts. Great for intermediate listeners."
        ),
        "feed_url": "https://culips.com/feed/podcast",
        "artwork_url": "https://culips.com/wp-content/uploads/culips-podcast-album-art-3000.jpg",
        "episode_count": 0,
        "categories": ["education", "esl"],
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
        "artwork_url": "https://media.npr.org/assets/img/2022/01/19/ted-radio-hour_tile_npr-network-01_sq-64a0e68af71c9fc53b820ac7f3e8e88a91b0da6.jpg",
        "episode_count": 0,
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
        "artwork_url": "https://media.npr.org/assets/img/2018/08/03/npr_nprnewsnow_podcasttile_sq-fd4d9b32d97b5c5b1440f45b5a05c9b9c4fbba4.jpg",
        "episode_count": 0,
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


# ============================================================================
# 1. Search Podcasts
# ============================================================================

@router.get("/search")
async def search_podcasts(
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
        return {
            "podcasts": CURATED_PODCASTS,
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
        for podcast in podcasts:
            if "cefr_level" not in podcast or not podcast["cefr_level"]:
                podcast["cefr_level"] = _estimate_cefr(podcast.get("description", ""))
                podcast["cefr_info"] = CEFR_LEVELS.get(podcast["cefr_level"], {})

        return {
            "podcasts": podcasts,
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
async def get_curated_podcasts():
    """
    Return a handpicked list of English-learning podcasts grouped by CEFR level.

    No external API call — static data, no rate limiting needed.
    Returns podcasts in each CEFR band with category metadata.
    """
    grouped = _group_curated_by_cefr()
    return {
        "podcasts": CURATED_PODCASTS,
        "categories": grouped,
    }


# ============================================================================
# 3. Podcast Episodes from RSS Feed
# ============================================================================

@router.get("/episodes")
async def get_podcast_episodes(
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

        return {
            "episodes": result.data.get("episodes", []),
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


# ============================================================================
# 4. Transcript (Not Implemented)
# ============================================================================

@router.post("/transcript")
async def generate_transcript(
    feed_url: str = Body(..., description="RSS feed URL"),
    episode_guid: str = Body(..., description="Episode GUID"),
    audio_url: str = Body(..., description="Direct audio file URL"),
):
    """
    Request transcript generation for a podcast episode.

    NOT IMPLEMENTED — transcript generation via speech-to-text is planned
    for a future phase. Returns a pending status response.
    """
    return {
        "message": "Transcript generation coming soon",
        "status": "pending",
        "feed_url": feed_url,
        "episode_guid": episode_guid,
    }


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
        if entry.get("published"):
            published_at = entry.published
        elif entry.get("updated"):
            published_at = entry.updated

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

        episodes.append({
            "guid": _elem_text(item, "guid") or _elem_text(item, "link") or "",
            "title": _elem_text(item, "title") or "",
            "audio_url": audio_url,
            "duration_seconds": duration_seconds,
            "published_at": _elem_text(item, "pubDate") or "",
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
