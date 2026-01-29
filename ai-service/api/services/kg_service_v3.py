"""V3 Knowledge Graph service (skeleton).

This is a thin interface for:
- Expanding concepts (graph hops)
- Writing/learning edges after each interaction

Replace internals with KuzuDB/Neo4j/NetworkX later.
"""

from __future__ import annotations

from typing import Dict, List, Optional, Tuple
import os

import kuzu

from api.core.config import settings
from api.models.v3_schemas import KGHits, KGExpandedNode, KGPath


class KnowledgeGraphServiceV3:
    """KuzuDB-backed KG service for V3 pipeline."""

    def __init__(self) -> None:
        db_path = getattr(settings, "KUZU_DB_PATH", None) or os.path.join(
            os.path.dirname(__file__), "..", "..", "data", "kuzu"
        )
        db_path = os.path.abspath(db_path)
        
        # Create parent directory if doesn't exist
        parent_dir = os.path.dirname(db_path)
        os.makedirs(parent_dir, exist_ok=True)
        
        # Remove if it's a directory (Kuzu needs the path to not exist or be a valid DB)
        if os.path.isdir(db_path):
            import shutil
            shutil.rmtree(db_path)

        self._db = kuzu.Database(db_path)
        self._conn = kuzu.Connection(self._db)
        self._ensure_schema()
        self._seed_default_graph()

    def _ensure_schema(self) -> None:
        # Create tables if they do not exist.
        statements = [
            "CREATE NODE TABLE IF NOT EXISTS Concept(id STRING, title STRING, keywords STRING, PRIMARY KEY(id))",
            "CREATE NODE TABLE IF NOT EXISTS User(id STRING, PRIMARY KEY(id))",
            "CREATE REL TABLE IF NOT EXISTS Edge(FROM Concept TO Concept, relation STRING)",
            "CREATE REL TABLE IF NOT EXISTS Mastery(FROM User TO Concept, score DOUBLE)",
        ]
        for stmt in statements:
            try:
                self._conn.execute(stmt)
            except Exception:
                # Ignore schema creation errors if already exists
                continue

    def _seed_default_graph(self) -> None:
        # Minimal starter concepts for grammar tutoring
        nodes: Dict[str, Dict[str, str]] = {
            "concept:grammar.subject_verb_agreement": {
                "title": "Subject-verb agreement",
                "keywords": "subject verb agreement I you we they base verb goes go",
            },
            "concept:grammar.third_person_s": {
                "title": "Third-person -s",
                "keywords": "third person he she it adds s",
            },
            "concept:grammar.present_simple": {
                "title": "Present simple",
                "keywords": "present simple routines habits every day",
            },
            "concept:grammar.past_time_markers": {
                "title": "Past time markers",
                "keywords": "yesterday last ago past time markers",
            },
        }

        # Edge format: from -> [(to, relation)]
        edges: Dict[str, List[Tuple[str, str]]] = {
            "concept:grammar.subject_verb_agreement": [
                ("concept:grammar.third_person_s", "related_to"),
                ("concept:grammar.present_simple", "related_to"),
            ],
            "concept:grammar.present_simple": [
                ("concept:grammar.past_time_markers", "prerequisite_of"),
            ],
        }

        # Insert nodes
        for node_id, meta in nodes.items():
            title = meta.get("title", "")
            keywords = meta.get("keywords", "")
            try:
                self._conn.execute(
                    "MERGE (c:Concept {id: $id, title: $title, keywords: $keywords})",
                    {"id": node_id, "title": title, "keywords": keywords},
                )
            except Exception:
                continue

        # Insert edges
        for from_id, rels in edges.items():
            for to_id, relation in rels:
                try:
                    self._conn.execute(
                        "MATCH (a:Concept), (b:Concept) WHERE a.id = $from AND b.id = $to "
                        "MERGE (a)-[:Edge {relation: $relation}]->(b)",
                        {"from": from_id, "to": to_id, "relation": relation},
                    )
                except Exception:
                    continue

    def get_concepts(self) -> Dict[str, Dict[str, str]]:
        concepts: Dict[str, Dict[str, str]] = {}
        try:
            result = self._conn.execute("MATCH (c:Concept) RETURN c.id, c.title, c.keywords")
            while result.has_next():
                row = result.get_next()
                concepts[row[0]] = {
                    "title": row[1],
                    "keywords": row[2] or "",
                }
        except Exception:
            return concepts
        return concepts

    async def expand(self, seed_nodes: List[str], hops: int = 1) -> KGHits:
        expanded_nodes: List[KGExpandedNode] = []
        paths: List[KGPath] = []

        if not seed_nodes:
            return KGHits(seed_nodes=[], expanded_nodes=[], paths=[])

        try:
            for seed in seed_nodes:
                result = self._conn.execute(
                    "MATCH (a:Concept)-[e:Edge]->(b:Concept) "
                    "WHERE a.id = $seed RETURN b.id, e.relation",
                    {"seed": seed},
                )
                while result.has_next():
                    row = result.get_next()
                    expanded_nodes.append(KGExpandedNode(id=row[0], relation=row[1]))
                    paths.append(KGPath(from_id=seed, to_id=row[0], hops=1))
        except Exception:
            return KGHits(seed_nodes=seed_nodes, expanded_nodes=[], paths=[])

        return KGHits(seed_nodes=seed_nodes, expanded_nodes=expanded_nodes, paths=paths)

    async def record_interaction(
        self,
        user_id: str,
        session_id: str,
        linked_concepts: List[str],
        error_types: List[str],
    ) -> None:
        if not user_id or not linked_concepts:
            return None

        # Ensure user node exists
        try:
            self._conn.execute(
                "MERGE (u:User {id: $id})",
                {"id": user_id},
            )
        except Exception:
            return None

        for concept_id in linked_concepts:
            # Simple mastery update: decrease on errors, increase otherwise
            delta = -0.05 if error_types else 0.03
            try:
                self._conn.execute(
                    "MATCH (u:User), (c:Concept) "
                    "WHERE u.id = $uid AND c.id = $cid "
                    "MERGE (u)-[m:Mastery]->(c) "
                    "ON CREATE SET m.score = $score "
                    "ON MATCH SET m.score = min(1.0, max(0.0, m.score + $delta))",
                    {"uid": user_id, "cid": concept_id, "score": 0.5, "delta": delta},
                )
            except Exception:
                continue

        return None
