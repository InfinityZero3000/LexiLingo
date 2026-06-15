"""Paths for importing LexiLingo-owned knowledge-graph data."""

from pathlib import Path


PIPELINE_DIR = Path(__file__).parent
AI_SERVICE_DIR = PIPELINE_DIR.parent.parent
KG_DOMAIN_DIR = AI_SERVICE_DIR / "data" / "kg"
KG_RAW_DIR = AI_SERVICE_DIR / "data" / "kg_raw"
KUZU_DB_PATH = AI_SERVICE_DIR / "models" / "kuzu_db"

NODES_CSV = KG_RAW_DIR / "nodes.csv"
EDGES_CSV = KG_RAW_DIR / "edges.csv"
PROGRESS_DIR = KG_RAW_DIR / "progress"
TARGET_NODES = 1_000_000
