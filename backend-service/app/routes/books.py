"""
Book API Routes — English Book Reading for Language Learners

Endpoints search Gutendex (Project Gutenberg) and Open Library for free,
public-domain books. CEFR levels are estimated from description text.
Comprehension quizzes are AI-generated per chapter (stub, coming soon).
Curated recommendations are served from hardcoded data (no API cost).

Phase 5: Book Reading Feature.
"""

import logging
import re
from typing import Optional
from urllib.parse import quote, urlparse

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query, status, Request, Response
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

# ── CEFR by Subject (ordered list — more specific keywords checked first) ──
_CEFR_BY_SUBJECT: list[tuple[str, str]] = [
    # A1 — Beginner
    ("easy reader", "A1"), ("fairy tale", "A1"), ("picture book", "A1"), ("nursery", "A1"),
    # A2 — Elementary
    ("children", "A2"), ("juvenile fiction", "A2"), ("fable", "A2"), ("folk tale", "A2"),
    # B1 — Intermediate
    ("short stories", "B1"), ("adventure", "B1"), ("romance", "B1"),
    ("mystery", "B1"), ("detective", "B1"), ("science fiction", "B1"),
    # B2 — Upper Intermediate
    ("historical fiction", "B2"), ("historical", "B2"), ("literary fiction", "B2"),
    ("classic", "B2"), ("drama", "B2"), ("comedy", "B2"), ("gothic", "B2"),
    # C1 — Advanced
    ("philosophy", "C1"), ("essay", "C1"), ("poetry", "C1"),
    ("satire", "C1"), ("tragedy", "C1"), ("criticism", "C1"),
    # C2 — Proficiency
    ("epic poem", "C2"), ("metaphysics", "C2"), ("existentialism", "C2"),
]

