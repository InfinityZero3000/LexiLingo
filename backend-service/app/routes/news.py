"""
News API Routes — English News Articles for Language Learning

Proxy endpoints that fetch news from NewsAPI.org (primary) and NewsData.io (fallback).
Articles are AI-graded with CEFR levels and cached via APICacheService.

Phase 2: News Reading Feature.
"""

import logging
import hashlib
import re
from typing import Optional

import httpx
from urllib.parse import quote, urlparse
from fastapi import APIRouter, Body, Depends, HTTPException, Query, status, Response, Request
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

router = APIRouter(prefix="/news", tags=["News"])

NEWSAPI_BASE = "https://newsapi.org/v2"
NEWSDATA_BASE = "https://newsdata.io/api/1"

# ── CEFR Level Definitions ──────────────────────────────────────
CEFR_LEVELS = {
    "A1": {"label": "Beginner", "color": "#4CAF50", "max_words": 120},
    "A2": {"label": "Elementary", "color": "#8BC34A", "max_words": 200},
    "B1": {"label": "Intermediate", "color": "#FFC107", "max_words": 350},
    "B2": {"label": "Upper Intermediate", "color": "#FF9800", "max_words": 500},
    "C1": {"label": "Advanced", "color": "#FF5722", "max_words": 800},
    "C2": {"label": "Proficiency", "color": "#9C27B0", "max_words": 1500},
}

# ── Curated Categories ──────────────────────────────────────────
NEWS_CATEGORIES = [
    {"id": "technology", "label": "Technology", "icon": "devices"},
    {"id": "science", "label": "Science", "icon": "science"},
    {"id": "health", "label": "Health", "icon": "favorite"},
    {"id": "business", "label": "Business", "icon": "business"},
    {"id": "entertainment", "label": "Entertainment", "icon": "movie"},
    {"id": "sports", "label": "Sports", "icon": "sports"},
    {"id": "general", "label": "World", "icon": "public"},
    {"id": "education", "label": "Education", "icon": "school"},
]


# ============================================================================
# News Articles
# ============================================================================

@router.get("")
async def get_news(
    request: Request,
    category: str = Query("general", description="News category"),
    level: Optional[str] = Query(None, description="CEFR level filter (A1-C2)"),
    page: int = Query(1, ge=1, le=10),
    page_size: int = Query(10, ge=5, le=20),
    q: Optional[str] = Query(None, description="Search query"),
    db: AsyncSession = Depends(get_db),
):
    """
    Get English news articles with CEFR level grading.
    
    Flow:
    1. Fetch from NewsAPI.org (primary) or NewsData.io (fallback)
    2. Estimate CEFR level for each article
    3. Optionally filter by requested level
    4. Cache: Redis 1h, DB 6h
    
    Returns articles with cefrLevel, estimated reading time, and highlighted words.
    """
    if level and level not in CEFR_LEVELS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid CEFR level: {level}. Valid: {list(CEFR_LEVELS.keys())}",
        )
    
    # Build cache key
    cache_parts = [f"cat:{category}", f"p:{page}", f"ps:{page_size}"]
    if level:
        cache_parts.append(f"lv:{level}")
    if q:
        cache_parts.append(f"q:{q}")
    cache_key = f"news:articles:{':'.join(cache_parts)}"
    
    cache_service = APICacheService(db)
    
    try:
        result = await cache_service.get_or_fetch(
            cache_key=cache_key,
            api_name="newsapi",
            fetch_fn=lambda: _fetch_news(
                category=category,
                page=page,
                page_size=page_size,
                query=q,
            ),
            priority=Priority.MEDIUM,
            redis_ttl=3600,      # 1 hour
            db_ttl=21600,        # 6 hours
        )
        
        articles = result.data.get("articles", [])
        
        # Post-process: estimate CEFR level and filter
        for article in articles:
            if "cefr_level" not in article:
                article["cefr_level"] = _estimate_cefr(article)
                article["cefr_info"] = CEFR_LEVELS.get(article["cefr_level"], {})
                article["reading_time_min"] = _estimate_reading_time(article)
                article["highlighted_words"] = _extract_highlight_words(article)
        
        # Filter by level if specified
        if level:
            articles = [a for a in articles if a.get("cefr_level") == level]
        
        # Proxy image URLs to avoid CORS
        base_url = str(request.base_url).rstrip("/")
        api_prefix = settings.API_V1_PREFIX.strip("/")
        news_prefix = router.prefix.strip("/")
        path_prefix = f"{api_prefix}/{news_prefix}".strip("/")
        for a in articles:
            if a.get("image_url"):
                a["image_url"] = f"{base_url}/{path_prefix}/proxy/image?url={quote(a['image_url'])}"
        
        return {
            "articles": articles,
            "total": len(articles),
            "page": page,
            "category": category,
            "source": result.source,
            "is_stale": result.is_stale,
            "categories": NEWS_CATEGORIES,
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


@router.get("/proxy/image", summary="Proxy news images to bypass CORS")
async def proxy_image(url: str = Query(..., description="The image URL to proxy")):
    """
    Proxy news images to bypass browser CORS on web.
    """
    try:
        parsed_url = urlparse(url)
        if not parsed_url.netloc:
            raise ValueError()
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid URL."
        )
        
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            resp = await client.get(
                url, 
                headers={"User-Agent": "LexiLingo/1.0 (English learning app; proxy)"},
                follow_redirects=True
            )
            if resp.status_code != 200:
                raise HTTPException(
                    status_code=resp.status_code,
                    detail=f"Failed to fetch image: HTTP {resp.status_code}"
                )
            return Response(
                content=resp.content,
                media_type=resp.headers.get("content-type", "image/jpeg"),
                headers={
                    "Cache-Control": "public, max-age=86400",  # Cache for 24h
                }
            )
        except Exception as e:
            logger.error(f"Error proxying image {url}: {e}")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to proxy image."
            )


