#!/usr/bin/env python3
"""KG Synthesis Script

Rebuilds/updates the KuzuDB knowledge graph from all source data files:
  - data/knowledge_extended.json         (main concepts + relations)
  - data/kg/01_grammar_gaps.json         (grammar gap patterns)
  - data/kg/02_functional_language.json  (functional phrases)
  - data/kg/03_errors_vietnamese.json    (Vietnamese learner errors)
  - data/kg/04_writing_phonology.json    (writing/phonology)
  - data/kg/05_vocabulary_advanced.json  (advanced vocabulary)
  - data/kg/06_tracecag_topic_expansion.json (expanded topic chat corpus)

Usage:
  # From ai-service directory or inside container:
  python scripts/build_kg.py [--force] [--dry-run]

  --force    Wipe existing KG and rebuild from scratch
  --dry-run  Only print what would be imported, no DB writes

Exit codes: 0 = success, 1 = error
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)


# ── Paths ─────────────────────────────────────────────────────────────────────
_SCRIPT_DIR = Path(__file__).resolve().parent
_ROOT = _SCRIPT_DIR.parent
_DATA_DIR = _ROOT / "data"
_KG_DATA_DIR = _DATA_DIR / "kg"

_SOURCES: List[Path] = [
    _DATA_DIR / "knowledge_extended.json",
    _KG_DATA_DIR / "01_grammar_gaps.json",
    _KG_DATA_DIR / "02_functional_language.json",
    _KG_DATA_DIR / "03_errors_vietnamese.json",
    _KG_DATA_DIR / "04_writing_phonology.json",
    _KG_DATA_DIR / "05_vocabulary_advanced.json",
    _KG_DATA_DIR / "06_tracecag_topic_expansion.json",
]


# ── Helpers ───────────────────────────────────────────────────────────────────

def _load_json(path: Path) -> Any:
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        logger.warning("File not found, skipping: %s", path)
        return None
    except json.JSONDecodeError as exc:
        logger.error("Invalid JSON in %s: %s", path, exc)
        return None


def _normalize_level(raw: str) -> str:
    mapping = {"a1": "A1", "a2": "A2", "b1": "B1", "b2": "B2", "c1": "C1", "c2": "C2"}
    return mapping.get((raw or "").strip().lower(), "B1")


def _extract_nodes_and_edges(
    data: Any, source_file: str
) -> Tuple[Dict[str, Dict[str, str]], List[Tuple[str, str, str]]]:
    """Extract concept nodes and edges from a data file.

    Supports several common formats found in this project:
      - {"concepts": [{id, title, keywords, level}], "edges": [{from, to, relation}]}
      - {"nodes": [...], "edges": [...]}
      - {"categories": {"grammar": {"level": "B1", "items": [{...}]}}}
      - flat list of concept dicts
    """
    nodes: Dict[str, Dict[str, str]] = {}
    edges: List[Tuple[str, str, str]] = []

    if not data:
        return nodes, edges

    # Format 1: {"concepts": [...], "edges": [...]}
    raw_concepts = data.get("concepts") or data.get("nodes") or []
    for item in raw_concepts:
        nid = str(item.get("id") or item.get("concept_id") or "").strip()
        if not nid:
            continue
        nodes[nid] = {
            "title": str(item.get("title") or item.get("name") or nid),
            "keywords": str(item.get("keywords") or item.get("tags") or ""),
            "level": _normalize_level(str(item.get("level") or "B1")),
        }

    for edge in (data.get("edges") or data.get("relations") or []):
        src = str(edge.get("from") or edge.get("source") or "").strip()
        dst = str(edge.get("to") or edge.get("target") or "").strip()
        rel = str(edge.get("relation") or edge.get("type") or "related_to").strip()
        if src and dst:
            edges.append((src, dst, rel))

    # Format 2: {"categories": {"<category>": {"level": "B1", "items": [...]}}}
    for cat_name, cat_data in (data.get("categories") or {}).items():
        if not isinstance(cat_data, dict):
            continue
        cat_level = _normalize_level(str(cat_data.get("level") or "B1"))
        for item in (cat_data.get("items") or []):
            nid = str(item.get("id") or item.get("concept_id") or "").strip()
            if not nid:
                continue
            nodes[nid] = {
                "title": str(item.get("title") or item.get("name") or nid),
                "keywords": str(item.get("keywords") or item.get("tags") or cat_name),
                "level": _normalize_level(str(item.get("level") or cat_level)),
            }
            # Build prerequisite edges if present
            for prereq in (item.get("prerequisites") or []):
                edges.append((prereq, nid, "prerequisite_of"))
            for related in (item.get("related") or []):
                edges.append((nid, related, "related_to"))

    # Format 3: top-level list
    if isinstance(data, list):
        for item in data:
            nid = str(item.get("id") or item.get("concept_id") or "").strip()
            if not nid:
                continue
            nodes[nid] = {
                "title": str(item.get("title") or item.get("name") or nid),
                "keywords": str(item.get("keywords") or ""),
                "level": _normalize_level(str(item.get("level") or "B1")),
            }

    logger.info(
        "[%s] extracted %d nodes, %d edges",
        Path(source_file).name, len(nodes), len(edges),
    )
    return nodes, edges


# ── Core rebuild logic ────────────────────────────────────────────────────────

def run(force: bool = False, dry_run: bool = False) -> int:
    """Main synthesis logic. Returns exit code."""
    # Add repo to path so we can import project modules
    sys.path.insert(0, str(_ROOT))

    try:
        import kuzu  # noqa: F401
    except ImportError:
        logger.error("kuzu package not installed. Run: pip install kuzu")
        return 1

    from api.core.config import settings
    db_path = os.path.abspath(
        getattr(settings, "KUZU_DB_PATH", None)
        or str(_DATA_DIR / "kuzu")
    )
    logger.info("KuzuDB path: %s", db_path)

    # Collect all source data
    all_nodes: Dict[str, Dict[str, str]] = {}
    all_edges: List[Tuple[str, str, str]] = []

    for src_path in _SOURCES:
        data = _load_json(src_path)
        if data is None:
            continue
        nodes, edges = _extract_nodes_and_edges(data, str(src_path))
        all_nodes.update(nodes)
        all_edges.extend(edges)

    logger.info(
        "Total: %d unique nodes, %d edges from %d source files",
        len(all_nodes), len(all_edges), len(_SOURCES),
    )

    if dry_run:
        logger.info("[DRY RUN] No writes performed.")
        return 0

    # Open (or rebuild) KuzuDB
    if force and os.path.isdir(db_path):
        import shutil, time as _t
        ts = int(_t.time() * 1000)
        backup = f"{db_path}.backup.{ts}"
        logger.info("Force mode: renaming existing DB to %s", backup)
        os.rename(db_path, backup)

    os.makedirs(os.path.dirname(db_path), exist_ok=True)
    import kuzu

    db = kuzu.Database(db_path)
    conn = kuzu.Connection(db)

    # Ensure schema
    for stmt in [
        "CREATE NODE TABLE IF NOT EXISTS Concept(id STRING, title STRING, keywords STRING, level STRING DEFAULT 'B1', PRIMARY KEY(id))",
        "CREATE NODE TABLE IF NOT EXISTS User(id STRING, PRIMARY KEY(id))",
        "CREATE REL TABLE IF NOT EXISTS Edge(FROM Concept TO Concept, relation STRING)",
        "CREATE REL TABLE IF NOT EXISTS Mastery(FROM User TO Concept, score DOUBLE)",
    ]:
        try:
            conn.execute(stmt)
        except Exception:
            pass
    try:
        conn.execute("ALTER TABLE Concept ADD level STRING DEFAULT 'B1'")
    except Exception:
        pass

    # Upsert nodes (MERGE equivalent — delete + reinsert for updates)
    inserted_nodes = 0
    skipped_nodes = 0
    t0 = time.time()
    for nid, attrs in all_nodes.items():
        title = attrs["title"].replace("'", "''")
        keywords = attrs["keywords"].replace("'", "''")
        level = attrs["level"]
        # Try insert first; on duplicate skip
        try:
            conn.execute(
                f"CREATE (c:Concept {{id: '{nid}', title: '{title}', keywords: '{keywords}', level: '{level}'}})"
            )
            inserted_nodes += 1
        except Exception:
            # Node exists — update it
            try:
                conn.execute(
                    f"MATCH (c:Concept {{id: '{nid}'}}) "
                    f"SET c.title = '{title}', c.keywords = '{keywords}', c.level = '{level}'"
                )
                skipped_nodes += 1
            except Exception as exc:
                logger.warning("Could not upsert node %s: %s", nid, exc)

    logger.info(
        "Nodes: %d inserted, %d updated in %.1fs",
        inserted_nodes, skipped_nodes, time.time() - t0,
    )

    # Insert edges (skip on duplicate)
    inserted_edges = 0
    t1 = time.time()
    for src, dst, rel in all_edges:
        # Only create edge if both endpoints exist
        if src not in all_nodes or dst not in all_nodes:
            continue
        rel_safe = rel.replace("'", "''")
        try:
            conn.execute(
                f"MATCH (a:Concept {{id: '{src}'}}), (b:Concept {{id: '{dst}'}}) "
                f"CREATE (a)-[:Edge {{relation: '{rel_safe}'}}]->(b)"
            )
            inserted_edges += 1
        except Exception:
            pass  # Duplicate or endpoint missing

    logger.info(
        "Edges: %d inserted in %.1fs",
        inserted_edges, time.time() - t1,
    )

    # Count final state
    try:
        result = conn.execute("MATCH (c:Concept) RETURN count(c) AS total")
        row = result.get_next()
        total_concepts = row[0] if row else "?"
    except Exception:
        total_concepts = "?"

    logger.info("KG synthesis complete. Total concepts in DB: %s", total_concepts)
    return 0


# ── CLI entrypoint ────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="LexiLingo KG synthesis script")
    parser.add_argument(
        "--force",
        action="store_true",
        help="Back up and rebuild the KG DB from scratch",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Parse sources but skip all DB writes",
    )
    args = parser.parse_args()
    sys.exit(run(force=args.force, dry_run=args.dry_run))


if __name__ == "__main__":
    main()
