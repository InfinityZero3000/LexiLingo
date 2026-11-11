"""Fetch structured English Wiktionary entries (kaikki.org, a Wiktextract extraction, CC BY-SA 4.0) for the words we need.

Usage:  python scripts/crawl_kaikki_reference.py            # resumes; skips words already stored
Words:  every CEFR-J / Octanove headword plus every word in the KG vocabulary file
Output: data/corpora/kaikki_reference/entries.jsonl   {word, found, entries:[{pos, glosses, ipa, forms, vi}]}

One small static file per word, no API key. Only extracted fields are kept (a raw page is 20-300 KB).
"""
import concurrent.futures as cf
import json
import os
import re
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Dict, List, Set

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
OUT = os.path.join(DATA, "corpora", "kaikki_reference", "entries.jsonl")
BASE = "https://kaikki.org/dictionary/English/meaning/"
WORKERS = 10
MIN_INTERVAL = 0.1  # seconds between request starts, over all workers
_gate, _next = threading.Lock(), [0.0]


def wanted_words() -> List[str]:
    words: Set[str] = set()
    with open(os.path.join(DATA, "lexicon", "cefr_vocabulary.jsonl"), encoding="utf-8") as fh:
        for line in fh:
            words.add(json.loads(line)["word"])
    with open(os.path.join(DATA, "kg", "07_vocabulary_anki.json"), encoding="utf-8") as fh:
        words |= {c["title"].lower() for c in json.load(fh)["concepts"]}
    return sorted(w for w in words if re.fullmatch(r"[a-z]+(?:[' -][a-z]+)*", w))


def url_for(word: str) -> str:
    key = re.sub(r"[^a-z]", "", word)
    first, two = key[:1], key[:2] if len(key) > 1 else key[:1] + "_"
    return f"{BASE}{first}/{two}/{urllib.parse.quote(word)}.jsonl"


def _pace() -> None:
    with _gate:
        now = time.monotonic()
        _next[0] = max(_next[0], now) + MIN_INTERVAL
        delay = _next[0] - MIN_INTERVAL - now
    if delay > 0:
        time.sleep(delay)


def fetch(word: str) -> dict:
    for attempt in range(4):
        _pace()
        try:
            with urllib.request.urlopen(url_for(word), timeout=40) as r:
                rows = [json.loads(line) for line in r.read().decode("utf-8").splitlines() if line.strip()]
            return {"word": word, "found": True, "entries": [extract(r) for r in rows if r.get("lang_code") == "en"]}
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                return {"word": word, "found": False, "entries": []}
            time.sleep(2 ** attempt)
        except Exception:
            time.sleep(2 ** attempt)
    return {"word": word, "found": None, "entries": []}  # unknown: retried on the next run


def extract(row: dict) -> dict:
    glosses = []
    for sense in row.get("senses", []):
        tags = set(sense.get("tags", [])) | set(sense.get("raw_tags", []))
        text = (sense.get("glosses") or [""])[-1].strip()
        if text and not tags & {"form-of", "alt-of", "obsolete", "archaic", "rare"} and text not in glosses:
            glosses.append(text)
    ipa = next((s["ipa"] for s in row.get("sounds", []) if s.get("ipa")), None)
    forms = [{"form": f["form"], "tags": f.get("tags", [])} for f in row.get("forms", []) if f.get("form") and f.get("tags")]
    vi = []
    for t in row.get("translations", []):
        if t.get("lang_code") == "vi" and t.get("word") and t["word"] not in [v["word"] for v in vi]:
            vi.append({"word": t["word"], "sense": (t.get("sense") or "")[:80]})
    return {"pos": row.get("pos"), "glosses": glosses[:3], "ipa": ipa, "forms": forms[:12], "vi": vi[:6]}


def main() -> None:
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    done: Dict[str, bool] = {}
    if os.path.exists(OUT):
        with open(OUT, encoding="utf-8") as fh:
            for line in fh:
                r = json.loads(line)
                if r["found"] is not None:
                    done[r["word"]] = True
    todo = [w for w in wanted_words() if w not in done]
    print(f"{len(done)} stored, {len(todo)} to fetch", flush=True)
    n = bad = 0
    with open(OUT, "a", encoding="utf-8") as out, cf.ThreadPoolExecutor(max_workers=WORKERS) as ex:
        for rec in ex.map(fetch, todo):
            out.write(json.dumps(rec, ensure_ascii=False) + "\n")
            out.flush()
            n += 1
            bad += rec["found"] is None
            if n % 500 == 0:
                print(f"  {n}/{len(todo)} (unreachable {bad})", flush=True)
    print(f"finished: {n} fetched, {bad} unreachable (rerun to retry)", flush=True)


if __name__ == "__main__":
    main()