# ── Curated English-Learning Books by CEFR Level (4 per level) ───
CURATED_BOOKS = [
    # ── A1 — Beginner ────────────────────────────────────────────
    {
        "id": "gutenberg-2591", "source": "gutenberg",
        "title": "Grimms' Fairy Tales", "author": "Brothers Grimm",
        "description": "Classic fairy tales including Cinderella, Snow White, and Hansel and Gretel — perfect for beginner English learners.",
        "cover_url": "https://www.gutenberg.org/cache/epub/2591/pg2591.cover.medium.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/2591/pg2591.txt",
        "language": "en", "cefr_level": "A1", "subject": "Fairy Tales", "topic": "Fantasy",
        "chapter_count": 45, "word_count": 55000,
    },
    {
        "id": "gutenberg-11339", "source": "gutenberg",
        "title": "Aesop's Fables", "author": "Aesop",
        "description": "Short moral fables featuring animals — ideal for beginners learning through simple, repeated story patterns.",
        "cover_url": "https://www.gutenberg.org/cache/epub/11339/pg11339.cover.medium.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/11339/pg11339.txt",
        "language": "en", "cefr_level": "A1", "subject": "Fables", "topic": "Children",
        "chapter_count": 60, "word_count": 18000,
    },
    {
        "id": "gutenberg-16", "source": "gutenberg",
        "title": "Peter Pan", "author": "J. M. Barrie",
        "description": "The classic tale of a boy who never grows up and takes three children on an adventure to Neverland.",
        "cover_url": "https://www.gutenberg.org/cache/epub/16/pg16.cover.medium.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/16/pg16.txt",
        "language": "en", "cefr_level": "A1", "subject": "Fantasy", "topic": "Fantasy",
        "chapter_count": 17, "word_count": 28000,
    },
    {
        "id": "gutenberg-55", "source": "gutenberg",
        "title": "The Wonderful Wizard of Oz", "author": "L. Frank Baum",
        "description": "Dorothy is swept away to the magical land of Oz and follows the yellow brick road to find her way home.",
        "cover_url": "https://www.gutenberg.org/cache/epub/55/pg55.cover.medium.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/55/pg55.txt",
        "language": "en", "cefr_level": "A1", "subject": "Fantasy", "topic": "Fantasy",
        "chapter_count": 24, "word_count": 39000,
    },
    # ── A2 — Elementary ──────────────────────────────────────────
    {
        "id": "gutenberg-11", "source": "gutenberg",
        "title": "Alice's Adventures in Wonderland", "author": "Lewis Carroll",
        "description": "A young girl named Alice falls into a rabbit hole and embarks on a fantastical adventure in a world of nonsense.",
        "cover_url": "https://www.gutenberg.org/cache/epub/11/pg11.cover.medium.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/11/pg11.txt",
        "language": "en", "cefr_level": "A2", "subject": "Fantasy", "topic": "Fantasy",
        "chapter_count": 12, "word_count": 26500,
    },
    {
        "id": "gutenberg-120", "source": "gutenberg",
        "title": "Treasure Island", "author": "Robert Louis Stevenson",
        "description": "Young Jim Hawkins discovers a treasure map and sets sail on a dangerous adventure with pirates.",
        "cover_url": "https://www.gutenberg.org/cache/epub/120/pg120.cover.medium.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/120/pg120.txt",
        "language": "en", "cefr_level": "A2", "subject": "Adventure", "topic": "Adventure",
        "chapter_count": 34, "word_count": 68000,
    },
    {
        "id": "gutenberg-76", "source": "gutenberg",
        "title": "Adventures of Huckleberry Finn", "author": "Mark Twain",
        "description": "Huck Finn escapes his abusive father and rafts down the Mississippi River with the escaped slave Jim.",
        "cover_url": "https://www.gutenberg.org/cache/epub/76/pg76.cover.medium.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/76/pg76.txt",
        "language": "en", "cefr_level": "A2", "subject": "Adventure", "topic": "Adventure",
        "chapter_count": 43, "word_count": 109000,
    },
    {
        "id": "gutenberg-161", "source": "gutenberg",
        "title": "Sense and Sensibility", "author": "Jane Austen",
        "description": "Two sisters navigate love and heartbreak in 19th-century England with clearer prose than Austen's later works.",
        "cover_url": "https://www.gutenberg.org/cache/epub/161/pg161.cover.medium.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/161/pg161.txt",
        "language": "en", "cefr_level": "A2", "subject": "Romance", "topic": "Romance",
        "chapter_count": 50, "word_count": 119000,
    },
    # ── B1 — Intermediate ────────────────────────────────────────
    {
        "id": "gutenberg-74", "source": "gutenberg",
        "title": "The Adventures of Tom Sawyer", "author": "Mark Twain",
        "description": "The story of a young boy growing up along the Mississippi River, exploring caves and getting into mischief.",
        "cover_url": "https://www.gutenberg.org/cache/epub/74/pg74.cover.medium.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/74/pg74.txt",
        "language": "en", "cefr_level": "B1", "subject": "Adventure", "topic": "Adventure",
        "chapter_count": 35, "word_count": 70000,
    },
    {
        "id": "gutenberg-1342", "source": "gutenberg",
        "title": "Pride and Prejudice", "author": "Jane Austen",
        "description": "A classic novel about manners, morality, and marriage in early 19th-century England.",
        "cover_url": "https://www.gutenberg.org/cache/epub/1342/pg1342.cover.medium.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/1342/pg1342.txt",
        "language": "en", "cefr_level": "B1", "subject": "Romance", "topic": "Romance",
        "chapter_count": 61, "word_count": 122000,
    },
    {
        "id": "gutenberg-1661", "source": "gutenberg",
        "title": "The Adventures of Sherlock Holmes", "author": "Arthur Conan Doyle",
        "description": "Twelve gripping detective stories featuring the brilliant Sherlock Holmes and his faithful companion Dr. Watson.",
        "cover_url": "https://www.gutenberg.org/cache/epub/1661/pg1661.cover.medium.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/1661/pg1661.txt",
        "language": "en", "cefr_level": "B1", "subject": "Mystery", "topic": "Mystery",
        "chapter_count": 12, "word_count": 107000,
    },
    {
        "id": "gutenberg-35", "source": "gutenberg",
        "title": "The Time Machine", "author": "H. G. Wells",
        "description": "A Victorian scientist builds a machine that carries him 800,000 years into the future.",
        "cover_url": "https://www.gutenberg.org/cache/epub/35/pg35.cover.medium.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/35/pg35.txt",
        "language": "en", "cefr_level": "B1", "subject": "Science Fiction", "topic": "Science Fiction",
        "chapter_count": 16, "word_count": 33000,
    },
    # ── B2 — Upper Intermediate ──────────────────────────────────
    {
        "id": "gutenberg-5200", "source": "gutenberg",
        "title": "Metamorphosis", "author": "Franz Kafka",
        "description": "Gregor Samsa wakes to find he has transformed into a monstrous insect — a profound exploration of alienation.",
        "cover_url": "https://www.gutenberg.org/cache/epub/5200/pg5200.cover.medium.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/5200/pg5200.txt",
        "language": "en", "cefr_level": "B2", "subject": "Literary Fiction", "topic": "Fiction",
        "chapter_count": 3, "word_count": 22000,
    },
    {
        "id": "gutenberg-98", "source": "gutenberg",
        "title": "A Tale of Two Cities", "author": "Charles Dickens",
        "description": "Set during the French Revolution, this novel follows characters whose lives are intertwined across London and Paris.",
        "cover_url": "https://www.gutenberg.org/cache/epub/98/pg98.cover.medium.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/98/pg98.txt",
        "language": "en", "cefr_level": "B2", "subject": "Historical Fiction", "topic": "History",
        "chapter_count": 45, "word_count": 135000,
    },
    {
        "id": "gutenberg-174", "source": "gutenberg",
        "title": "The Picture of Dorian Gray", "author": "Oscar Wilde",
        "description": "A vain young man wishes his portrait would age instead of him — with devastating moral consequences.",
        "cover_url": "https://www.gutenberg.org/cache/epub/174/pg174.cover.medium.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/174/pg174.txt",
        "language": "en", "cefr_level": "B2", "subject": "Gothic Fiction", "topic": "Fiction",
        "chapter_count": 20, "word_count": 78000,
    },
    {
        "id": "gutenberg-244", "source": "gutenberg",
        "title": "A Study in Scarlet", "author": "Arthur Conan Doyle",
        "description": "The first Sherlock Holmes novel — a murder mystery that introduces the famous detective and Dr. Watson.",
        "cover_url": "https://www.gutenberg.org/cache/epub/244/pg244.cover.medium.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/244/pg244.txt",
        "language": "en", "cefr_level": "B2", "subject": "Mystery", "topic": "Mystery",
        "chapter_count": 14, "word_count": 43000,
    },
    # ── C1 — Advanced ────────────────────────────────────────────
    {
        "id": "gutenberg-1080", "source": "gutenberg",
        "title": "A Modest Proposal", "author": "Jonathan Swift",
        "description": "A satirical essay suggesting the Irish eat their children — a masterclass in irony and persuasive argument.",
        "cover_url": "https://www.gutenberg.org/cache/epub/1080/pg1080.cover.medium.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/1080/pg1080.txt",
        "language": "en", "cefr_level": "C1", "subject": "Essay", "topic": "Philosophy",
        "chapter_count": 1, "word_count": 3700,
    },
    {
        "id": "gutenberg-219", "source": "gutenberg",
        "title": "Heart of Darkness", "author": "Joseph Conrad",
        "description": "A sailor's voyage up the Congo River becomes a descent into colonial horror and moral ambiguity.",
        "cover_url": "https://www.gutenberg.org/cache/epub/219/pg219.cover.medium.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/219/pg219.txt",
        "language": "en", "cefr_level": "C1", "subject": "Literary Fiction", "topic": "Fiction",
        "chapter_count": 3, "word_count": 38000,
    },
    {
        "id": "gutenberg-1399", "source": "gutenberg",
        "title": "Anna Karenina", "author": "Leo Tolstoy",
        "description": "A tragic portrait of Russian aristocracy — one of the greatest novels ever written about love and society.",
        "cover_url": "https://www.gutenberg.org/cache/epub/1399/pg1399.cover.medium.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/1399/pg1399.txt",
        "language": "en", "cefr_level": "C1", "subject": "Literary Fiction", "topic": "Romance",
        "chapter_count": 239, "word_count": 349000,
    },
    {
        "id": "gutenberg-766", "source": "gutenberg",
        "title": "David Copperfield", "author": "Charles Dickens",
        "description": "Dickens' autobiographical masterpiece — the life of David Copperfield from childhood to maturity.",
        "cover_url": "https://www.gutenberg.org/cache/epub/766/pg766.cover.medium.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/766/pg766.txt",
        "language": "en", "cefr_level": "C1", "subject": "Literary Fiction", "topic": "Fiction",
        "chapter_count": 64, "word_count": 358000,
    },
    # ── C2 — Proficiency ─────────────────────────────────────────
    {
        "id": "gutenberg-2701", "source": "gutenberg",
        "title": "Moby Dick", "author": "Herman Melville",
        "description": "Captain Ahab's obsessive quest to hunt the great white whale — a monumental work of American literature.",
        "cover_url": "https://www.gutenberg.org/cache/epub/2701/pg2701.cover.medium.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/2701/pg2701.txt",
        "language": "en", "cefr_level": "C2", "subject": "Literary Fiction", "topic": "Adventure",
        "chapter_count": 135, "word_count": 206000,
    },
    {
        "id": "gutenberg-2554", "source": "gutenberg",
        "title": "Crime and Punishment", "author": "Fyodor Dostoevsky",
        "description": "A student murders a pawnbroker and grapples with guilt, philosophy, and redemption in 19th-century St. Petersburg.",
        "cover_url": "https://www.gutenberg.org/cache/epub/2554/pg2554.cover.medium.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/2554/pg2554.txt",
        "language": "en", "cefr_level": "C2", "subject": "Literary Fiction", "topic": "Fiction",
        "chapter_count": 52, "word_count": 211000,
    },
    {
        "id": "gutenberg-2600", "source": "gutenberg",
        "title": "War and Peace", "author": "Leo Tolstoy",
        "description": "An epic portrayal of Russian society during the Napoleonic Wars — one of the longest and most complex novels ever written.",
        "cover_url": "https://www.gutenberg.org/cache/epub/2600/pg2600.cover.medium.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/2600/pg2600.txt",
        "language": "en", "cefr_level": "C2", "subject": "Historical Fiction", "topic": "History",
        "chapter_count": 365, "word_count": 580000,
    },
    {
        "id": "gutenberg-26", "source": "gutenberg",
        "title": "Paradise Lost", "author": "John Milton",
        "description": "An epic poem retelling the Biblical story of the Fall of Man — the pinnacle of English literary achievement.",
        "cover_url": "https://www.gutenberg.org/cache/epub/26/pg26.cover.medium.jpg",
        "download_url": "https://www.gutenberg.org/cache/epub/26/pg26.txt",
        "language": "en", "cefr_level": "C2", "subject": "Poetry", "topic": "Poetry",
        "chapter_count": 12, "word_count": 80000,
    },
]


