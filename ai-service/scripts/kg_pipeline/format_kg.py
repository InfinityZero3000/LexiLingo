"""
format_kg.py
Deduplicate nodes.csv + edges.csv and write clean final versions with headers.
Output:
  data/kg_raw/nodes_final.csv  — header: id,title,keywords,level
  data/kg_raw/edges_final.csv  — header: from,to,relation
"""
import csv
import logging
import time
from pathlib import Path

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

DATA_DIR = Path(__file__).resolve().parents[2] / "data" / "kg_raw"
NODES_IN  = DATA_DIR / "nodes.csv"
EDGES_IN  = DATA_DIR / "edges.csv"
NODES_OUT = DATA_DIR / "nodes_final.csv"
EDGES_OUT = DATA_DIR / "edges_final.csv"


def deduplicate_nodes() -> int:
    seen: dict[str, list[str]] = {}
    bad = 0
    logger.info("Reading %s …", NODES_IN)
    with open(NODES_IN, encoding="utf-8", newline="") as f:
        for row in csv.reader(f):
            if not row or len(row) < 2:
                bad += 1
                continue
            # Pad to 4 columns (id, title, keywords, level)
            while len(row) < 4:
                row.append("")
            node_id = row[0].strip()
            if not node_id:
                bad += 1
                continue
            if node_id not in seen:
                seen[node_id] = [node_id, row[1], row[2], row[3]]
    logger.info("nodes: %d unique (skipped %d bad rows)", len(seen), bad)
    logger.info("Writing %s …", NODES_OUT)
    with open(NODES_OUT, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["id", "title", "keywords", "level"])
        w.writerows(seen.values())
    return len(seen)


def deduplicate_edges() -> int:
    seen: set[tuple[str, str, str]] = set()
    bad = 0
    logger.info("Reading %s …", EDGES_IN)
    with open(EDGES_IN, encoding="utf-8", newline="") as f:
        for row in csv.reader(f):
            if not row or len(row) < 3:
                bad += 1
                continue
            src, dst, rel = row[0].strip(), row[1].strip(), row[2].strip()
            if not src or not dst or not rel:
                bad += 1
                continue
            seen.add((src, dst, rel))
    logger.info("edges: %d unique (skipped %d bad rows)", len(seen), bad)
    logger.info("Writing %s …", EDGES_OUT)
    with open(EDGES_OUT, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["from", "to", "relation"])
        w.writerows(seen)
    return len(seen)


if __name__ == "__main__":
    t0 = time.time()
    n = deduplicate_nodes()
    e = deduplicate_edges()
    logger.info(
        "Done in %.1fs — %d nodes, %d edges written to nodes_final.csv / edges_final.csv",
        time.time() - t0, n, e,
    )
