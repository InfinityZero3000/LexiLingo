"""Build the CEFR reference lexicon and grammar profile from the open CEFR-J / Octanove files.

Usage:  python scripts/build_cefr_lexicon.py [--fetch]

  --fetch   download the three CSVs from github.com/openlanguageprofiles/olp-en-cefrj first
Inputs   data/corpora/cefr_profiles/*.csv  (kept as downloaded, for provenance)
Outputs  data/lexicon/cefr_vocabulary.jsonl         one row per (headword, pos, level)
         data/lexicon/cefrj_grammar_profile.jsonl   one row per grammatical item
         data/lexicon/README.md                     terms of use and citation

Why a lexicon and not KG nodes: it is an authority to check labels against and to measure CEFR
profiles of text with. Putting 8k more isolated nodes into the graph would only add retrieval noise.
"""
import argparse
import csv
import json
import os
import urllib.request
from typing import Dict, List

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "data", "corpora", "cefr_profiles")
OUT = os.path.join(ROOT, "data", "lexicon")
BASE = "https://raw.githubusercontent.com/openlanguageprofiles/olp-en-cefrj/master/"
FILES = ("cefrj-vocabulary-profile-1.5.csv", "octanove-vocabulary-profile-c1c2-1.0.csv",
         "cefrj-grammar-profile-20180315.csv", "README.md")
SOURCES = {
    "cefrj-vocabulary-profile-1.5.csv": ("CEFR-J Wordlist 1.5 (Tono Laboratory, TUFS)", "free with citation"),
    "octanove-vocabulary-profile-c1c2-1.0.csv": ("Octanove Vocabulary Profile C1/C2 1.0", "CC BY-SA 4.0"),
}
LEVELS = ("A1", "A2", "B1", "B2", "C1", "C2")

README = """# CEFR lexicon

Reference data, not a graph. Rebuild with `python scripts/build_cefr_lexicon.py`.

| File | Rows | Source | Terms |
|---|---|---|---|
| `cefr_vocabulary.jsonl` | {vocab} | CEFR-J Wordlist 1.5 (A1-B2) + Octanove Vocabulary Profile C1/C2 1.0 | CEFR-J: free for research and commercial use if cited; Octanove: CC BY-SA 4.0 (share alike) |
| `cefrj_grammar_profile.jsonl` | {grammar} | CEFR-J Grammar Profile 20180315 (partly translated from Japanese) | as CEFR-J, cite |

Cite: The CEFR-J Wordlist Version 1.5, compiled by Yukio Tono, Tokyo University of Foreign Studies (http://www.cefr-j.org/download.html);
The CEFR-J Grammar Profile Version 20180315; Octanove Labs, Octanove Vocabulary Profile C1/C2 1.0.
Distributed through https://github.com/openlanguageprofiles/olp-en-cefrj . The copyright of the CEFR-J data belongs to the
Tono Laboratory at TUFS; neither CEFR-J nor Open Language Profiles is liable for inaccuracies.

`cefr_vocabulary.jsonl`: `word` (first spelling), `variants` (all spellings in the source row), `pos`, `cefr`, `source`.
A word with several parts of speech has one row each, and may carry different levels.
"""


def fetch() -> None:
    os.makedirs(RAW, exist_ok=True)
    for name in FILES:
        with urllib.request.urlopen(BASE + name, timeout=60) as r, open(os.path.join(RAW, name), "wb") as fh:
            fh.write(r.read())


def read_csv(name: str) -> List[Dict[str, str]]:
    with open(os.path.join(RAW, name), encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh))


def vocabulary() -> List[dict]:
    rows = []
    for name, (source, _) in SOURCES.items():
        for r in read_csv(name):
            forms = [f.strip() for f in r["headword"].split("/") if f.strip()]
            if not forms or r["CEFR"] not in LEVELS:
                continue
            rows.append({"word": forms[0].lower(), "variants": forms, "pos": r["pos"].strip().lower(),
                         "cefr": r["CEFR"], "source": source})
    return rows


def grammar() -> List[dict]:
    rows = []
    for r in read_csv("cefrj-grammar-profile-20180315.csv"):
        level = (r["CEFR-J Level"] or "").strip()
        rows.append({"id": r["ID"].strip(), "parent": r["ID"].strip().split("-")[0], "code": r["Shorthand Code"].strip(),
                     "item": r["Grammatical Item"].strip(), "sentence_type": r["Sentence Type"].strip() or None,
                     "cefrj_level": level or None, "cefr": level[:2] if level[:2] in LEVELS else None,
                     "egp_level": (r["EGP"] or "").strip() or None, "core_inventory": (r["Core Inventory"] or "").strip() or None,
                     "source": "CEFR-J Grammar Profile 20180315"})
    return rows


def write(path: str, rows: List[dict]) -> None:
    with open(path, "w", encoding="utf-8") as fh:
        for r in rows:
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--fetch", action="store_true")
    if ap.parse_args().fetch:
        fetch()
    os.makedirs(OUT, exist_ok=True)
    v, g = vocabulary(), grammar()
    write(os.path.join(OUT, "cefr_vocabulary.jsonl"), v)
    write(os.path.join(OUT, "cefrj_grammar_profile.jsonl"), g)
    with open(os.path.join(OUT, "README.md"), "w", encoding="utf-8") as fh:
        fh.write(README.format(vocab=len(v), grammar=len(g)))
    print(f"vocabulary {len(v)} rows, grammar {len(g)} rows")