# ── Helper Functions ──────────────────────────────────────────────

def _estimate_cefr_from_description(text: str) -> str:
    """Estimate CEFR from sentence and word complexity (Flesch-Kincaid proxy)."""
    if not text:
        return "B1"
    sentences = [s.strip() for s in re.split(r"[.!?]+", text) if s.strip()]
    sentence_count = max(len(sentences), 1)
    words = [w.strip(".,;:!?\"'()[]") for w in text.split()]
    words = [w for w in words if w]
    word_count = len(words)
    if word_count == 0:
        return "B1"
    avg_word_len = sum(len(w) for w in words) / word_count
    avg_sent_len = word_count / sentence_count
    # Syllable proxy: words with 8+ chars ≈ 3+ syllables
    complex_ratio = sum(1 for w in words if len(w) >= 8) / word_count
    # Weighted score calibrated to CEFR ranges
    score = avg_word_len * 4.8 + complex_ratio * 24.0 + avg_sent_len * 0.3
    if score < 9:
        return "A1"
    elif score < 15:
        return "A2"
    elif score < 22:
        return "B1"
    elif score < 31:
        return "B2"
    elif score < 48:
        return "C1"
    return "C2"


def _estimate_cefr_from_subjects(subjects: list) -> Optional[str]:
    """Try to map book subjects to a CEFR level (first specific match wins)."""
    for subject in subjects:
        normalized = subject.lower()
        for keyword, level in _CEFR_BY_SUBJECT:
            if keyword in normalized:
                return level
    return None


