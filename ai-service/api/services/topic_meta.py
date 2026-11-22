"""Category and icon for a topic, from its title: what the admin would otherwise pick by hand.

The icon keys are the ones the Flutter app draws (`TopicIconResolver`) and the
admin picker offers. A topic's `icon_key` wins in the app; without one the
app falls back to the category, so every category is also a valid icon key.
"""

from __future__ import annotations

import re
from typing import Any, Iterable

TOPIC_CATEGORIES: tuple[str, ...] = (
    "travel", "work", "business", "services", "health", "food", "social", "finance",
    "shopping", "education", "technology", "housing", "culture", "leisure", "media",
    "emergency", "environment", "daily_life",
)

ICON_KEYS: tuple[str, ...] = (
    *TOPIC_CATEGORIES,
    "hotel", "directions", "transport", "cafe", "doctor", "library", "classroom",
    "internet", "repair", "achievement", "ai", "chat",
)

DEFAULT_CATEGORY = "daily_life"
DEFAULT_ICON = "chat"

# (icon_key, category, keywords). First match wins a tie; a multi-word keyword counts double.
_RULES: tuple[tuple[str, str, tuple[str, ...]], ...] = (
    ("hotel", "travel", ("hotel", "hostel", "resort", "concierge", "front desk", "room service", "booking a room", "hotel check-in")),
    ("directions", "travel", ("directions", "get lost", "map", "navigate", "landmark", "street", "downtown", "which way")),
    ("transport", "travel", ("train", "bus", "taxi", "subway", "metro", "ticket", "car rental", "rental", "ride", "station", "traffic", "public transport")),
    ("emergency", "emergency", ("emergency", "police", "fire", "accident", "ambulance", "urgent", "theft", "stolen", "lost wallet", "first aid")),
    ("travel", "travel", ("travel", "trip", "tour", "tourist", "passport", "visa", "customs", "immigration", "airport", "flight", "luggage", "baggage", "vacation", "holiday", "itinerary", "sightseeing")),
    ("doctor", "health", ("doctor", "dentist", "dental", "pharmacy", "symptom", "medicine", "prescription", "hospital", "nurse", "clinic", "checkup", "injury", "toothache", "medical", "doctor's office")),
    ("health", "health", ("health", "gym", "fitness", "fitness class", "diet", "exercise", "yoga", "wellness", "sleep", "mental health", "therapy", "stress")),
    ("library", "education", ("library", "librarian", "borrow", "book club")),
    ("classroom", "education", ("classroom", "lesson", "homework", "lecture", "tutor")),
    ("education", "education", ("school", "class", "teacher", "student", "university", "college", "exam", "scholarship", "study", "course", "campus")),
    ("internet", "technology", ("wifi", "internet", "broadband", "router", "network", "phone plan", "data plan", "subscription")),
    ("ai", "technology", ("artificial intelligence", "chatbot", "machine learning", "ai")),
    ("technology", "technology", ("computer", "software", "app", "laptop", "bug", "code", "programming", "tech", "cloud", "password", "website", "developer", "demo", "privacy", "cyber*", "security", "settings", "electronics", "data")),
    ("repair", "services", ("repair", "fix", "broken", "plumber", "electrician", "mechanic", "maintenance", "leak")),
    ("housing", "housing", ("neighborhood", "apartment", "rent", "lease", "landlord", "tenant", "moving", "furniture", "house", "flat", "roommate", "utility bill")),
    ("services", "services", ("customer service", "customer support", "support", "customer", "complaint", "cleaning", "laundry", "delivery", "post office", "salon", "haircut", "installation", "booking")),
    ("cafe", "food", ("coffee", "cafe", "barista", "tea", "latte")),
    ("food", "food", ("restaurant", "menu", "order food", "dinner", "lunch", "breakfast", "recipe", "cook*", "cooking class", "bakery", "food", "dish", "waiter", "cake", "ingredient", "grocery", "dietary restrictions", "allerg*")),
    ("shopping", "shopping", ("shop", "store", "buy", "price", "discount", "refund", "return", "size", "clothes", "fitting", "receipt", "market", "mall", "supermarket", "warranty", "return*", "online order")),
    ("finance", "finance", ("bank", "loan", "budget", "tax", "insurance", "invoice", "bill", "credit", "payment", "mortgage", "saving", "investment", "money", "account")),
    ("business", "business", ("professional", "networking", "startup", "sales", "marketing", "negotiation", "contract", "pitch", "investor", "stakeholder", "partnership", "client")),
    ("work", "work", ("networking event", "job", "interview", "meeting", "boss", "colleague", "salary", "office", "presentation", "resume", "career", "project", "deadline", "remote work", "performance review", "promotion", "workplace", "team")),
    ("media", "media", ("news interview", "news report", "news", "podcast", "radio", "journalist", "broadcast", "tv", "video", "headline", "documentary")),
    ("culture", "culture", ("museum", "art", "festival", "tradition", "history", "theater", "gallery", "heritage", "ceremony")),
    ("leisure", "leisure", ("hobby", "sport", "football", "game", "movie", "weekend", "hiking", "camping", "concert", "club")),
    ("social", "social", ("friend", "party", "invite", "introduction", "small talk", "family", "wedding", "date", "neighbor", "volunteer*", "community", "event")),
    ("environment", "environment", ("climate", "recycle", "pollution", "weather", "nature", "energy", "green", "plastic", "sustainab*")),
    ("achievement", "education", ("achievement", "award", "graduation", "certificate", "goal")),
    ("daily_life", "daily_life", ("daily routine", "morning routine", "chores", "everyday", "habit")),
)