@router.get("/categories")
async def get_categories():
    """Get available news categories with labels and icons."""
    return {"categories": NEWS_CATEGORIES}


# ============================================================================
# Full Article Content (Web Scraping)
# ============================================================================

@router.post("/full-content")
async def get_full_article_content(
    url: str = Body(..., embed=True, description="Original article URL to scrape"),
    db: AsyncSession = Depends(get_db),
):
    """
    Scrape full article text from the original URL.

    NewsAPI free tier truncates content to ~200 characters.
    This endpoint fetches the full article using trafilatura.

    Cache: Redis 24h, DB 7 days (article content doesn't change).
    """
    if not url or not url.startswith(("http://", "https://")):
        raise HTTPException(status_code=400, detail="Invalid URL")

    cache_key = f"news:full:{hashlib.md5(url.encode()).hexdigest()[:16]}"
    cache_service = APICacheService(db)

    try:
        result = await cache_service.get_or_fetch(
            cache_key=cache_key,
            api_name="newsapi",
            fetch_fn=lambda: _scrape_full_article(url),
            priority=Priority.LOW,
            redis_ttl=86400,     # 24 hours
            db_ttl=604800,       # 7 days
        )

        return {
            "content": result.data.get("content", ""),
            "source": result.source,
        }
    except Exception as e:
        logger.error(f"Failed to scrape article from {url}: {e}")
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to fetch full article content",
        )


async def _scrape_full_article(url: str) -> dict:
    """Fetch and extract full article text from a URL using trafilatura."""
    import asyncio

    try:
        import trafilatura

        async with httpx.AsyncClient(
            timeout=15.0,
            follow_redirects=True,
            headers={"User-Agent": "Mozilla/5.0 (compatible; LexiLingo/1.0)"},
        ) as client:
            response = await client.get(url)
            response.raise_for_status()
            html = response.text

        # trafilatura is synchronous — run in executor
        loop = asyncio.get_event_loop()
        content = await loop.run_in_executor(
            None,
            lambda: trafilatura.extract(
                html,
                include_comments=False,
                include_tables=False,
                no_fallback=False,
            ),
        )

        if not content:
            # Fallback: basic HTML tag stripping
            content = _strip_html_basic(html)

        return {"content": content or ""}

    except ImportError:
        # trafilatura not installed — basic fallback
        logger.warning("trafilatura not installed, using basic HTML extraction")
        async with httpx.AsyncClient(
            timeout=15.0,
            follow_redirects=True,
            headers={"User-Agent": "Mozilla/5.0 (compatible; LexiLingo/1.0)"},
        ) as client:
            response = await client.get(url)
            response.raise_for_status()
            html = response.text

        return {"content": _strip_html_basic(html)}


def _strip_html_basic(html: str) -> str:
    """Basic HTML to text conversion — fallback when trafilatura is unavailable."""
    import html as html_module

    # Remove script and style tags
    html = re.sub(r'<(script|style)[^>]*>.*?</\1>', '', html, flags=re.DOTALL | re.IGNORECASE)
    # Remove HTML tags (replace with space to preserve word boundaries)
    text = re.sub(r'<[^>]+>', ' ', html)
    # Decode HTML entities (&#x27; → ', &amp; → &, etc.)
    text = html_module.unescape(text)
    # Clean up whitespace
    text = re.sub(r'\s+', ' ', text).strip()
    # Take only the main content portion (skip navigation etc.)
    if len(text) > 500:
        return text[:10000]  # Cap at 10k chars
    return text