# ── Topic / Genre normalization ────────────────────────────────────
_TOPIC_MAP: list[tuple[str, str]] = [
    ("children", "Children"), ("juvenile", "Children"),
    ("fairy", "Fantasy"), ("fantasy", "Fantasy"), ("magic", "Fantasy"),
    ("mystery", "Mystery"), ("detective", "Mystery"), ("crime", "Mystery"),
    ("romance", "Romance"),
    ("adventure", "Adventure"), ("travel", "Adventure"),
    ("science fiction", "Science Fiction"), ("sci-fi", "Science Fiction"),
    ("historical", "History"), ("history", "History"),
    ("biography", "Biography"), ("autobiography", "Biography"), ("memoir", "Biography"),
    ("philosophy", "Philosophy"), ("essay", "Philosophy"),
    ("poetry", "Poetry"), ("poem", "Poetry"), ("verse", "Poetry"),
    ("fiction", "Fiction"), ("novel", "Fiction"),
]


def _normalize_topic(subjects: list[str]) -> str:
    """Map subjects list to a normalized genre label."""
    for subject in subjects:
        s = subject.lower()
        for keyword, topic in _TOPIC_MAP:
            if keyword in s:
                return topic
    return "Fiction"


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
    topic = _normalize_topic(subjects)

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
        "topic": topic,
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
    topic = _normalize_topic(subjects)

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
        "topic": topic,
        "download_count": work.get("edition_count", 0),
        "chapter_count": work.get("number_of_pages_median", 0),
        "word_count": 0,
    }