def _words(text: str) -> str:
    return f" {re.sub(r'[^a-z0-9]+', ' ', text.lower()).strip()} "


def _hit(keyword: str, haystack: str) -> bool:
    """Whole-word match, tolerant of a plural ("hobby" ~ "hobbies"); a trailing * makes it a prefix."""
    prefix = keyword.endswith("*")
    needle = _words(keyword.rstrip("*")).strip()
    if not needle:
        return False
    if prefix:
        return f" {needle}" in haystack
    stem = needle[:-1] + "(?:y|ies)" if needle.endswith("y") else needle + "(?:s|es)?"
    return re.search(rf" {stem} ", haystack) is not None


def infer_topic_meta(title: str, tags: Iterable[str] = (), notes: str = "") -> dict[str, Any]:
    """{"category", "icon_key", "confidence": "high"|"low", "matched": [...]} for a topic title.

    Rule-based on purpose: instant in a form field, free, and the same answer
    every time. With nothing to go on it returns the generic chat icon and says so.
    """
    haystack = _words(" ".join([title or "", *list(tags), notes or ""]))
    scored: list[tuple[int, str, str, list[str]]] = []
    for icon, category, keywords in _RULES:
        matched = [k for k in keywords if _hit(k, haystack)]
        score = sum(2 if " " in k.strip() else 1 for k in matched)
        if score:
            scored.append((score, icon, category, matched))
    if not scored:
        return {"category": DEFAULT_CATEGORY, "icon_key": DEFAULT_ICON, "confidence": "low", "matched": []}
    best = max(scored, key=lambda row: row[0])  # max keeps the earlier, more specific rule on a tie
    runner_up = max((row[0] for row in scored if row is not best), default=0)
    score, icon, category, matched = best
    return {
        "category": category,
        "icon_key": icon,
        # Sure only when one rule clearly beats the rest; a tie means the title could be either.
        "confidence": "high" if score > runner_up else "low",
        "matched": matched,
    }


def resolve_icon_key(icon_key: str | None, category: str | None) -> str:
    """The icon the app will draw: a known icon_key, else the category, else the generic one."""
    key = (icon_key or "").strip().lower().replace(" ", "_")
    if key in ICON_KEYS:
        return key
    cat = (category or "").strip().lower().replace(" ", "_")
    return cat if cat in ICON_KEYS else DEFAULT_ICON
