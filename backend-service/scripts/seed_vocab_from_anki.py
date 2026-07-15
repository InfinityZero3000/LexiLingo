"""
Seed Vocabulary from Anki .apkg File
=====================================
Parses a .apkg file (ZIP containing SQLite) and inserts all notes
into `vocabulary_items` as the master word list for flashcard topics.

Features:
  - Skips duplicates (safe to re-run — upserts on word)
  - Auto-maps CEFR level from card rank (first 500→A1, 501-1500→A2, etc.)
  - Extracts word, definition, IPA pronunciation, part-of-speech from Anki fields
  - Strips HTML tags from Anki card content
  - Tags each word with {"source": "anki_5000", "topic": <detected topic>}

Run:
    cd backend-service
    venv/bin/python3 -m scripts.seed_vocab_from_anki /path/to/5000_English_Word_Anki.apkg

    # Dry-run (print first 20 parsed words, no DB write):
    venv/bin/python3 -m scripts.seed_vocab_from_anki /path/to/file.apkg --dry-run
"""

import sys
import os
import re
import json
import uuid
import asyncio
import sqlite3
import zipfile
import tempfile
import argparse
import logging
from pathlib import Path
from html.parser import HTMLParser

backend_path = Path(__file__).parent.parent
sys.path.insert(0, str(backend_path))

from sqlalchemy import select
from app.core.database import AsyncSessionLocal
from app.models.vocabulary import VocabularyItem, PartOfSpeech, DifficultyLevel

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)


# ─── CEFR rank bands (by position in the 5000-word frequency list) ────────────
#
# Word frequency rank → CEFR approximation (Oxford / Cambridge mapping):
#   1–500   → A1  (most common, everyday words)
#   501–1500 → A2
#   1501–2500 → B1
#   2501–3500 → B2
#   3501–4500 → C1
#   4501+    → C2
#
RANK_TO_CEFR: list[tuple[int, str]] = [
    (500,  "A1"),
    (1500, "A2"),
    (2500, "B1"),
    (3500, "B2"),
    (4500, "C1"),
]


def rank_to_cefr(rank: int) -> str:
    for threshold, level in RANK_TO_CEFR:
        if rank <= threshold:
            return level
    return "C2"


# ─── Part-of-speech keyword mapping ──────────────────────────────────────────

_POS_KEYWORDS: list[tuple[str, str]] = [
    ("noun",        "noun"),
    ("verb",        "verb"),
    ("adjective",   "adjective"),
    ("adj",         "adjective"),
    ("adverb",      "adverb"),
    ("adv",         "adverb"),
    ("pronoun",     "pronoun"),
    ("preposition", "preposition"),
    ("prep",        "preposition"),
    ("conjunction", "conjunction"),
    ("conj",        "conjunction"),
    ("interjection","interjection"),
    ("phrase",      "phrase"),
]

_VALID_POS = {p.value for p in PartOfSpeech}


def detect_pos(text: str) -> str:
    """Return a PartOfSpeech value detected from free text, defaulting to 'noun'."""
    lower = text.lower()
    for keyword, pos in _POS_KEYWORDS:
        if keyword in lower:
            return pos
    return "noun"


# ─── HTML strip ──────────────────────────────────────────────────────────────

class _HTMLStripper(HTMLParser):
    def __init__(self):
        super().__init__()
        self._parts: list[str] = []

    def handle_data(self, data: str):
        self._parts.append(data)

    def get_text(self) -> str:
        return " ".join(self._parts).strip()


def strip_html(raw: str) -> str:
    s = _HTMLStripper()
    s.feed(raw)
    return re.sub(r"\s+", " ", s.get_text()).strip()


# ─── Anki .apkg parser ───────────────────────────────────────────────────────

def extract_anki_notes(apkg_path: str) -> list[dict]:
    """
    Extract all notes from an .apkg file.
    Returns list of dicts: {rank, word, definition, ipa, pos_raw, tags_raw, fields}
    """
    notes: list[dict] = []

    with tempfile.TemporaryDirectory() as tmp:
        # .apkg is a ZIP — extract the SQLite database
        with zipfile.ZipFile(apkg_path, "r") as zf:
            members = zf.namelist()
            logger.info(f"apkg contains: {members}")

            # Anki 2.x uses "collection.anki2", Anki 21+ may use "collection.anki21"
            db_name = None
            for name in ("collection.anki21", "collection.anki2"):
                if name in members:
                    db_name = name
                    break

            if not db_name:
                raise ValueError(f"No Anki collection found in {apkg_path}. Files: {members}")

            db_path = os.path.join(tmp, db_name)
            zf.extract(db_name, tmp)

        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()

        # Get the note model (field names) from the col table
        cur.execute("SELECT models FROM col")
        col_row = cur.fetchone()
        models_json: dict = json.loads(col_row["models"]) if col_row else {}

        # Build field-name map: model_id → [field_name, ...]
        model_fields: dict[str, list[str]] = {}
        for mid, model in models_json.items():
            field_names = [f["name"] for f in model.get("flds", [])]
            model_fields[mid] = field_names
            logger.info(f"Model '{model.get('name')}' fields: {field_names}")

        # Read all notes ordered by id (id = creation timestamp = roughly frequency order)
        cur.execute("SELECT id, mid, tags, flds FROM notes ORDER BY id ASC")
        rows = cur.fetchall()
        conn.close()

        logger.info(f"Found {len(rows)} notes in deck")

        for rank, row in enumerate(rows, start=1):
            mid = str(row["mid"])
            field_names = model_fields.get(mid, [])
            raw_fields = row["flds"].split("\x1f")
            fields = {
                (field_names[i] if i < len(field_names) else f"field_{i}"): strip_html(raw_fields[i])
                for i in range(len(raw_fields))
            }

            tags_raw = (row["tags"] or "").strip()

            notes.append({
                "rank": rank,
                "fields": fields,
                "tags_raw": tags_raw,
                "field_names": field_names,
            })

    return notes


