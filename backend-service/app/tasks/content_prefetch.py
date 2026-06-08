"""
Content Prefetch Tasks — Background Cron Jobs

Pre-populate cache with fresh content from external APIs.
Runs on a schedule to ensure users always see data, even during
peak hours when quota might be exhausted by real-time requests.

Schedule:
    - News:     4x/day (every 6 hours)
    - YouTube:  2x/day (every 12 hours)
    - Podcasts: 1x/day (once at midnight UTC)

All prefetch tasks use LOW priority, so they are automatically
blocked when quota reaches WARNING threshold (70%).

Phase 0 Infrastructure: Background data population.
"""

import logging
from datetime import date

from sqlalchemy.ext.asyncio import AsyncSession

from app.services.api_cache_service import APICacheService
from app.services.quota_manager import Priority

logger = logging.getLogger(__name__)

# ──────────────────────────────────────────────────────────
#  Curated Content IDs (hardcoded — no API cost)
# ──────────────────────────────────────────────────────────

# YouTube channels for English learning
CURATED_YOUTUBE_CHANNELS = {
    "BBC Learning English": "UCHaHD477h-FeBbVh9Sh7syA",
    "TED-Ed": "UCsooa4yRKGN_zEE8iknghZA",
    "English with Lucy": "UCz4tgANd4yy8Oe0iXCdSWfA",
    "Rachel's English": "UCvn_XCl_mgQmt3sD753zdJA",
    "VOA Learning English": "UCKyTokYo0nK2OA-az-sDijA",
    "EngVid": "UCVBErcpqaokOf4fI5j73K_w",
}

# Curated podcast RSS feeds for English learning
CURATED_PODCAST_FEEDS = {
    "BBC 6 Minute English": "https://podcasts.files.bbci.co.uk/p02pc9tn.rss",
    "ESL Pod": "https://www.eslpod.com/website/podcast.xml",
    "All Ears English": "https://feeds.simplecast.com/UM9bvJkp",
    "Culips": "https://feeds.feedburner.com/CulipsEslPodcast",
}

# News categories to prefetch
NEWS_CATEGORIES = ["technology", "science", "world", "education"]


# ──────────────────────────────────────────────────────────
#  Prefetch Tasks
# ──────────────────────────────────────────────────────────

async def prefetch_news(db: AsyncSession) -> dict:
    """
    Fetch top English learning news articles, grade by CEFR level.
    
    Schedule: Run 4x/day (every 6 hours).
    API: NewsAPI.org (budget: 80 req/day → uses ~4-16 req per run).
    
    Returns summary of results.
    """
    cache_service = APICacheService(db)
    results = {"fetched": 0, "cached": 0, "errors": 0}
    
    for category in NEWS_CATEGORIES:
        cache_key = f"news:en:{category}:{date.today().isoformat()}"
        
        try:
            result = await cache_service.get_or_fetch(
                cache_key=cache_key,
                api_name="newsapi",
                fetch_fn=lambda cat=category: _fetch_news_category(cat),
                priority=Priority.LOW,
                redis_ttl=3600,     # 1 hour
                db_ttl=21600,       # 6 hours
            )
            if result.source == "api":
                results["fetched"] += 1
            else:
                results["cached"] += 1
        except Exception as e:
            logger.error(f"Prefetch news [{category}] failed: {e}")
            results["errors"] += 1
    
    logger.info(f" News prefetch complete: {results}")
    return results


async def prefetch_youtube(db: AsyncSession) -> dict:
    """
    Fetch latest videos from curated English learning channels.
    
    Schedule: Run 2x/day (every 12 hours).
    API: YouTube Data API v3 (budget: 8,000 units/day).
    Note: search.list costs 100 units per call. 6 channels × 100 = 600 units.
    
    Returns summary of results.
    """
    cache_service = APICacheService(db)
    results = {"fetched": 0, "cached": 0, "errors": 0}
    
    for channel_name, channel_id in CURATED_YOUTUBE_CHANNELS.items():
        cache_key = f"youtube:channel:{channel_id}:{date.today().isoformat()}"
        
        try:
            result = await cache_service.get_or_fetch(
                cache_key=cache_key,
                api_name="youtube",
                fetch_fn=lambda cid=channel_id: _fetch_youtube_channel(cid),
                priority=Priority.LOW,
                redis_ttl=43200,    # 12 hours
                db_ttl=86400,       # 24 hours
            )
            if result.source == "api":
                results["fetched"] += 1
            else:
                results["cached"] += 1
        except Exception as e:
            logger.error(f"Prefetch YouTube [{channel_name}] failed: {e}")
            results["errors"] += 1
    
    logger.info(f" YouTube prefetch complete: {results}")
    return results


async def prefetch_podcasts(db: AsyncSession) -> dict:
    """
    Fetch latest episodes from curated English learning podcasts.
    
    Schedule: Run 1x/day.
    API: Direct RSS feed parsing (no API cost for curated feeds).
    
    Returns summary of results.
    """
    cache_service = APICacheService(db)
    results = {"fetched": 0, "cached": 0, "errors": 0}
    
    for podcast_name, feed_url in CURATED_PODCAST_FEEDS.items():
        cache_key = f"podcast:feed:{hash(feed_url)}:{date.today().isoformat()}"
        
        try:
            result = await cache_service.get_or_fetch(
                cache_key=cache_key,
                api_name="podcastindex",
                fetch_fn=lambda url=feed_url: _fetch_rss_feed(url),
                priority=Priority.LOW,
                redis_ttl=10800,    # 3 hours
                db_ttl=86400,       # 24 hours
            )
            if result.source == "api":
                results["fetched"] += 1
            else:
                results["cached"] += 1
        except Exception as e:
            logger.error(f"Prefetch podcast [{podcast_name}] failed: {e}")
            results["errors"] += 1
    
    logger.info(f"️ Podcast prefetch complete: {results}")
    return results


# ──────────────────────────────────────────────────────────
#  API Call Integrations (delegated to actual fetch helpers)
# ──────────────────────────────────────────────────────────

async def _fetch_news_category(category: str) -> list[dict]:
    """Fetch news articles from NewsAPI.org (or fallback) for a given category."""
    from app.routes.news import _fetch_news
    res = await _fetch_news(category=category, page=1, page_size=10)
    return res.get("articles", [])


async def _fetch_youtube_channel(channel_id: str) -> list[dict]:
    """Fetch latest videos from a YouTube channel using search.list."""
    from app.routes.youtube import _youtube_search
    res = await _youtube_search(q="", max_results=10, channel_id=channel_id, require_captions=False)
    return res.get("videos", [])


async def _fetch_rss_feed(feed_url: str) -> list[dict]:
    """Parse RSS feed and extract episode list."""
    from app.routes.podcasts import _fetch_rss_episodes
    res = await _fetch_rss_episodes(feed_url=feed_url, limit=20)
    return res.get("episodes", [])