async def _fetch_books(q: str, page: int, topic: Optional[str] = None) -> dict:
    """Fetch books from Gutendex and Open Library, merge, deduplicate."""
    books: list[dict] = []

    async with httpx.AsyncClient(timeout=12.0) as client:
        # Gutendex — supports both ?search= and ?topic= natively
        try:
            gutendex_params: dict = {"mime_type": "text%2F", "page": page, "languages": "en"}
            if q:
                gutendex_params["search"] = q
            if topic:
                gutendex_params["topic"] = topic
            resp = await client.get(GUTENDEX_BASE, params=gutendex_params)
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


# ── CORS Proxy for Gutenberg and Book Sources ────────────────────

ALLOWED_PROXY_DOMAINS = {
    "www.gutenberg.org",
    "gutenberg.org",
    "gutendex.com",
    "openlibrary.org",
    "covers.openlibrary.org",
}

def _proxy_book_urls(book: dict, request: Request) -> dict:
    """Rewrite book cover_url and download_url to go through backend proxy to avoid CORS."""
    proxied = book.copy()
    base_url = str(request.base_url).rstrip("/")
    api_prefix = settings.API_V1_PREFIX.strip("/")
    books_prefix = router.prefix.strip("/")
    path_prefix = f"{api_prefix}/{books_prefix}".strip("/")
    
    if book.get("cover_url"):
        cover_url = book["cover_url"]
        if "gutenberg.org" in cover_url:
            proxied["cover_url"] = f"{base_url}/{path_prefix}/proxy/image?url={quote(cover_url)}"
            
    if book.get("download_url"):
        download_url = book["download_url"]
        if "gutenberg.org" in download_url:
            proxied["download_url"] = f"{base_url}/{path_prefix}/proxy/text?url={quote(download_url)}"
            
    return proxied


@router.get("/proxy/image", summary="Proxy book cover images to bypass CORS")
async def proxy_image(url: str = Query(..., description="The image URL to proxy")):
    """
    Proxy book cover images from Gutenberg or Open Library to bypass browser CORS.
    """
    try:
        parsed_url = urlparse(url)
        if parsed_url.netloc not in ALLOWED_PROXY_DOMAINS:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Domain not allowed for proxying."
            )
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid URL."
        )
        
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            resp = await client.get(
                url, 
                headers={"User-Agent": "LexiLingo/1.0 (English learning app; cover-proxy)"},
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
        except httpx.RequestError as e:
            logger.error("HTTP request error proxying image %s: %s", url, e)
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"Failed to reach image source: {str(e)}"
            )
        except Exception as e:
            logger.error("Unexpected error proxying image %s: %s", url, e)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Internal proxy error."
            )


