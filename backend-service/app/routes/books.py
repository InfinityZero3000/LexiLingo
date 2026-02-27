"""
Book API Routes — English Book Reading for Language Learners

Endpoints search Gutendex (Project Gutenberg) and Open Library for free,
public-domain books. CEFR levels are estimated from description text.
Comprehension quizzes are AI-generated per chapter (stub, coming soon).
Curated recommendations are served from hardcoded data (no API cost).

Phase 5: Book Reading Feature.
"""

import logging
from typing import Optional

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.services.api_cache_service import (
    APICacheService,
    QuotaExhaustedError,
    QuotaNearLimitError,
)
from app.services.quota_manager import Priority

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/books", tags=["Books"])

GUTENDEX_BASE = "https://gutendex.com/books"
OPEN_LIBRARY_BASE = "https://openlibrary.org"

# ── CEFR Level Definitions ───────────────────────────────────────
CEFR_LEVELS = {
    "A1": {"label": "Beginner", "color": "#4CAF50"},
    "A2": {"label": "Elementary", "color": "#8BC34A"},
    "B1": {"label": "Intermediate", "color": "#FFC107"},
    "B2": {"label": "Upper Intermediate", "color": "#FF9800"},
    "C1": {"label": "Advanced", "color": "#FF5722"},
    "C2": {"label": "Proficiency", "color": "#9C27B0"},
}

# ── CEFR by Subject ──────────────────────────────────────────────
_CEFR_BY_SUBJECT = {
    "fairy tales": "A1",
    "children": "A1",
    "easy reader": "A1",
    "short stories": "A2",
    "adventure": "B1",
    "romance": "B1",
    "mystery": "B1",
    "science fiction": "B1",
    "historical fiction": "B2",
    "literary fiction": "B2",
    "philosophy": "C1",
    "essay": "C1",
    "classic": "B2",
    "poetry": "C1",
    "satire": "C1",
    "drama": "B2",
    "tragedy": "C1",
    "comedy": "B2",
}

# ── Curated English-Learning Books by CEFR Level ─────────────────
CURATED_BOOKS = [
    {
        "id": "gutenberg-2591",
        "source": "gutenberg",
        "title": "Grimms' Fairy Tales",
        "author": "Brothers Grimm",
        "description": (
            "Classic fairy tales including Cinderella, Snow White, and Hansel "
            "and Gretel — perfect for beginner English learners."
        ),
        "cover_url": "https://covers.openlibrary.org/b/id/8739153-L.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/2591/pg2591.txt",
        "language": "en",
        "cefr_level": "A1",
        "subject": "Fairy Tales",
        "chapter_count": 45,
        "word_count": 55000,
    },
    {
        "id": "gutenberg-11",
        "source": "gutenberg",
        "title": "Alice's Adventures in Wonderland",
        "author": "Lewis Carroll",
        "description": (
            "A young girl named Alice falls into a rabbit hole and embarks on a "
            "fantastical adventure in a world of nonsense and imagination."
        ),
        "cover_url": "https://covers.openlibrary.org/b/id/8739155-L.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/11/pg11.txt",
        "language": "en",
        "cefr_level": "A2",
        "subject": "Fantasy",
        "chapter_count": 12,
        "word_count": 26500,
    },
    {
        "id": "gutenberg-74",
        "source": "gutenberg",
        "title": "The Adventures of Tom Sawyer",
        "author": "Mark Twain",
        "description": (
            "The story of a young boy growing up along the Mississippi River "
            "in the mid-19th century, exploring caves and getting into mischief."
        ),
        "cover_url": "https://covers.openlibrary.org/b/id/8739160-L.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/74/pg74.txt",
        "language": "en",
        "cefr_level": "B1",
        "subject": "Adventure",
        "chapter_count": 35,
        "word_count": 70000,
    },
    {
        "id": "gutenberg-1342",
        "source": "gutenberg",
        "title": "Pride and Prejudice",
        "author": "Jane Austen",
        "description": (
            "A classic novel about manners, upbringing, morality, education, "
            "and marriage in early 19th-century England."
        ),
        "cover_url": "https://covers.openlibrary.org/b/id/8739161-L.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/1342/pg1342.txt",
        "language": "en",
        "cefr_level": "B1",
        "subject": "Romance",
        "chapter_count": 61,
        "word_count": 122000,
    },
    {
        "id": "gutenberg-5200",
        "source": "gutenberg",
        "title": "Metamorphosis",
        "author": "Franz Kafka",
        "description": (
            "Gregor Samsa wakes one morning to find he has transformed into a "
            "monstrous insect. A profound short novel exploring alienation."
        ),
        "cover_url": "https://covers.openlibrary.org/b/id/8739154-L.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/5200/pg5200.txt",
        "language": "en",
        "cefr_level": "B2",
        "subject": "Literary Fiction",
        "chapter_count": 3,
        "word_count": 22000,
    },
    {
        "id": "gutenberg-1080",
        "source": "gutenberg",
        "title": "A Modest Proposal",
        "author": "Jonathan Swift",
        "description": (
            "A satirical essay suggesting the Irish eat their children as a "
            "solution to economic problems — a masterclass in irony and argument."
        ),
        "cover_url": "https://covers.openlibrary.org/b/id/8739158-L.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/1080/pg1080.txt",
        "language": "en",
        "cefr_level": "C1",
        "subject": "Essay",
        "chapter_count": 1,
        "word_count": 3700,
    },
]


