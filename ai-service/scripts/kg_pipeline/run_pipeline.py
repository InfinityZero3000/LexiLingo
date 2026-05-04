#!/usr/bin/env python3
"""
KG crawl pipeline orchestrator — runs all stages in order.

Usage:
    cd /opt/lexilingo/ai-service/scripts/kg_pipeline
    python run_pipeline.py [--stages wordnet,wiktionary,cefr,crawl4ai,conceptnet,import] [--dry-run]

Stages (run in this order):
    1. cefr        — download CEFR word lists (fast, ~30s)
    2. wordnet     — extract from NLTK WordNet (~5 min, ~270k nodes+edges)
    3. wiktionary  — stream kaikki.org dump (~30 min, ~1.4M nodes)
    4. crawl4ai    — crawl grammar/idiom/phrasal-verb sites (~5 min)
    5. conceptnet  — download+extract ConceptNet 5.7 (~20 min, ~700k nodes)
    6. import      — bulk-load all CSVs into KuzuDB (~15 min)

The CSV files are APPENDED to across stages — running a subset of stages
extends the same files. Delete data/kg_raw/ to start clean.

Checkpoints in data/kg_raw/progress/*.done prevent re-running completed stages.
Delete the relevant .done file to re-run a single stage.

Expected final KG size:
    WordNet synsets + words:   ~270 000 nodes
    Wiktionary entries:        ~1 400 000 nodes
    ConceptNet English:        ~700 000 nodes
    Crawl4AI:                  ~1 500 nodes
    Existing hand-crafted KG:  ~242 nodes
    ─────────────────────────────────────
    Total (approx):            ~2 370 000 nodes  ← well past 1 000 000
"""

import argparse
import csv
import json
import logging
import sys
import time
from pathlib import Path

# ── Path bootstrap ─────────────────────────────────────────────────────────
_PIPELINE_DIR = Path(__file__).parent
sys.path.insert(0, str(_PIPELINE_DIR))