@router.get("/proxy/text", summary="Proxy book plain-text content to bypass CORS")
async def proxy_text(url: str = Query(..., description="The text URL to proxy")):
    """
    Proxy book plain-text content from Gutenberg to bypass browser CORS.
    """
    try:
        parsed_url = urlparse(url)
        if parsed_url.netloc not in ALLOWED_PROXY_DOMAINS:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Domain not allowed for proxying."
            )
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid URL."
        )
        
    async with httpx.AsyncClient(timeout=15.0) as client:
        try:
            resp = await client.get(
                url, 
                headers={"User-Agent": "LexiLingo/1.0 (English learning app; text-proxy)"},
                follow_redirects=True
            )
            if resp.status_code != 200:
                raise HTTPException(
                    status_code=resp.status_code,
                    detail=f"Failed to fetch text: HTTP {resp.status_code}"
                )
            
            content_type = resp.headers.get("content-type", "text/plain; charset=utf-8")
            
            return Response(
                content=resp.content,
                media_type=content_type,
                headers={
                    "Cache-Control": "public, max-age=86400",  # Cache for 24h
                }
            )
        except httpx.RequestError as e:
            logger.error("HTTP request error proxying text %s: %s", url, e)
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"Failed to reach text source: {str(e)}"
            )
        except Exception as e:
            logger.error("Unexpected error proxying text %s: %s", url, e)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Internal proxy error."
            )


# ── Endpoints ────────────────────────────────────────────────────

@router.get("/recommended", summary="Get curated books by CEFR level")
async def get_recommended_books(
    request: Request,
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
            _proxy_book_urls({**b, "cefr_info": CEFR_LEVELS.get(b["cefr_level"], {})}, request)
            for b in books
        ],
        "total": len(books),
        "source": "curated",
    }


@router.get("/search", summary="Search books from Gutendex + Open Library")
async def search_books(
    request: Request,
    q: str = Query(..., min_length=2, description="Search query"),
    level: Optional[str] = Query(None, description="CEFR level filter"),
    topic: Optional[str] = Query(None, description="Genre filter (Fiction/Fantasy/Mystery/etc.)"),
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

    cache_key = f"books:search:{q.lower().strip()}:t:{topic or 'all'}:p:{page}"
    cache_service = APICacheService(db)

    try:
        result = await cache_service.get_or_fetch(
            cache_key=cache_key,
            api_name="gutendex",
            fetch_fn=lambda: _fetch_books(q=q, page=page, topic=topic),
            priority=Priority.MEDIUM,
            redis_ttl=86400,    # 24 hours
            db_ttl=604800,      # 7 days
        )

        books: list[dict] = result.data.get("books", [])

        # Filter by CEFR level if requested
        if level:
            books = [b for b in books if b.get("cefr_level") == level.upper()]
        # Filter by genre/topic if requested
        if topic:
            books = [b for b in books if b.get("topic", "").lower() == topic.lower()]

        return {
            "books": [_proxy_book_urls(b, request) for b in books],
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


# ── Browse defaults per CEFR level ───────────────────────────────
LEVEL_DEFAULT_TOPICS = {
    "A1": "children",
    "A2": "adventure",
    "B1": "fiction",
    "B2": "historical",
    "C1": "philosophy",
    "C2": "classic",
}


@router.get("/browse", summary="Browse books by CEFR level with lazy pagination")
async def browse_books(
    request: Request,
    level: str = Query(..., description="CEFR level: A1/A2/B1/B2/C1/C2"),
    page: int = Query(1, ge=1, description="Page number"),
    topic: Optional[str] = Query(None, description="Genre override"),
    db: AsyncSession = Depends(get_db),
):
    """
    Browse public-domain books by CEFR level with index-based pagination.

    Used by the Flutter app to lazy-load additional books as the user
    scrolls to the end of a level section. Cached 24h (Redis) + 7d (DB).
    """
    level = level.upper()
    if level not in CEFR_LEVELS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid level. Valid: {list(CEFR_LEVELS.keys())}",
        )

    search_topic = topic or LEVEL_DEFAULT_TOPICS.get(level, "fiction")
    cache_key = f"books:browse:{level.lower()}:t:{search_topic.lower()}:p:{page}"
    cache_service = APICacheService(db)

    try:
        result = await cache_service.get_or_fetch(
            cache_key=cache_key,
            api_name="gutendex",
            fetch_fn=lambda: _fetch_books(q="", page=page, topic=search_topic),
            priority=Priority.LOW,
            redis_ttl=86400,
            db_ttl=604800,
        )
        books: list[dict] = result.data.get("books", [])
        return {
            "books": [_proxy_book_urls(b, request) for b in books],
            "level": level,
            "page": page,
            "topic": search_topic,
            "total": len(books),
            "source": result.source,
        }
    except QuotaExhaustedError as e:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=str(e),
            headers={"Retry-After": e.reset_time},
        )
    except Exception as e:
        logger.error("Book browse error: %s", e)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Book browse service temporarily unavailable.",
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
