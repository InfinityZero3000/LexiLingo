"""Add the CEFR-J / Octanove words the KG lacks, as KG vocabulary concepts (data/kg/13_cefrj_vocabulary.json).

Usage:  python scripts/build_cefrj_kg_vocab.py        (needs data/lexicon/ and data/corpora/kaikki_reference/)

A word becomes a node only if the English Wiktionary extraction gives it a definition, so every node can be explained. The node
follows the file 07 format: id concept:vocab.word.<slug>, keywords "<definition>,<Vietnamese>, <Vietnamese>", level from CEFR-J
(the lowest level if the word is listed at several). No edges: the nodes are reference vocabulary, and 27% of the graph is
already isolated nodes.
"""
import json
import os
import re
from typing import Dict, List

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
OUT = os.path.join(DATA, "kg", "13_cefrj_vocabulary.json")
RANK = {"A1": 1, "A2": 2, "B1": 3, "B2": 4, "C1": 5, "C2": 6}
KG_FILES = ["knowledge_extended.json"] + [f"kg/{n}" for n in (
    "01_grammar_gaps.json", "02_functional_language.json", "03_errors_vietnamese.json", "04_writing_phonology.json",
    "05_vocabulary_advanced.json", "06_tracecag_topic_expansion.json", "seed_graph.json", "07_vocabulary_anki.json",
    "08_cefr_sentences.json", "09_grammar_usage.json", "10_collocations.json", "11_idioms.json", "12_lexical_relations.json")]
POS_ORDER = {"noun": 0, "verb": 1, "adj": 2, "adv": 3}


def slug(word: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", word.lower()).strip("_")


def levels() -> Dict[str, str]:
    best: Dict[str, str] = {}
    with open(os.path.join(DATA, "lexicon", "cefr_vocabulary.jsonl"), encoding="utf-8") as fh:
        for line in fh:
            r = json.loads(line)
            if r["word"] not in best or RANK[r["cefr"]] < RANK[best[r["word"]]]:
                best[r["word"]] = r["cefr"]
    return best


def existing() -> tuple:
    ids, titles = set(), set()
    for rel in KG_FILES:
        with open(os.path.join(DATA, rel), encoding="utf-8") as fh:
            for c in json.load(fh).get("concepts", []):
                ids.add(c["id"])
                titles.add(c["title"].strip().lower())
    return ids, titles


def definition(entries: List[dict]) -> str:
    ordered = sorted((e for e in entries if e.get("glosses")), key=lambda e: POS_ORDER.get(e.get("pos") or "", 9))
    return re.sub(r"\s+", " ", ordered[0]["glosses"][0]).strip()[:160] if ordered else ""


def vietnamese(entries: List[dict]) -> List[str]:
    out: List[str] = []
    for e in sorted(entries, key=lambda e: POS_ORDER.get(e.get("pos") or "", 9)):
        for v in e.get("vi", []):
            if v["word"] not in out and "," not in v["word"]:
                out.append(v["word"])
    return out[:3]


def main() -> None:
    lvl = levels()
    ids, titles = existing()
    concepts, no_gloss, skipped = [], 0, 0
    with open(os.path.join(DATA, "corpora", "kaikki_reference", "entries.jsonl"), encoding="utf-8") as fh:
        ref = {r["word"]: r for r in map(json.loads, fh) if r["found"]}
    for word in sorted(lvl):
        cid = f"concept:vocab.word.{slug(word)}"
        if word in titles or cid in ids or not slug(word):   # `ids` grows below, so a slug collision keeps the first word
            skipped += 1
            continue
        entry = ref.get(word)
        gloss = definition(entry["entries"]) if entry else ""
        if not gloss:
            no_gloss += 1
            continue
        vi = vietnamese(entry["entries"])
        concepts.append({"id": cid, "title": word, "keywords": gloss + ("," + ", ".join(vi) if vi else ""), "level": lvl[word]})
        ids.add(cid)
    doc = {"version": "1.0.0",
           "description": "CEFR-J Wordlist 1.5 and Octanove C1/C2 1.0 words absent from the other vocabulary files. Definitions and Vietnamese "
                          "translations from English Wiktionary via kaikki.org (CC BY-SA 4.0). Levels: CEFR-J (free with citation) / Octanove (CC BY-SA 4.0).",
           "concepts": concepts, "edges": []}
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, indent=2, ensure_ascii=False)
    by = {}
    for c in concepts:
        by[c["level"]] = by.get(c["level"], 0) + 1
    print(f"{len(concepts)} concepts written ({dict(sorted(by.items()))}); {skipped} already in the KG, {no_gloss} dropped for lack of a definition")
    print("with a Vietnamese gloss:", sum("," in c["keywords"].split(" ", 1)[-1] and bool(re.search(r"[À-ỹ]", c["keywords"])) for c in concepts))


if __name__ == "__main__":
    main()
