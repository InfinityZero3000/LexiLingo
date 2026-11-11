"""Look the eval vocabulary up in English Wiktionary (CC BY-SA 4.0) with Firecrawl.

Usage:
  python scripts/crawl_wiktionary_reference.py crawl --per-level 80   # spends ~1 credit per word
  python scripts/crawl_wiktionary_reference.py parse                  # re-extract from cache, free

Why: the KG is the only source of the QA gold, so a wrong KG fact becomes a wrong
"correct" answer. Wiktionary is an independent reference for Vietnamese glosses, and
its headword line carries inflections (plural, past tense) that the KG lacks — those
make the "answerable from text, not from the KG" stratum.

Raw pages (~100 KB each) stay in the cache dir; only extracted fields are committed
to data/corpora/wiktionary_reference/entries.jsonl.
"""
import argparse
import concurrent.futures as cf
import datetime
import importlib.util
import json
import os
import re
import subprocess
import sys
import threading
import time
import unicodedata
import urllib.parse
from typing import Dict, List, Optional

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "tmp", "wiktionary_raw")
OUT_DIR = os.path.join(ROOT, "data", "corpora", "wiktionary_reference")
OUT = os.path.join(OUT_DIR, "entries.jsonl")
LICENSE = "CC BY-SA 4.0 (en.wiktionary.org, see page history for authors)"
POS_HEADINGS = {"Noun", "Verb", "Adjective", "Adverb", "Preposition", "Pronoun",
                "Conjunction", "Interjection", "Determiner", "Numeral"}
VI_LETTER = re.compile(r"[a-zà-ỹđ]", re.I)

_spec = importlib.util.spec_from_file_location(
    "build_kg_grounded_eval", os.path.join(ROOT, "scripts", "build_kg_grounded_eval.py"))
builder = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(builder)


_gate = threading.Lock()
_next_slot = 0.0
MIN_INTERVAL = 7.5  # the plan allows ~10 requests/min and counts rejected retries too


def _wait_turn(extra: float = 0.0) -> None:
    global _next_slot
    with _gate:
        now = time.monotonic()
        _next_slot = max(_next_slot, now) + MIN_INTERVAL + extra
        delay = _next_slot - MIN_INTERVAL - extra - now
    if delay > 0:
        time.sleep(delay)


def url_for(word: str) -> str:
    return "https://en.wiktionary.org/wiki/" + urllib.parse.quote(word)


def fetch(word: str) -> str:
    """Scrape one page into the cache (skips what is already there); returns the path."""
    path = os.path.join(CACHE, f"{word}.md")
    if os.path.exists(path) and os.path.getsize(path) > 500:
        return path
    for _ in range(4):
        _wait_turn()
        r = subprocess.run(
            ["firecrawl", "scrape", url_for(word), "--format", "markdown", "--only-main-content", "-o", path],
            capture_output=True, text=True, timeout=180)
        if r.returncode == 0 and os.path.exists(path) and os.path.getsize(path) > 500:
            return path
        err = (r.stderr or r.stdout or "").strip().replace("\n", " ")[:200]
        print(f"  ! {word}: rc={r.returncode} {err[:120]}", flush=True)
        m = re.search(r"retry after (\d+)s", err)
        if m:
            _wait_turn(extra=int(m.group(1)) + 3)
    return ""


def clean(text: str) -> str:
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)        # [x](url "t") -> x
    text = re.sub(r"\\\[.*?\\\]", "", text)                       # \[ edit \]
    text = re.sub(r"[*_]", "", text)
    return re.sub(r"\s+", " ", text).strip()


def english_section(md: str) -> str:
    m = re.search(r"^## English\s*$", md, re.M)
    if not m:
        return ""
    rest = md[m.end():]
    n = re.search(r"^## (?!English)", rest, re.M)
    return rest[: n.start()] if n else rest


def split_alternatives(value: str) -> List[str]:
    parts = [p.strip() for p in re.split(r"\s+or\s+|,", value) if p.strip()]
    return [p for p in parts if re.fullmatch(r"[a-z]+(?:[' -][a-z]+)*", p)]