# ── Helper Functions ──────────────────────────────────────────────

def _estimate_cefr_from_description(text: str) -> str:
    """Estimate CEFR level from text using word-length heuristics."""
    if not text:
        return "B1"

    words = text.lower().split()
    word_count = len(words)
    if word_count == 0:
        return "B1"

    avg_word_length = sum(len(w.strip(".,;!?\"'")) for w in words) / word_count
    long_words = sum(1 for w in words if len(w.strip(".,;!?\"'")) > 8)
    long_word_ratio = long_words / word_count

    score = (avg_word_length - 3) * 12 + long_word_ratio * 60

    if score < 8:
        return "A1"
    elif score < 18:
        return "A2"
    elif score < 32:
        return "B1"
    elif score < 50:
        return "B2"
    elif score < 70:
        return "C1"
    else:
        return "C2"


def _estimate_cefr_from_subjects(subjects: list) -> Optional[str]:
    """Try to map book subjects/bookshelves to a CEFR level."""
    for subject in subjects:
        normalized = subject.lower()
        for keyword, level in _CEFR_BY_SUBJECT.items():
            if keyword in normalized:
                return level
    return None


def _normalize_gutendex_book(book: dict) -> dict:
    """Convert a Gutendex API result to our Book schema."""
    authors = [a.get("name", "") for a in book.get("authors", [])]
    subjects = book.get("subjects", []) + book.get("bookshelves", [])
    description = "; ".join(book.get("bookshelves", [])[:3]) or ""
    formats = book.get("formats", {})

    download_url = (
        formats.get("text/plain; charset=utf-8")
        or formats.get("text/plain")
        or formats.get("text/html; charset=utf-8")
        or formats.get("text/html")
        or ""
    )
    cover_url = formats.get("image/jpeg") or ""

    # Convert Gutenberg ebooks URL to direct cache URL to avoid 302 redirects
    # e.g., https://www.gutenberg.org/ebooks/11.txt.utf-8 → https://www.gutenberg.org/cache/epub/11/pg11.txt
    book_id = book.get("id", "")
    if book_id and download_url and "gutenberg.org" in download_url:
        download_url = f"https://www.gutenberg.org/cache/epub/{book_id}/pg{book_id}.txt"

    cefr = _estimate_cefr_from_subjects(subjects) or _estimate_cefr_from_description(description)

    return {
        "id": f"gutenberg-{book.get('id', '')}",
        "source": "gutenberg",
        "title": book.get("title", ""),
        "author": ", ".join(authors) if authors else "Unknown",
        "description": description,
        "cover_url": cover_url,
        "download_url": download_url,
        "language": "en",
        "cefr_level": cefr,
        "cefr_info": CEFR_LEVELS.get(cefr, {}),
        "subject": subjects[0] if subjects else "",
        "download_count": book.get("download_count", 0),
        "chapter_count": 0,
        "word_count": 0,
    }


