"""Fetch the standalone corpora under data/corpora/ from the public Hugging Face datasets-server.

Usage:  python scripts/fetch_hf_corpora.py [--opus-rows 20000]

  gec_pairs/gec_pairs.jsonl       jhu-clsp/jfleg, every row (validation + test), all 4 references   CC BY-NC-SA 4.0
  parallel_en_vi/pairs.jsonl      Helsinki-NLP/opus-100 en-vi, first N train rows, noise-filtered  licence unknown

Both are non-commercial / unaudited: keep them out of anything shipped to users.
Rows are fetched in order, so a rerun gives the same file.
"""
import argparse
import json
import os
import re
import time
import urllib.parse
import urllib.request
from typing import Iterator, List

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "data", "corpora")
API = "https://datasets-server.huggingface.co/rows"
VI_MARK = re.compile(r"[àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ]", re.I)


def rows(dataset: str, config: str, split: str, total: int) -> Iterator[dict]:
    for offset in range(0, total, 100):
        q = urllib.parse.urlencode({"dataset": dataset, "config": config, "split": split,
                                    "offset": offset, "length": min(100, total - offset)})
        for attempt in range(6):
            try:
                with urllib.request.urlopen(f"{API}?{q}", timeout=60) as r:
                    batch = json.load(r)["rows"]
                break
            except Exception:
                time.sleep(2 ** attempt)
        else:
            raise RuntimeError(f"gave up at {dataset} {split} offset {offset}")
        for item in batch:
            yield item["row"]
        time.sleep(0.15)


def write(path: str, items: List[dict]) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        for it in items:
            fh.write(json.dumps(it, ensure_ascii=False) + "\n")


def gec() -> int:
    items = []
    for split, n in (("validation", 755), ("test", 748)):
        for r in rows("jhu-clsp/jfleg", "default", split, n):
            refs = [c.strip() for c in r["corrections"] if c.strip()]
            orig = r["sentence"].strip()
            if orig and refs:
                items.append({"source": f"jhu-clsp/jfleg:{split}", "original": orig, "corrected": refs[0],
                              "references": refs, "has_error": orig != refs[0]})
    write(os.path.join(OUT, "gec_pairs", "gec_pairs.jsonl"), items)
    return len(items)


def opus(n: int) -> int:
    seen, items = set(), []
    for r in rows("Helsinki-NLP/opus-100", "en-vi", "train", n):
        en, vi = r["translation"]["en"].strip(), r["translation"]["vi"].strip()
        ratio = len(vi.split()) / max(1, len(en.split()))
        if (not en or not vi or en.lower() == vi.lower() or not re.search(r"[A-Za-z]", en)
                or not 0.4 <= ratio <= 3.0 or (en, vi) in seen):
            continue
        seen.add((en, vi))
        items.append({"en": en, "vi": vi, "vi_has_diacritics": bool(VI_MARK.search(vi)),
                      "source": "Helsinki-NLP/opus-100:en-vi:train"})
    write(os.path.join(OUT, "parallel_en_vi", "pairs.jsonl"), items)
    return len(items)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--opus-rows", type=int, default=20000)
    a = ap.parse_args()
    print("gec_pairs:", gec())
    print("parallel_en_vi:", opus(a.opus_rows))
