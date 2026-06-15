#!/usr/bin/env python3
"""Import LexiLingo-owned KG JSON/CSV data without external web crawling."""

from __future__ import annotations

import argparse
import csv
import json
import logging
import sys
import time
from pathlib import Path


_PIPELINE_DIR = Path(__file__).parent
sys.path.insert(0, str(_PIPELINE_DIR))

from config import EDGES_CSV, KG_DOMAIN_DIR, KG_RAW_DIR, NODES_CSV, PROGRESS_DIR


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s - %(message)s",
)
logger = logging.getLogger("kg-import")

ALL_STAGES = ["domain_json", "import"]


def _init_csv_files() -> None:
    KG_RAW_DIR.mkdir(parents=True, exist_ok=True)
    PROGRESS_DIR.mkdir(parents=True, exist_ok=True)
    NODES_CSV.touch(exist_ok=True)
    EDGES_CSV.touch(exist_ok=True)


def _load_existing_domain_json() -> tuple[int, int]:
    """Append only repository-owned domain concepts and relations."""

    checkpoint = PROGRESS_DIR / "domain_json.done"
    if checkpoint.exists():
        logger.info("Domain JSON already imported; skipping")
        return 0, 0

    node_count = 0
    edge_count = 0
    with (
        NODES_CSV.open("a", newline="", encoding="utf-8") as node_file,
        EDGES_CSV.open("a", newline="", encoding="utf-8") as edge_file,
    ):
        node_writer = csv.writer(node_file)
        edge_writer = csv.writer(edge_file)
        for json_path in sorted(KG_DOMAIN_DIR.glob("*.json")):
            try:
                data = json.loads(json_path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError) as exc:
                logger.warning("Skipping %s: %s", json_path.name, exc)
                continue

            for concept in data.get("concepts", []):
                node_writer.writerow(
                    [
                        concept["id"],
                        concept.get("title", ""),
                        concept.get("keywords", ""),
                        concept.get("level", "B1"),
                    ]
                )
                node_count += 1

            for edge in data.get("edges", []):
                edge_writer.writerow(
                    [
                        edge["from"],
                        edge["to"],
                        edge.get("relation", "related_to"),
                    ]
                )
                edge_count += 1

    checkpoint.touch()
    return node_count, edge_count


def run(stages: list[str], *, dry_run: bool = False) -> dict:
    started_at = time.time()
    report: dict[str, object] = {"stages": {}, "dry_run": dry_run}
    if dry_run:
        logger.info("Dry-run stages: %s", stages)
        report["planned_stages"] = stages
        return report

    _init_csv_files()
    if "domain_json" in stages:
        nodes, edges = _load_existing_domain_json()
        report["stages"]["domain_json"] = {"nodes": nodes, "edges": edges}

    if "import" in stages:
        from importers.kuzu_importer import run as import_kuzu

        report["stages"]["import"] = import_kuzu(NODES_CSV, EDGES_CSV)

    report["total_duration_s"] = round(time.time() - started_at, 1)
    report_path = KG_RAW_DIR / "import_report.json"
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Import LexiLingo-owned knowledge-graph data",
    )
    parser.add_argument(
        "--stages",
        default=",".join(ALL_STAGES),
        help=f"Comma-separated stages: {', '.join(ALL_STAGES)}",
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    stages = list(dict.fromkeys(item.strip() for item in args.stages.split(",")))
    unknown = sorted(set(stages) - set(ALL_STAGES))
    if unknown:
        parser.error(f"Unknown stages: {', '.join(unknown)}")
    run(stages, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