from config import (
    EDGES_CSV,
    KG_DOMAIN_DIR,
    KG_RAW_DIR,
    NODES_CSV,
    PROGRESS_DIR,
    TARGET_NODES,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("pipeline")

ALL_STAGES = ["cefr", "wordnet", "wiktionary", "crawl4ai", "conceptnet", "import"]


def _init_csv_files() -> None:
    """Create CSV files with headers if they don't exist yet."""
    KG_RAW_DIR.mkdir(parents=True, exist_ok=True)
    PROGRESS_DIR.mkdir(parents=True, exist_ok=True)

    if not NODES_CSV.exists():
        with open(NODES_CSV, "w", newline="", encoding="utf-8") as f:
            pass  # no header row — KuzuDB COPY FROM with HEADER=false

    if not EDGES_CSV.exists():
        with open(EDGES_CSV, "w", newline="", encoding="utf-8") as f:
            pass


def _load_existing_domain_json() -> tuple[int, int]:
    """
    Copy existing hand-crafted domain JSON files (data/kg/*.json) into the
    pipeline CSVs so the importer picks them up in the bulk load.

    Returns (node_count, edge_count) added.
    """
    checkpoint = PROGRESS_DIR / "domain_json.done"
    if checkpoint.exists():
        logger.info("Domain JSON stage already done — skipping")
        return 0, 0

    node_count = 0
    edge_count = 0

    with (
        open(NODES_CSV, "a", newline="", encoding="utf-8") as nf,
        open(EDGES_CSV, "a", newline="", encoding="utf-8") as ef,
    ):
        nw = csv.writer(nf)
        ew = csv.writer(ef)

        for json_path in sorted(KG_DOMAIN_DIR.glob("*.json")):
            try:
                import json as _json
                data = _json.loads(json_path.read_text(encoding="utf-8"))
            except Exception as exc:
                logger.warning("Skipping %s: %s", json_path.name, exc)
                continue

            for c in data.get("concepts", []):
                nw.writerow([c["id"], c.get("title", ""), c.get("keywords", ""), c.get("level", "B1")])
                node_count += 1

            for e in data.get("edges", []):
                ew.writerow([e["from"], e["to"], e.get("relation", "related_to")])
                edge_count += 1

    checkpoint.touch()
    logger.info("Domain JSON: loaded %d nodes, %d edges", node_count, edge_count)
    return node_count, edge_count


def _count_csv_rows() -> tuple[int, int]:
    node_count = sum(1 for _ in open(NODES_CSV, encoding="utf-8")) if NODES_CSV.exists() else 0
    edge_count = sum(1 for _ in open(EDGES_CSV, encoding="utf-8")) if EDGES_CSV.exists() else 0
    return node_count, edge_count


def run(stages: list[str], dry_run: bool = False) -> None:
    t_start = time.time()
    _init_csv_files()

    report = {"stages": {}, "total_duration_s": 0}

    # ── Always: load hand-crafted domain JSON ──────────────────────────────
    if not dry_run:
        n, e = _load_existing_domain_json()
        report["stages"]["domain_json"] = {"nodes": n, "edges": e}

    # ── Stage 1: CEFR lists ────────────────────────────────────────────────
    if "cefr" in stages:
        logger.info("=" * 60)
        logger.info("STAGE: cefr — downloading CEFR word lists")
        if dry_run:
            logger.info("[dry-run] skipped")
        else:
            from crawlers.cefr_lists import load as cefr_load
            cefr_map = cefr_load()
            report["stages"]["cefr"] = {"words": len(cefr_map)}
            logger.info("CEFR map: %d words", len(cefr_map))
    else:
        cefr_map = {}

    # ── Stage 2: WordNet ───────────────────────────────────────────────────
    if "wordnet" in stages:
        logger.info("=" * 60)
        logger.info("STAGE: wordnet — extracting from NLTK WordNet")
        if dry_run:
            logger.info("[dry-run] skipped")
        else:
            from crawlers.wordnet_extractor import extract as wn_extract
            n, e = wn_extract(NODES_CSV, EDGES_CSV)
            report["stages"]["wordnet"] = {"nodes": n, "edges": e}
            rows_n, rows_e = _count_csv_rows()
            logger.info("CSV totals after WordNet: %d node rows, %d edge rows", rows_n, rows_e)

    # ── Stage 3: Wiktionary ────────────────────────────────────────────────
    if "wiktionary" in stages:
        logger.info("=" * 60)
        logger.info("STAGE: wiktionary — streaming kaikki.org dump")
        if dry_run:
            logger.info("[dry-run] skipped")
        else:
            from crawlers.wiktionary_kaikki import extract as wikt_extract
            n, e = wikt_extract(NODES_CSV, EDGES_CSV, cefr_map=cefr_map)
            report["stages"]["wiktionary"] = {"nodes": n, "edges": e}
            rows_n, rows_e = _count_csv_rows()
            logger.info("CSV totals after Wiktionary: %d node rows, %d edge rows", rows_n, rows_e)

    # ── Stage 4: Crawl4AI ─────────────────────────────────────────────────
    if "crawl4ai" in stages:
        logger.info("=" * 60)
        logger.info("STAGE: crawl4ai — crawling grammar/idiom/phrasal-verb sites")
        if dry_run:
            logger.info("[dry-run] skipped")
        else:
            from crawlers.web_crawler import extract as web_extract
            n, e = web_extract(NODES_CSV, EDGES_CSV)
            report["stages"]["crawl4ai"] = {"nodes": n, "edges": e}
            rows_n, rows_e = _count_csv_rows()
            logger.info("CSV totals after Crawl4AI: %d node rows, %d edge rows", rows_n, rows_e)

    # ── Stage 5: ConceptNet ────────────────────────────────────────────────
    if "conceptnet" in stages:
        logger.info("=" * 60)
        logger.info("STAGE: conceptnet — downloading+extracting ConceptNet 5.7")
        if dry_run:
            logger.info("[dry-run] skipped")
        else:
            from crawlers.conceptnet_extractor import extract as cn_extract
            n, e = cn_extract(NODES_CSV, EDGES_CSV)
            report["stages"]["conceptnet"] = {"nodes": n, "edges": e}
            rows_n, rows_e = _count_csv_rows()
            logger.info("CSV totals after ConceptNet: %d node rows, %d edge rows", rows_n, rows_e)

    # ── Stage 6: Import ────────────────────────────────────────────────────
    if "import" in stages:
        logger.info("=" * 60)
        logger.info("STAGE: import — bulk-loading CSVs into KuzuDB")
        if dry_run:
            logger.info("[dry-run] skipped")
        else:
            from importers.kuzu_importer import run as kuzu_run
            import_report = kuzu_run(NODES_CSV, EDGES_CSV)
            report["stages"]["import"] = import_report

            final_nodes = import_report.get("node_count", 0)
            pct = final_nodes / TARGET_NODES * 100
            logger.info(
                "KG size: %d / %d target nodes (%.1f%%)",
                final_nodes,
                TARGET_NODES,
                pct,
            )

    # ── Summary ────────────────────────────────────────────────────────────
    report["total_duration_s"] = round(time.time() - t_start, 1)
    logger.info("=" * 60)
    logger.info("Pipeline complete in %.1fs", report["total_duration_s"])

    report_path = KG_RAW_DIR / "import_report.json"
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    logger.info("Report written to %s", report_path)


def main() -> None:
    parser = argparse.ArgumentParser(description="LexiLingo KG crawl pipeline")
    parser.add_argument(
        "--stages",
        default=",".join(ALL_STAGES),
        help=f"Comma-separated stages to run. Available: {', '.join(ALL_STAGES)} (default: all)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print stage plan without executing",
    )
    args = parser.parse_args()

    stages = [s.strip() for s in args.stages.split(",")]
    unknown = [s for s in stages if s not in ALL_STAGES]
    if unknown:
        parser.error(f"Unknown stages: {unknown}. Available: {ALL_STAGES}")

    logger.info("Pipeline stages: %s", stages)
    logger.info("Dry run: %s", args.dry_run)

    run(stages, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