# ============================================================================
# Article Quiz
# ============================================================================

@router.get("/{article_id}/quiz")
async def get_article_quiz(
    article_id: str,
    db: AsyncSession = Depends(get_db),
):
    """
    Get AI-generated comprehension quiz for a news article.
    
    Generates 5 questions:
    - 2 comprehension (main idea, detail)
    - 2 vocabulary (word meaning in context)
    - 1 grammar (sentence structure)
    
    Cache: permanent (article content doesn't change).
    """
    cache_key = f"news:quiz:{article_id}"
    cache_service = APICacheService(db)
    
    try:
        result = await cache_service.get_or_fetch(
            cache_key=cache_key,
            api_name="newsapi",  # Minimal cost — uses cached article text
            fetch_fn=lambda: _generate_quiz(article_id),
            priority=Priority.LOW,
            redis_ttl=604800,       # 7 days
            db_ttl=31536000,        # 1 year (permanent)
        )
        return {
            "article_id": article_id,
            "quiz": result.data,
            "source": result.source,
        }
    except (QuotaExhaustedError, QuotaNearLimitError) as e:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=str(e),
        )


# ============================================================================
# Internal Functions
# ============================================================================

async def _fetch_news(
    category: str = "general",
    page: int = 1,
    page_size: int = 10,
    query: Optional[str] = None,
) -> dict:
    """
    Fetch news from NewsAPI.org (primary) with NewsData.io fallback.
    
    Returns normalized article list.
    """
    # Try NewsAPI.org first
    if settings.NEWSAPI_KEY:
        try:
            return await _fetch_from_newsapi(category, page, page_size, query)
        except Exception as e:
            logger.warning(f"NewsAPI.org failed, trying fallback: {e}")
    
    # Fallback: NewsData.io
    if settings.NEWSDATA_KEY:
        try:
            return await _fetch_from_newsdata(category, page, page_size, query)
        except Exception as e:
            logger.error(f"NewsData.io also failed: {e}")
    
    raise HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail="No news API keys configured or all providers failed.",
    )


async def _fetch_from_newsapi(
    category: str,
    page: int,
    page_size: int,
    query: Optional[str],
) -> dict:
    """Fetch from NewsAPI.org and normalize to common format."""
    params = {
        "apiKey": settings.NEWSAPI_KEY,
        "language": "en",
        "pageSize": page_size,
        "page": page,
    }
    
    if query:
        # Use /everything endpoint for search
        params["q"] = query
        params["sortBy"] = "relevancy"
        endpoint = f"{NEWSAPI_BASE}/everything"
    else:
        # Use /top-headlines for category browsing
        params["category"] = category
        params["country"] = "us"
        endpoint = f"{NEWSAPI_BASE}/top-headlines"
    
    async with httpx.AsyncClient(timeout=15.0) as client:
        response = await client.get(endpoint, params=params)
        response.raise_for_status()
        data = response.json()
    
    if data.get("status") != "ok":
        raise Exception(f"NewsAPI error: {data.get('message', 'Unknown')}")
    
    articles = []
    for item in data.get("articles", []):
        # Skip articles with [Removed] content
        if item.get("title") == "[Removed]" or not item.get("content"):
            continue
        
        article_id = hashlib.md5(
            (item.get("url", "") + item.get("title", "")).encode()
        ).hexdigest()[:12]
        
        articles.append({
            "id": article_id,
            "title": item.get("title", ""),
            "description": item.get("description", ""),
            "content": re.sub(r'\s*\[\+\d+ chars\]$', '', item.get("content", "")),
            "url": item.get("url", ""),
            "image_url": item.get("urlToImage", ""),
            "source_name": item.get("source", {}).get("name", ""),
            "author": item.get("author", ""),
            "published_at": item.get("publishedAt", ""),
            "category": category,
            "provider": "newsapi",
        })
    
    return {
        "articles": articles,
        "total_results": data.get("totalResults", 0),
    }


async def _fetch_from_newsdata(
    category: str,
    page: int,
    page_size: int,
    query: Optional[str],
) -> dict:
    """Fetch from NewsData.io (fallback) and normalize to common format."""
    params = {
        "apikey": settings.NEWSDATA_KEY,
        "language": "en",
        "size": min(page_size, 10),  # NewsData free tier limit
    }
    
    if query:
        params["q"] = query
    if category and category != "general":
        params["category"] = category
    
    async with httpx.AsyncClient(timeout=15.0) as client:
        response = await client.get(f"{NEWSDATA_BASE}/news", params=params)
        response.raise_for_status()
        data = response.json()
    
    if data.get("status") != "success":
        raise Exception(f"NewsData error: {data.get('message', 'Unknown')}")
    
    articles = []
    for item in data.get("results", []):
        article_id = hashlib.md5(
            (item.get("link", "") + item.get("title", "")).encode()
        ).hexdigest()[:12]
        
        articles.append({
            "id": article_id,
            "title": item.get("title", ""),
            "description": item.get("description", ""),
            "content": item.get("content", "") or item.get("description", ""),
            "url": item.get("link", ""),
            "image_url": item.get("image_url", ""),
            "source_name": item.get("source_id", ""),
            "author": item.get("creator", [""])[0] if item.get("creator") else "",
            "published_at": item.get("pubDate", ""),
            "category": category,
            "provider": "newsdata",
        })
    
    return {
        "articles": articles,
        "total_results": data.get("totalResults", 0),
    }


