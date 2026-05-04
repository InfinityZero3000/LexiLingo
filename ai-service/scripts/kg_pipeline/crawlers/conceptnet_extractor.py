"""
Download ConceptNet 5.7 English assertions and append to the KG CSVs.

Produces ~700k unique English concept nodes and ~3M edges.
Download size: ~1.2 GB compressed.
"""

import csv
import gzip
import logging
import re
import sys
import time
import urllib.request
from pathlib import Path

logger = logging.getLogger(__name__)

CONCEPTNET_URL = (
    "https://s3.amazonaws.com/conceptnet/downloads/2019/edges/"
    "conceptnet-assertions-5.7.0.csv.gz"
)

DATA_DIR = Path(__file__).resolve().parents[3] / "data" / "kg_raw"
DUMP_PATH = DATA_DIR / "conceptnet-5.7.csv.gz"
NODES_CSV = DATA_DIR / "nodes.csv"
EDGES_CSV = DATA_DIR / "edges.csv"
DONE_FLAG = DATA_DIR / "progress" / "conceptnet.done"


def _download_dump() -> None:
    if DUMP_PATH.exists():
        logger.info("ConceptNet dump already cached at %s", DUMP_PATH)
        return
    logger.info("Downloading ConceptNet 5.7 (~1.2 GB) …")
    DATA_DIR.mkdir(parents=True, exist_ok=True)

    def _progress(block, block_size, total):
        done = block * block_size
        pct = done * 100 // total if total > 0 else 0
        mb = done / 1_048_576
        total_mb = total / 1_048_576
        print(f"\r  {pct:3d}%  {mb:.0f} MB / {total_mb:.0f} MB", end="", flush=True)

    urllib.request.urlretrieve(CONCEPTNET_URL, DUMP_PATH, _progress)
    print()
    logger.info("Download complete: %s", DUMP_PATH)


def _uri_to_id(uri: str) -> str:
    segs = uri.split("/")  # ['', 'c', 'en', 'word', 'pos', ...]
    word = segs[3] if len(segs) > 3 else ""
    pos = segs[4] if len(segs) > 4 else ""
    word = re.sub(r"[^a-z0-9_]", "_", word.lower())
    return f"cn:{word}_{pos}" if pos else f"cn:{word}"


def _uri_to_title(uri: str) -> str:
    segs = uri.split("/")
    raw = segs[3] if len(segs) > 3 else ""
    return raw.replace('"', "").replace(",", " ").replace("\n", " ").strip()


def extract(nodes_csv: Path = NODES_CSV, edges_csv: Path = EDGES_CSV) -> tuple[int, int]:
    """Append ConceptNet English nodes+edges to the CSV files."""
    if DONE_FLAG.exists():
        logger.info("ConceptNet already extracted (checkpoint exists), skipping.")
        return 0, 0

    _download_dump()

    seen_nodes: set[str] = set()
    t0 = time.time()
    nc = ec = 0
    skipped = 0

    with (
        gzip.open(DUMP_PATH, "rt", encoding="utf-8") as fin,
        open(nodes_csv, "a", newline="", encoding="utf-8") as fn,
        open(edges_csv, "a", newline="", encoding="utf-8") as fe,
    ):
        nw = csv.writer(fn)
        ew = csv.writer(fe)

        for i, line in enumerate(fin):
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 5:
                continue
            _, rel_uri, src_uri, dst_uri, _ = parts[:5]

            # English-only assertions
            if not src_uri.startswith("/c/en/") or not dst_uri.startswith("/c/en/"):
                skipped += 1
                continue

            src_id = _uri_to_id(src_uri)
            dst_id = _uri_to_id(dst_uri)

            if src_id not in seen_nodes:
                seen_nodes.add(src_id)
                nw.writerow([src_id, _uri_to_title(src_uri), _uri_to_title(src_uri), "B1"])
                nc += 1
            if dst_id not in seen_nodes:
                seen_nodes.add(dst_id)
                nw.writerow([dst_id, _uri_to_title(dst_uri), _uri_to_title(dst_uri), "B1"])
                nc += 1

            rel = rel_uri.split("/")[-1]  # e.g. IsA, Synonym, RelatedTo
            ew.writerow([src_id, dst_id, rel])
            ec += 1

            if (i + 1) % 500_000 == 0:
                logger.info(
                    "conceptnet: %d lines … %d nodes, %d edges (%.0fs)",
                    i + 1, nc, ec, time.time() - t0,
                )

    DONE_FLAG.touch()
    logger.info(
        "ConceptNet done — %d new nodes, %d edges (%.0fs)",
        nc, ec, time.time() - t0,
    )
    return nc, ec


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%H:%M:%S",
    )
    nc, ec = extract()
    print(f"ConceptNet: {nc:,} nodes, {ec:,} edges")
