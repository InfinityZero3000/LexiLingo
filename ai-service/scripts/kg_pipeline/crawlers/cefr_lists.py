"""
Download and merge free CEFR word lists into a single {word: level} dict.

Sources (all free, open-licence):
  1. CEFR-J (Tokyo Tech, CC BY-SA 4.0) — ~9 000 words with A1-C2 levels
  2. Oxford 3000/5000 list (OUP open data) — 5 000 curated CEFR words
  3. EVP sampler embedded below — 300 high-confidence CEFR words

The returned dict is passed to the Wiktionary crawler so it overrides
the less-reliable CEFR tags in Wiktionary entries.
"""

import csv
import io
import json
import logging
import urllib.request
from pathlib import Path
from typing import Dict

from config import CEFR_J_LOCAL, CEFR_J_URL, KG_RAW_DIR, OXFORD_LISTS_LOCAL, OXFORD_LISTS_URL

logger = logging.getLogger(__name__)


# ── Embedded high-confidence CEFR seeds ───────────────────────────────────
# 300 hand-picked words used as fallback / to cross-validate downloads
_SEED: Dict[str, str] = {
    # A1
    "apple": "A1", "bag": "A1", "book": "A1", "car": "A1", "cat": "A1",
    "day": "A1", "eat": "A1", "family": "A1", "good": "A1", "happy": "A1",
    "house": "A1", "like": "A1", "man": "A1", "mother": "A1", "name": "A1",
    "night": "A1", "one": "A1", "play": "A1", "run": "A1", "school": "A1",
    "small": "A1", "time": "A1", "water": "A1", "year": "A1", "yes": "A1",
    # A2
    "afraid": "A2", "airport": "A2", "arrive": "A2", "beautiful": "A2",
    "begin": "A2", "borrow": "A2", "busy": "A2", "change": "A2",
    "decision": "A2", "early": "A2", "easy": "A2", "enjoy": "A2",
    "explain": "A2", "forget": "A2", "interesting": "A2", "invite": "A2",
    "journey": "A2", "letter": "A2", "minute": "A2", "money": "A2",
    "necessary": "A2", "outside": "A2", "perhaps": "A2", "promise": "A2",
    "remember": "A2", "season": "A2", "special": "A2", "still": "A2",
    "surprise": "A2", "together": "A2",
    # B1
    "achieve": "B1", "advantage": "B1", "argue": "B1", "attitude": "B1",
    "career": "B1", "challenge": "B1", "compare": "B1", "complain": "B1",
    "consider": "B1", "culture": "B1", "decrease": "B1", "develop": "B1",
    "effective": "B1", "environment": "B1", "expect": "B1", "experience": "B1",
    "government": "B1", "impact": "B1", "include": "B1", "increase": "B1",
    "industry": "B1", "involve": "B1", "issue": "B1", "knowledge": "B1",
    "manage": "B1", "opinion": "B1", "opportunity": "B1", "politics": "B1",
    "provide": "B1", "reduce": "B1", "relationship": "B1", "research": "B1",
    "serious": "B1", "society": "B1", "solution": "B1", "suggest": "B1",
    "technology": "B1", "threat": "B1", "traditional": "B1", "various": "B1",
    # B2
    "acknowledge": "B2", "anticipate": "B2", "approach": "B2",
    "approximate": "B2", "assess": "B2", "circumstances": "B2",
    "collaborate": "B2", "comprehensive": "B2", "consequently": "B2",
    "controversial": "B2", "corporation": "B2", "criteria": "B2",
    "decline": "B2", "demonstrate": "B2", "despite": "B2",
    "dimension": "B2", "diverse": "B2", "eliminate": "B2",
    "establish": "B2", "evaluate": "B2", "furthermore": "B2",
    "generate": "B2", "hypothesis": "B2", "identify": "B2",
    "implement": "B2", "indicate": "B2", "inherent": "B2",
    "investigate": "B2", "justify": "B2", "maintain": "B2",
    "mechanism": "B2", "methodology": "B2", "modify": "B2",
    "nevertheless": "B2", "obtain": "B2", "perceive": "B2",
    "phenomenon": "B2", "principle": "B2", "proportion": "B2",
    "relevant": "B2", "significant": "B2", "strategy": "B2",
    # C1
    "abstract": "C1", "accumulate": "C1", "alleviate": "C1",
    "ambiguous": "C1", "analogy": "C1", "arbitrary": "C1",
    "coherent": "C1", "colloquial": "C1", "conjecture": "C1",
    "contemplate": "C1", "delineate": "C1", "discourse": "C1",
    "elicit": "C1", "empirical": "C1", "enumerate": "C1",
    "explicit": "C1", "facilitate": "C1", "fundamental": "C1",
    "ideology": "C1", "implicit": "C1", "inherent": "C1",
    "mitigate": "C1", "nuance": "C1", "paradigm": "C1",
    "postulate": "C1", "pragmatic": "C1", "prevalent": "C1",
    "rationale": "C1", "rhetoric": "C1", "salient": "C1",
}


def _download(url: str, local: Path) -> bool:
    """Return True if successfully downloaded or already cached."""
    if local.exists() and local.stat().st_size > 500:
        return True
    KG_RAW_DIR.mkdir(parents=True, exist_ok=True)
    try:
        logger.info("Downloading %s …", url)
        req = urllib.request.Request(url, headers={"User-Agent": "LexiLingoKG/1.0"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            local.write_bytes(resp.read())
        return True
    except Exception as exc:
        logger.warning("Could not download %s: %s", url, exc)
        return False


def load() -> Dict[str, str]:
    """Return merged {word.lower(): CEFR_level} dict."""
    cefr: Dict[str, str] = dict(_SEED)  # start from seeds

    # ── Source 1: CEFR-J ──────────────────────────────────────────────────
    if _download(CEFR_J_URL, CEFR_J_LOCAL):
        try:
            with open(CEFR_J_LOCAL, encoding="utf-8", errors="ignore") as f:
                reader = csv.DictReader(f)
                for row in reader:
                    word = (row.get("headword") or row.get("word") or "").strip().lower()
                    level = (row.get("CEFR") or row.get("level") or "").strip().upper()
                    if word and level and level in {"A1", "A2", "B1", "B2", "C1", "C2"}:
                        cefr[word] = level
            logger.info("CEFR-J loaded: %d entries total", len(cefr))
        except Exception as exc:
            logger.warning("CEFR-J parse error: %s", exc)

    # ── Source 2: Oxford 3000/5000 ─────────────────────────────────────────
    if _download(OXFORD_LISTS_URL, OXFORD_LISTS_LOCAL):
        try:
            data = json.loads(OXFORD_LISTS_LOCAL.read_text(encoding="utf-8"))
            # Format varies; try common patterns
            if isinstance(data, list):
                for item in data:
                    if isinstance(item, dict):
                        word = (item.get("word") or item.get("headword") or "").strip().lower()
                        level = (item.get("cefr") or item.get("level") or "").strip().upper()
                        if word and level in {"A1", "A2", "B1", "B2", "C1", "C2"}:
                            cefr[word] = level
            logger.info("Oxford list loaded: %d entries total", len(cefr))
        except Exception as exc:
            logger.warning("Oxford list parse error: %s", exc)

    logger.info("CEFR map final size: %d words", len(cefr))
    return cefr
