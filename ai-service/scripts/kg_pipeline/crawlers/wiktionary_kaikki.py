"""
Stream the kaikki.org English Wiktionary JSONL dump into KG CSV rows.

Why kaikki.org instead of the Wiktionary API?
  - Wiktionary API pagination = ~700k API calls = 4-8 hours
  - kaikki.org pre-extracts structured data from wikitext → 1 download
  - File: ~450 MB gz → ~1.8 GB JSONL → ~1.3M English entries

Entry format (each line is one JSON object):
  {
    "word": "abandon",
    "pos": "verb",
    "lang_code": "en",
    "senses": [{"glosses": ["To give up completely..."], "tags": [...]}],
    "sounds": [{"ipa": "/æ.bæn.dən/"}],
    "forms": [{"form": "abandons", "tags": ["singular"]}],
    "topics": ["psychology"],
    "categories": [...]
  }
"""

import csv
import gzip
import json
import logging
import re
import urllib.request
from pathlib import Path
from typing import Tuple

from tqdm import tqdm

from config import (
    KAIKKI_DUMP_URL,
    KAIKKI_LOCAL,
    KG_RAW_DIR,
    PROGRESS_DIR,
)

logger = logging.getLogger(__name__)

# POS → short code used in node IDs
_POS_CODE = {
    "noun": "n",
    "verb": "v",
    "adjective": "j",
    "adverb": "r",
    "phrase": "ph",
    "idiom": "id",
    "proverb": "pv",
    "interjection": "ij",
    "conjunction": "cj",
    "preposition": "pp",
    "determiner": "det",
    "numeral": "num",
    "particle": "part",
    "affix": "affix",
}

# CEFR tags embedded in Wiktionary entries
_CEFR_RE = re.compile(r"\b([ABC][12])\b")

# Slugify for stable IDs
_SLUG_RE = re.compile(r"[^a-z0-9_]")


def _slugify(text: str) -> str:
    return _SLUG_RE.sub("_", text.lower().strip())[:80]


def _extract_cefr(entry: dict) -> str:
    """Look for CEFR level in tags/categories; fall back to B1."""
    for sense in entry.get("senses", []):
        for tag in sense.get("tags", []):
            m = _CEFR_RE.search(tag.upper())
            if m:
                return m.group(1)
    for cat in entry.get("categories", []):
        m = _CEFR_RE.search(str(cat).upper())
        if m:
            return m.group(1)
    return "B1"


def _download_dump() -> None:
    if KAIKKI_LOCAL.exists() and KAIKKI_LOCAL.stat().st_size > 1_000_000:
        logger.info("Kaikki dump already present: %s", KAIKKI_LOCAL)
        return
    logger.info("Downloading kaikki.org English dump (~450 MB) …")
    KG_RAW_DIR.mkdir(parents=True, exist_ok=True)

    def _progress(block_num: int, block_size: int, total_size: int) -> None:
        downloaded = block_num * block_size
        if total_size > 0:
            pct = min(downloaded / total_size * 100, 100)
            print(f"\r  {pct:.1f}%  {downloaded // 1_048_576} MB / {total_size // 1_048_576} MB", end="", flush=True)

    urllib.request.urlretrieve(KAIKKI_DUMP_URL, KAIKKI_LOCAL, reporthook=_progress)
    print()
    logger.info("Download complete: %s", KAIKKI_LOCAL)


def extract(nodes_csv: Path, edges_csv: Path, cefr_map: dict[str, str] | None = None) -> Tuple[int, int]:
    """
    Stream kaikki dump → append to nodes/edges CSV files.

    Args:
        cefr_map: optional {word → CEFR level} from cefr_lists stage;
                  used to override kaikki CEFR when available (more accurate).
    Returns (node_count, edge_count).
    """
    checkpoint = PROGRESS_DIR / "wiktionary.done"
    if checkpoint.exists():
        logger.info("Wiktionary stage already done — skipping (delete %s to re-run)", checkpoint)
        return 0, 0

    _download_dump()

    node_count = 0
    edge_count = 0
    seen: set[str] = set()

    with (
        gzip.open(KAIKKI_LOCAL, "rt", encoding="utf-8") as gz,
        open(nodes_csv, "a", newline="", encoding="utf-8") as nf,
        open(edges_csv, "a", newline="", encoding="utf-8") as ef,
    ):
        nw = csv.writer(nf)
        ew = csv.writer(ef)

        for raw_line in tqdm(gz, desc="Wiktionary entries", unit="entry", mininterval=2.0):
            raw_line = raw_line.strip()
            if not raw_line:
                continue
            try:
                entry = json.loads(raw_line)
            except json.JSONDecodeError:
                continue

            # Only English entries
            if entry.get("lang_code") != "en":
                continue

            word: str = entry.get("word", "").strip()
            if not word or len(word) > 80:
                continue

            pos: str = entry.get("pos", "noun")
            pos_code = _POS_CODE.get(pos, "w")
            node_id = f"wikt:{pos_code}.{_slugify(word)}"

            # Skip if already seen (a word can appear multiple times with diff senses)
            if node_id in seen:
                continue
            seen.add(node_id)

            # CEFR: prefer external list over entry-embedded tag
            level = (cefr_map or {}).get(word.lower()) or _extract_cefr(entry)

            # Build keywords from senses
            glosses = [
                g
                for sense in entry.get("senses", [])
                for g in sense.get("glosses", [])
            ]
            keywords = f"{word} " + " ".join(glosses[:2])[:200]

            # Title = first gloss (truncated) or word itself
            title = glosses[0][:100] if glosses else word

            nw.writerow([node_id, title, keywords, level])
            node_count += 1

            # Edges: related forms (derived terms)
            for derived in entry.get("derived", []):
                d_word = (derived.get("word") or "").strip()
                if not d_word or len(d_word) > 80:
                    continue
                d_id = f"wikt:{pos_code}.{_slugify(d_word)}"
                ew.writerow([d_id, node_id, "derived_from"])
                edge_count += 1

            # Edges: explicitly listed synonyms / antonyms
            for rel_type, kaikki_key in [("synonym_of", "synonyms"), ("antonym_of", "antonyms")]:
                for rel in entry.get(kaikki_key, []):
                    r_word = (rel.get("word") or "").strip()
                    if not r_word:
                        continue
                    r_id = f"wikt:{pos_code}.{_slugify(r_word)}"
                    ew.writerow([node_id, r_id, rel_type])
                    edge_count += 1

    PROGRESS_DIR.mkdir(parents=True, exist_ok=True)
    checkpoint.touch()
    logger.info("Wiktionary done — %d nodes, %d edges", node_count, edge_count)
    return node_count, edge_count