def _normalize_open_library_book(work: dict) -> dict:
    """Convert an Open Library search result to our Book schema."""
    ol_key = work.get("key", "").replace("/works/", "")
    authors = work.get("author_name", [])
    first_sentence = work.get("first_sentence", [])
    description = first_sentence[0] if isinstance(first_sentence, list) and first_sentence else ""
    subjects = work.get("subject", [])[:5]

    cover_id = work.get("cover_i")
    cover_url = f"https://covers.openlibrary.org/b/id/{cover_id}-L.jpg" if cover_id else ""

    cefr = _estimate_cefr_from_subjects(subjects) or _estimate_cefr_from_description(
        description or work.get("title", "")
    )

    return {
        "id": f"ol-{ol_key}",
        "source": "open_library",
        "title": work.get("title", ""),
        "author": ", ".join(authors[:2]) if authors else "Unknown",
        "description": description,
        "cover_url": cover_url,
        "download_url": f"https://openlibrary.org/works/{ol_key}",
        "language": "en",
        "cefr_level": cefr,
        "cefr_info": CEFR_LEVELS.get(cefr, {}),
        "subject": subjects[0] if subjects else "",
        "download_count": work.get("edition_count", 0),
        "chapter_count": work.get("number_of_pages_median", 0),
        "word_count": 0,
    }


async def _fetch_books(q: str, page: int) -> dict:
    """Fetch books from Gutendex and Open Library, merge, deduplicate."""
    books: list[dict] = []

    async with httpx.AsyncClient(timeout=12.0) as client:
        # Gutendex
        try:
            resp = await client.get(
                GUTENDEX_BASE,
                params={"search": q, "mime_type": "text%2F", "page": page},
            )
            if resp.status_code == 200:
                for book in resp.json().get("results", []):
                    if "en" in book.get("languages", []):
                        books.append(_normalize_gutendex_book(book))
        except Exception as e:
            logger.warning("Gutendex error: %s", e)

        # Open Library
        try:
            resp = await client.get(
                f"{OPEN_LIBRARY_BASE}/search.json",
                params={"q": q, "lang": "eng", "limit": 10, "page": page},
            )
            if resp.status_code == 200:
                for work in resp.json().get("docs", []):
                    books.append(_normalize_open_library_book(work))
        except Exception as e:
            logger.warning("Open Library error: %s", e)

    # Deduplicate by normalized title
    seen: set = set()
    unique: list[dict] = []
    for book in books:
        key = book["title"].lower().strip()
        if key not in seen:
            seen.add(key)
            unique.append(book)

    return {"books": unique}


# ── Endpoints ────────────────────────────────────────────────────

@router.get("/recommended", summary="Get curated books by CEFR level")
async def get_recommended_books(
    level: Optional[str] = Query(None, description="CEFR level filter: A1/A2/B1/B2/C1/C2"),
):
    """
    Return a curated list of high-quality public-domain books for English learners.

    Served from hardcoded data — zero API cost, always available offline.
    """
    books = CURATED_BOOKS
    if level and level.upper() in CEFR_LEVELS:
        books = [b for b in CURATED_BOOKS if b["cefr_level"] == level.upper()]

    return {
        "books": [
            {**b, "cefr_info": CEFR_LEVELS.get(b["cefr_level"], {})}
            for b in books
        ],
        "total": len(books),
        "source": "curated",
    }