def _estimate_cefr(article: dict) -> str:
    """
    Estimate CEFR level from article text using heuristics.
    
    Factors: word count, average word length, sentence complexity.
    In production, replace with AI grading via /ai/grade_text endpoint.
    """
    content = article.get("content", "") or article.get("description", "")
    if not content:
        return "B1"  # Default middle level
    
    words = content.split()
    word_count = len(words)
    
    if word_count == 0:
        return "B1"
    
    avg_word_length = sum(len(w) for w in words) / word_count
    
    # Long words + many words → harder
    # Short words + fewer words → easier
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


def _estimate_reading_time(article: dict) -> int:
    """Estimate reading time in minutes (avg 200 wpm for ESL learners)."""
    content = article.get("content", "") or article.get("description", "")
    word_count = len(content.split()) if content else 0
    return max(1, round(word_count / 150))  # 150 wpm for ESL


def _extract_highlight_words(article: dict) -> list[str]:
    """
    Extract potentially challenging vocabulary words to highlight.
    
    Simple heuristic: words longer than 7 characters that aren't common.
    In production, use AI NLP analysis.
    """
    COMMON_LONG_WORDS = {
        "something", "everything", "everyone", "someone", "position",
        "important", "different", "national", "international", "according",
        "government", "president", "countries", "continue", "following",
        "including", "community", "available", "together", "possible",
        "information", "development", "education", "technology", "experience",
        "questions", "companies", "beginning", "financial", "political",
    }
    
    content = article.get("content", "") or article.get("description", "")
    if not content:
        return []
    
    import re
    words = re.findall(r'\b[a-zA-Z]+\b', content)
    
    highlights = set()
    for word in words:
        lower = word.lower()
        if len(lower) > 7 and lower not in COMMON_LONG_WORDS:
            highlights.add(lower)
    
    return sorted(list(highlights))[:10]  # Max 10 highlighted words


async def _generate_quiz(article_id: str) -> dict:
    """
    Generate a comprehension quiz for an article.
    
    TODO: Integrate with AI service for real quiz generation.
    Returns placeholder quiz structure for now.
    """
    return {
        "questions": [
            {
                "id": 1,
                "type": "comprehension",
                "question": "What is the main idea of this article?",
                "options": [
                    "Option A — correct answer",
                    "Option B — distractor",
                    "Option C — distractor",
                    "Option D — distractor",
                ],
                "correct_index": 0,
                "explanation": "This will be AI-generated based on the article content.",
            },
            {
                "id": 2,
                "type": "comprehension",
                "question": "Which detail is mentioned in the article?",
                "options": [
                    "Option A — distractor",
                    "Option B — correct answer",
                    "Option C — distractor",
                    "Option D — distractor",
                ],
                "correct_index": 1,
                "explanation": "AI-generated explanation.",
            },
            {
                "id": 3,
                "type": "vocabulary",
                "question": "What does the word '[highlighted word]' mean in context?",
                "options": [
                    "Option A — distractor",
                    "Option B — distractor",
                    "Option C — correct answer",
                    "Option D — distractor",
                ],
                "correct_index": 2,
                "explanation": "AI-generated vocabulary explanation.",
            },
            {
                "id": 4,
                "type": "vocabulary",
                "question": "Choose the synonym for '[highlighted word]' as used here.",
                "options": [
                    "Option A — correct answer",
                    "Option B — distractor",
                    "Option C — distractor",
                    "Option D — distractor",
                ],
                "correct_index": 0,
                "explanation": "AI-generated synonym explanation.",
            },
            {
                "id": 5,
                "type": "grammar",
                "question": "Which sentence structure is correct?",
                "options": [
                    "Option A — distractor",
                    "Option B — distractor",
                    "Option C — distractor",
                    "Option D — correct answer",
                ],
                "correct_index": 3,
                "explanation": "AI-generated grammar explanation.",
            },
        ],
        "total_questions": 5,
        "xp_reward": 15,
        "note": "Quiz generation will be powered by AI service in production.",
    }