def forms_from_headword(line: str, pos: str) -> Dict[str, List[str]]:
    """Inflections stated on the headword line, only when stated unambiguously."""
    paren = re.search(r"\((.*)\)", clean(line))
    if not paren:
        return {}
    body = paren.group(1).strip()
    if re.search(r"uncountable|no plural|not comparable|usually|rare|dated|obsolete|archaic|proscribed", body):
        # stated with a caveat or tied to one sense: not a clean gold answer
        if not re.search(r"^(?:countable|plural)", body) or "usually" in body:
            return {}
    out: Dict[str, List[str]] = {}
    if pos == "Noun":
        m = re.search(r"\bplural ([^;]+?)(?:$|;)", body)
        if m and not re.search(r"\bplural (?:uncountable|only|\?)", body):
            alts = split_alternatives(m.group(1))
            if alts:
                out["plural"] = alts
    elif pos == "Verb":
        both = re.search(r"simple past and past participle ([^;]+?)(?:$|,\s*(?:third|present)|;)", body)
        if both:
            alts = split_alternatives(both.group(1))
            if alts:
                out["simple_past"] = out["past_participle"] = alts
        else:
            a = re.search(r"simple past ([^;]+?)(?:,\s*past participle|;|$)", body)
            b = re.search(r"past participle ([^;]+?)(?:$|;)", body)
            if a and split_alternatives(a.group(1)):
                out["simple_past"] = split_alternatives(a.group(1))
            if b and split_alternatives(b.group(1)) and "(" not in b.group(1):
                out["past_participle"] = split_alternatives(b.group(1))
    elif pos == "Adjective":
        c = re.search(r"comparative ([^,;]+?)(?:,|;|$)", body)
        s = re.search(r"superlative ([^,;]+?)(?:,|;|$)", body)
        if c and s and not c.group(1).startswith("more") and re.fullmatch(r"[a-z]+", c.group(1).strip()):
            out["comparative"] = [c.group(1).strip()]
            out["superlative"] = [s.group(1).strip().split(" or ")[0]]
    return out


def parse_page(word: str, md: str) -> Optional[dict]:
    en = english_section(md)
    if not en:
        return None
    entry = {"word": word, "url": url_for(word), "license": LICENSE, "pos": {}, "vi_translations": []}
    for block in re.split(r"^#{3,5} ", en, flags=re.M)[1:]:
        pos = block.split("\n", 1)[0].strip()
        if pos not in POS_HEADINGS or pos in entry["pos"]:
            continue  # first etymology is the commonest sense; later ones are rare homographs
        lines = block.splitlines()
        inflected = re.compile(r"plural|simple past|past participle|comparative")
        head = next((ln for ln in lines[:14] if ln.lstrip().startswith("**") and inflected.search(ln)),
                    next((ln for ln in lines if ln.lstrip().startswith("**")), ""))
        senses = [clean(ln.split(". ", 1)[1]) for ln in block.splitlines() if re.match(r"^\d+\. ", ln)]
        entry["pos"][pos] = {
            "headword_line": clean(head)[:300],
            "forms": forms_from_headword(head, pos) if head else {},
            "definitions": [s for s in senses if s][:3],
        }
    seen: List[str] = []
    for line in re.findall(r"- Vietnamese: ([^\n]*?)(?:<br>|\|)", en):
        for w in re.findall(r"\[([^\]]+)\]\(https://en\.wiktionary\.org/wiki/[^)]*#Vietnamese", line):
            if VI_LETTER.search(w) and w not in seen:
                seen.append(unicodedata.normalize("NFC", w))
    entry["vi_translations"] = seen
    return entry if entry["pos"] else None


def cmd_crawl(per_level: int, workers: int) -> None:
    words = [c["title"] for c in builder.reference_words(per_level)]
    os.makedirs(CACHE, exist_ok=True)
    todo = [w for w in words if not (os.path.exists(os.path.join(CACHE, f"{w}.md")))]
    print(f"{len(words)} words selected, {len(todo)} not cached; ~{len(todo)} credits", flush=True)
    done = failed = 0
    with cf.ThreadPoolExecutor(max_workers=workers) as ex:
        for w, p in zip(todo, ex.map(fetch, todo)):
            done += bool(p)
            failed += not p
            if (done + failed) % 25 == 0:
                print(f"  {done + failed}/{len(todo)} (failed {failed})", flush=True)
    print(f"crawl finished: {done} ok, {failed} failed", flush=True)
    cmd_parse()


def cmd_parse() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    levels = {c["title"]: c["level"] for c in builder.reference_words(10_000)}
    n = 0
    with open(OUT, "w", encoding="utf-8") as fh:
        for fn in sorted(os.listdir(CACHE)):
            word = fn[:-3]
            with open(os.path.join(CACHE, fn), encoding="utf-8") as src:
                entry = parse_page(word, src.read())
            if entry:
                entry["retrieved"] = datetime.date.fromtimestamp(os.path.getmtime(os.path.join(CACHE, fn))).isoformat()
                entry["kg_level"] = levels.get(word)
                fh.write(json.dumps(entry, ensure_ascii=False) + "\n")
                n += 1
    print(f"wrote {n} entries to {OUT}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("crawl")
    c.add_argument("--per-level", type=int, default=80)
    c.add_argument("--workers", type=int, default=2)
    sub.add_parser("parse")
    a = ap.parse_args()
    cmd_crawl(a.per_level, a.workers) if a.cmd == "crawl" else cmd_parse()
