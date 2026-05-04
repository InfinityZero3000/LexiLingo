"""
Extract KG nodes and edges from NLTK WordNet — no HTTP required.

Produces:
  ~155 000 word nodes    (word:{pos}.{lemma})
  ~117 000 synset nodes  (synset:{name})
  ~450 000 semantic edges (hypernym, antonym, holonym, member_of …)

Estimated runtime: 3–6 minutes on a single CPU.
"""

import csv
import logging
from pathlib import Path
from typing import Iterator, Tuple

import nltk
from tqdm import tqdm

from config import KG_RAW_DIR, PROGRESS_DIR, WN_POS

logger = logging.getLogger(__name__)

# CEFR level heuristic: synset depth in the hypernym hierarchy
# (WordNet root = depth 0; common concrete nouns ≈ depth 5-8)
_DEPTH_LEVEL = [(3, "A1"), (5, "A2"), (8, "B1"), (11, "B2")]


def _depth_to_cefr(depth: int) -> str:
    for threshold, level in _DEPTH_LEVEL:
        if depth <= threshold:
            return level
    return "C1"


def _ensure_nltk() -> None:
    for corpus in ("wordnet", "omw-1.4"):
        try:
            nltk.data.find(f"corpora/{corpus}")
        except LookupError:
            logger.info("Downloading NLTK corpus: %s", corpus)
            nltk.download(corpus, quiet=True)


def extract(nodes_csv: Path, edges_csv: Path) -> Tuple[int, int]:
    """
    Stream WordNet into two CSV files.

    Returns (node_count, edge_count).
    """
    _ensure_nltk()
    from nltk.corpus import wordnet as wn  # noqa: import after download

    PROGRESS_DIR.mkdir(parents=True, exist_ok=True)
    checkpoint = PROGRESS_DIR / "wordnet.done"
    if checkpoint.exists():
        logger.info("WordNet stage already done — skipping (delete %s to re-run)", checkpoint)
        # Count existing lines
        n = sum(1 for _ in open(nodes_csv)) - 1
        e = sum(1 for _ in open(edges_csv)) - 1
        return n, e

    node_count = 0
    edge_count = 0
    seen_word_ids: set[str] = set()

    # Open in append mode so multiple stages can share the same CSV files
    with (
        open(nodes_csv, "a", newline="", encoding="utf-8") as nf,
        open(edges_csv, "a", newline="", encoding="utf-8") as ef,
    ):
        nw = csv.writer(nf)
        ew = csv.writer(ef)

        all_synsets = list(wn.all_synsets())
        for ss in tqdm(all_synsets, desc="WordNet synsets"):
            ss_id = f"synset:{ss.name()}"
            pos_code = ss.pos()
            pos_label = WN_POS.get(pos_code, "word")
            depth = ss.min_depth()
            level = _depth_to_cefr(depth)
            definition = (ss.definition() or "")[:120].replace('"', "'")
            lemma_names = [l.replace("_", " ") for l in ss.lemma_names()]
            keywords = " ".join(lemma_names)

            # Synset node
            nw.writerow([ss_id, definition or ss.name(), keywords, level])
            node_count += 1

            # Word (lemma) nodes + member_of edges
            for lemma in ss.lemmas():
                word = lemma.name().replace("_", " ")
                word_id = f"word:{pos_code}.{lemma.name()}"
                if word_id not in seen_word_ids:
                    nw.writerow([word_id, word, word, level])
                    seen_word_ids.add(word_id)
                    node_count += 1

                ew.writerow([word_id, ss_id, "member_of"])
                edge_count += 1

                # Antonyms
                for ant in lemma.antonyms():
                    ant_id = f"word:{pos_code}.{ant.name()}"
                    ew.writerow([word_id, ant_id, "antonym_of"])
                    edge_count += 1

            # Semantic relations from synset
            for hyper in ss.hypernyms():
                ew.writerow([ss_id, f"synset:{hyper.name()}", "hypernym_of"])
                edge_count += 1
            for hypo in ss.hyponyms():
                ew.writerow([ss_id, f"synset:{hypo.name()}", "hyponym_of"])
                edge_count += 1
            for holo in ss.member_holonyms() + ss.part_holonyms():
                ew.writerow([ss_id, f"synset:{holo.name()}", "part_of"])
                edge_count += 1
            for also in ss.also_sees():
                ew.writerow([ss_id, f"synset:{also.name()}", "related_to"])
                edge_count += 1

    checkpoint.touch()
    logger.info("WordNet done — %d nodes, %d edges", node_count, edge_count)
    return node_count, edge_count