@router.get("/search", summary="Search books from Gutendex + Open Library")
async def search_books(
    q: str = Query(..., min_length=2, description="Search query"),
    level: Optional[str] = Query(None, description="CEFR level filter"),
    page: int = Query(1, ge=1, description="Page number"),
    db: AsyncSession = Depends(get_db),
):
    """
    Search for English books across Gutendex (Project Gutenberg) and Open Library.

    Results are merged, deduplicated by title, and CEFR-estimated from subjects
    and descriptions. Responses are cached 24h (Redis) + 7d (DB).
    """
    if level and level.upper() not in CEFR_LEVELS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid CEFR level. Valid: {list(CEFR_LEVELS.keys())}",
        )

    cache_key = f"books:search:{q.lower().strip()}:p:{page}"
    cache_service = APICacheService(db)

    try:
        result = await cache_service.get_or_fetch(
            cache_key=cache_key,
            api_name="gutendex",
            fetch_fn=lambda: _fetch_books(q=q, page=page),
            priority=Priority.MEDIUM,
            redis_ttl=86400,    # 24 hours
            db_ttl=604800,      # 7 days
        )

        books: list[dict] = result.data.get("books", [])

        # Filter by CEFR level if requested
        if level:
            books = [b for b in books if b.get("cefr_level") == level.upper()]

        return {
            "books": books,
            "total": len(books),
            "page": page,
            "query": q,
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
    except Exception as e:
        logger.error("Book search error: %s", e)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Book search service temporarily unavailable.",
        )


@router.get("/{book_id}/quiz", summary="Get comprehension quiz for a chapter")
async def get_book_quiz(
    book_id: str,
    chapter: int = Query(1, ge=1, description="Chapter number"),
    db: AsyncSession = Depends(get_db),
):
    """
    Return a comprehension quiz for the given (book, chapter).

    Currently returns a placeholder quiz; full AI generation via
    the AI service will be integrated in a future update.

    Results are cached permanently per (book_id, chapter) pair.
    """
    cache_key = f"books:quiz:{book_id}:ch:{chapter}"
    cache_service = APICacheService(db)

    async def _generate_quiz() -> dict:
        # Stub — replace with call to AI service when available.
        return {
            "questions": [
                {
                    "id": f"{book_id}_ch{chapter}_q1",
                    "question": "What is the main theme explored in this chapter?",
                    "options": [
                        "Identity and self-discovery",
                        "Adventure and exploration",
                        "Friendship and loyalty",
                        "Conflict and resolution",
                    ],
                    "correct_index": 0,
                    "explanation": (
                        "This chapter focuses on themes of identity, exploring how "
                        "the characters define themselves in response to challenges."
                    ),
                },
                {
                    "id": f"{book_id}_ch{chapter}_q2",
                    "question": "Which word from this chapter means 'extremely surprised'?",
                    "options": ["astonished", "confused", "tired", "happy"],
                    "correct_index": 0,
                    "explanation": "'Astonished' means greatly surprised or amazed.",
                },
                {
                    "id": f"{book_id}_ch{chapter}_q3",
                    "question": "What literary device is most prominently used?",
                    "options": ["Simile", "Metaphor", "Foreshadowing", "Alliteration"],
                    "correct_index": 2,
                    "explanation": (
                        "Foreshadowing — hints about future events — is used "
                        "throughout to build tension and anticipation."
                    ),
                },
            ],
            "xp_reward": 25,
            "is_stub": True,
        }

    try:
        result = await cache_service.get_or_fetch(
            cache_key=cache_key,
            api_name="books_quiz",
            fetch_fn=_generate_quiz,
            priority=Priority.LOW,
            redis_ttl=0,        # Not in Redis hot cache
            db_ttl=315360000,   # ~10 years (permanent)
        )

        return {
            "book_id": book_id,
            "chapter": chapter,
            **result.data,
        }

    except Exception as e:
        logger.error("Book quiz error for %s ch%d: %s", book_id, chapter, e)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Quiz generation temporarily unavailable.",
        )