# ─── Field interpreter ────────────────────────────────────────────────────────
#
# Common Anki English vocab deck field layouts:
#   [Word, Definition]
#   [Word, IPA, Definition, Part of Speech, Example]
#   [Front, Back]
#   [Expression, Meaning, Reading, Example]
#
def interpret_note(note: dict) -> dict | None:
    """
    Map raw Anki fields → structured vocab record.
    Returns None if the note looks invalid (empty word/definition).
    """
    fields = note["fields"]
    keys = list(fields.keys())

    def get(*names: str, fallback: str = "") -> str:
        for name in names:
            # exact match
            if name in fields and fields[name]:
                return fields[name]
            # case-insensitive prefix match
            for k in keys:
                if k.lower().startswith(name.lower()) and fields[k]:
                    return fields[k]
        return fallback

    # Word — first field is almost always the word
    word = get("Word", "Front", "Expression", "Vocabulary", "English", keys[0] if keys else "")
    word = word.strip(".,;: \n")

    if not word:
        return None

    # Definition — second field or "Back"/"Meaning"/"Definition"
    definition = get("Definition", "Meaning", "Back", "Back Extra", "Explanation",
                     keys[1] if len(keys) > 1 else "")

    if not definition:
        return None

    # Pronunciation / IPA
    ipa = get("IPA", "Pronunciation", "Phonetic", "Reading")
    # Strip square brackets often used: [ˈhɛloʊ] → ˈhɛloʊ
    ipa = re.sub(r"^[\[/]|[\]/]$", "", ipa).strip()
    if len(ipa) > 100:
        ipa = ipa[:100]

    # Part of speech — from dedicated field or parsed from definition
    pos_field = get("Part of Speech", "PartOfSpeech", "Type", "POS", "Grammar")
    pos = detect_pos(pos_field or definition)

    # Example sentence
    example = get("Example", "Sentence", "Usage", "Context", "Example Sentence")

    # Topic tags from Anki tags
    tags_raw = note["tags_raw"]
    topic_tags = [t for t in tags_raw.split() if t and not t.startswith("leech")]

    return {
        "rank": note["rank"],
        "word": word,
        "definition": definition,
        "pronunciation": ipa or None,
        "pos": pos,
        "example": example or None,
        "topic_tags": topic_tags,
    }


# ─── DB seeder ────────────────────────────────────────────────────────────────

async def seed(records: list[dict], dry_run: bool = False) -> None:
    if dry_run:
        logger.info("=== DRY RUN — first 20 records ===")
        for r in records[:20]:
            print(json.dumps(r, ensure_ascii=False, indent=2))
        logger.info(f"Total parsed: {len(records)}")
        return

    async with AsyncSessionLocal() as session:
        # Load all existing words to skip duplicates (safe re-run)
        existing_result = await session.execute(
            select(VocabularyItem.word)
        )
        existing_words: set[str] = {row[0].lower() for row in existing_result.fetchall()}
        logger.info(f"Existing words in DB: {len(existing_words)}")

        total_records = len(records)
        inserted = 0
        skipped = 0
        batch_size = 200
        new_items: list[VocabularyItem] = []

        for r in records:
            if r["word"].lower() in existing_words:
                skipped += 1
                continue

            cefr = rank_to_cefr(r["rank"])
            tags_payload: dict = {"source": "anki_5000"}
            if r["topic_tags"]:
                tags_payload["anki_tags"] = r["topic_tags"]

            # Build translation JSON if example sentence available
            translation_payload = None
            if r.get("example"):
                translation_payload = {"examples": [r["example"]]}

            item = VocabularyItem(
                id=uuid.uuid4(),
                word=r["word"][:255],
                definition=r["definition"],
                translation=translation_payload,
                pronunciation=r.get("pronunciation"),
                audio_url=None,
                part_of_speech=r["pos"],
                difficulty_level=cefr,
                usage_frequency=max(0, total_records - r["rank"] + 1),
                tags=tags_payload,
            )
            new_items.append(item)
            existing_words.add(r["word"].lower())  # prevent intra-batch dupes

        logger.info(f"New words to insert: {len(new_items)}, already present: {skipped}")

        for i in range(0, len(new_items), batch_size):
            batch = new_items[i : i + batch_size]
            session.add_all(batch)
            await session.commit()
            inserted += len(batch)
            logger.info(f"  Inserted batch {i // batch_size + 1} ({len(batch)} words, total {inserted}/{len(new_items)})")

        logger.info(f"Done — {inserted} inserted, {skipped} skipped (duplicates)")


# ─── Entrypoint ───────────────────────────────────────────────────────────────

async def main(apkg_path: str, dry_run: bool) -> None:
    logger.info(f"Parsing {apkg_path} ...")
    raw_notes = extract_anki_notes(apkg_path)

    records: list[dict] = []
    for note in raw_notes:
        r = interpret_note(note)
        if r:
            records.append(r)

    logger.info(f"Parsed {len(records)} valid records out of {len(raw_notes)} notes")
    await seed(records, dry_run=dry_run)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Seed vocabulary_items from Anki .apkg")
    parser.add_argument("apkg", help="Path to the .apkg file")
    parser.add_argument("--dry-run", action="store_true", help="Print parsed records, skip DB write")
    args = parser.parse_args()

    if not Path(args.apkg).exists():
        print(f"ERROR: File not found: {args.apkg}", file=sys.stderr)
        sys.exit(1)

    asyncio.run(main(args.apkg, dry_run=args.dry_run))
