"""V3 Knowledge Graph service (skeleton).

This is a thin interface for:
- Expanding concepts (graph hops)
- Writing/learning edges after each interaction

Replace internals with KuzuDB/Neo4j/NetworkX later.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional, Tuple
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
        """
        Seed comprehensive curriculum concepts for English learning.
        
        Structure:
        - Grammar concepts (A1 → C2)
        - Vocabulary domains
        - Pronunciation patterns
        - Common error patterns for Vietnamese learners
        """
        nodes: Dict[str, Dict[str, str]] = {
            # ============================================
            # GRAMMAR - Level A1 (Beginner)
            # ============================================
            "concept:grammar.subject_verb_agreement": {
                "title": "Subject-verb agreement",
                "keywords": "subject verb agreement I you we they base verb goes go",
                "level": "A1",
            },
            "concept:grammar.third_person_s": {
                "title": "Third-person -s",
                "keywords": "third person he she it adds s",
                "level": "A1",
            },
            "concept:grammar.present_simple": {
                "title": "Present Simple",
                "keywords": "present simple routines habits every day always usually",
                "level": "A1",
            },
            "concept:grammar.articles_a_an": {
                "title": "Articles a/an",
                "keywords": "article a an indefinite countable singular noun",
                "level": "A1",
            },
            "concept:grammar.to_be": {
                "title": "Verb to be",
                "keywords": "am is are was were be being been",
                "level": "A1",
            },
            "concept:grammar.plural_nouns": {
                "title": "Plural nouns",
                "keywords": "plural s es ies irregular plurals",
                "level": "A1",
            },
            
            # ============================================
            # GRAMMAR - Level A2 (Elementary)
            # ============================================
            "concept:grammar.past_simple": {
                "title": "Past Simple",
                "keywords": "past simple ed yesterday last ago regular irregular",
                "level": "A2",
            },
            "concept:grammar.past_time_markers": {
                "title": "Past time markers",
                "keywords": "yesterday last ago past time markers week month",
                "level": "A2",
            },
            "concept:grammar.future_will": {
                "title": "Future with will",
                "keywords": "will future prediction promise tomorrow next",
                "level": "A2",
            },
            "concept:grammar.going_to": {
                "title": "Going to for plans",
                "keywords": "going to plan intention future arranged",
                "level": "A2",
            },
            "concept:grammar.comparatives": {
                "title": "Comparatives",
                "keywords": "comparative er more than bigger better worse",
                "level": "A2",
            },
            "concept:grammar.superlatives": {
                "title": "Superlatives",
                "keywords": "superlative est most the biggest best worst",
                "level": "A2",
            },
            
            # ============================================
            # GRAMMAR - Level B1 (Intermediate)
            # ============================================
            "concept:grammar.present_perfect": {
                "title": "Present Perfect",
                "keywords": "present perfect have has ed experience ever never since for",
                "level": "B1",
            },
            "concept:grammar.present_continuous": {
                "title": "Present Continuous",
                "keywords": "present continuous progressive ing now currently at the moment",
                "level": "B1",
            },
            "concept:grammar.conditionals_first": {
                "title": "First Conditional",
                "keywords": "if will first conditional real possible future",
                "level": "B1",
            },
            "concept:grammar.modal_can_could": {
                "title": "Modal: can/could",
                "keywords": "can could ability permission possibility request",
                "level": "B1",
            },
            "concept:grammar.modal_must_should": {
                "title": "Modal: must/should",
                "keywords": "must should obligation advice necessity recommendation",
                "level": "B1",
            },
            "concept:grammar.passive_voice": {
                "title": "Passive Voice",
                "keywords": "passive voice be done was made is being by agent",
                "level": "B1",
            },
            
            # ============================================
            # GRAMMAR - Level B2 (Upper-Intermediate)
            # ============================================
            "concept:grammar.past_perfect": {
                "title": "Past Perfect",
                "keywords": "past perfect had done before after earlier",
                "level": "B2",
            },
            "concept:grammar.conditionals_second": {
                "title": "Second Conditional",
                "keywords": "if would second conditional unreal hypothetical imagine",
                "level": "B2",
            },
            "concept:grammar.conditionals_third": {
                "title": "Third Conditional",
                "keywords": "if would have third conditional past unreal regret",
                "level": "B2",
            },
            "concept:grammar.relative_clauses": {
                "title": "Relative Clauses",
                "keywords": "relative clause who which that whose whom defining non-defining",
                "level": "B2",
            },
            "concept:grammar.reported_speech": {
                "title": "Reported Speech",
                "keywords": "reported speech indirect said told asked that would",
                "level": "B2",
            },
            
            # ============================================
            # GRAMMAR - Level C1 (Advanced)
            # ============================================
            "concept:grammar.inversion": {
                "title": "Inversion",
                "keywords": "inversion never rarely seldom hardly scarcely not only",
                "level": "C1",
            },
            "concept:grammar.cleft_sentences": {
                "title": "Cleft Sentences",
                "keywords": "cleft it is what who emphasis focus",
                "level": "C1",
            },
            "concept:grammar.mixed_conditionals": {
                "title": "Mixed Conditionals",
                "keywords": "mixed conditional past present result cause",
                "level": "C1",
            },
            
            # ============================================
            # VOCABULARY DOMAINS
            # ============================================
            "concept:vocab.daily_life": {
                "title": "Daily Life Vocabulary",
                "keywords": "daily routine morning evening food home family",
                "level": "A1",
            },
            "concept:vocab.work_business": {
                "title": "Work & Business",
                "keywords": "work office meeting business job career professional",
                "level": "B1",
            },
            "concept:vocab.academic": {
                "title": "Academic Vocabulary",
                "keywords": "academic research study analyze evaluate evidence",
                "level": "B2",
            },
            
            # ============================================
            # COMMON ERRORS (Vietnamese Learners)
            # ============================================
            "concept:error.article_omission": {
                "title": "Article Omission",
                "keywords": "missing article the a an Vietnamese learner",
                "level": "A1",
            },
            "concept:error.tense_confusion": {
                "title": "Tense Confusion",
                "keywords": "wrong tense past present future confused",
                "level": "A2",
            },
            "concept:error.subject_pronoun_drop": {
                "title": "Subject Pronoun Drop",
                "keywords": "missing subject pronoun I he she it",
                "level": "A1",
            },
        }

        # Edge format: from -> [(to, relation)]
        edges: Dict[str, List[Tuple[str, str]]] = {
            # A1 → A2 prerequisites
            "concept:grammar.present_simple": [
                ("concept:grammar.past_simple", "prerequisite_of"),
                ("concept:grammar.present_continuous", "prerequisite_of"),
            ],
            "concept:grammar.to_be": [
                ("concept:grammar.present_continuous", "prerequisite_of"),
                ("concept:grammar.passive_voice", "prerequisite_of"),
            ],
            "concept:grammar.subject_verb_agreement": [
                ("concept:grammar.third_person_s", "related_to"),
                ("concept:grammar.present_simple", "related_to"),
            ],
            
            # A2 → B1 prerequisites
            "concept:grammar.past_simple": [
                ("concept:grammar.present_perfect", "prerequisite_of"),
                ("concept:grammar.past_perfect", "prerequisite_of"),
            ],
            "concept:grammar.future_will": [
                ("concept:grammar.conditionals_first", "prerequisite_of"),
            ],
            
            # B1 → B2 prerequisites
            "concept:grammar.conditionals_first": [
                ("concept:grammar.conditionals_second", "prerequisite_of"),
            ],
            "concept:grammar.conditionals_second": [
                ("concept:grammar.conditionals_third", "prerequisite_of"),
                ("concept:grammar.mixed_conditionals", "prerequisite_of"),
            ],
            "concept:grammar.present_perfect": [
                ("concept:grammar.past_perfect", "prerequisite_of"),
            ],
            
            # Related concepts
            "concept:grammar.comparatives": [
                ("concept:grammar.superlatives", "related_to"),
            ],
            "concept:grammar.articles_a_an": [
                ("concept:error.article_omission", "related_to"),
            ],
            "concept:grammar.past_time_markers": [
                ("concept:error.tense_confusion", "related_to"),
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
            while result.has_next():  # type: ignore[union-attr]
                row: list = result.get_next()  # type: ignore[union-attr]
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
                while result.has_next():  # type: ignore[union-attr]
                    row: list = result.get_next()  # type: ignore[union-attr]
                    expanded_nodes.append(KGExpandedNode(id=row[0], type=row[1], properties={"relation": row[1]}))
                    paths.append(KGPath(nodes=[seed, row[0]], edges=[row[1]]))
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

    async def get_user_mastery(self, user_id: str) -> Dict[str, float]:
        """
        Get mastery scores for all concepts a user has interacted with.
        
        Returns:
            Dict mapping concept_id -> mastery_score (0.0 to 1.0)
        """
        mastery: Dict[str, float] = {}
        
        if not user_id:
            return mastery
        
        try:
            result = self._conn.execute(
                "MATCH (u:User)-[m:Mastery]->(c:Concept) "
                "WHERE u.id = $uid RETURN c.id, m.score",
                {"uid": user_id},
            )
            while result.has_next():  # type: ignore[union-attr]
                row: list = result.get_next()  # type: ignore[union-attr]
                mastery[row[0]] = row[1]
        except Exception:
            pass
        
        return mastery

    async def get_recommended_concepts(
        self, 
        user_id: str, 
        current_level: str = "B1",
        limit: int = 5
    ) -> List[Dict[str, Any]]:
        """
        Get recommended concepts for a user based on:
        1. Low mastery concepts at current level
        2. Prerequisites of weak concepts
        3. Concepts they haven't seen yet
        
        Returns:
            List of recommended concept dicts with id, title, reason
        """
        recommendations: List[Dict[str, Any]] = []
        level_order = ["A1", "A2", "B1", "B2", "C1", "C2"]
        
        try:
            # Get user's current mastery
            user_mastery = await self.get_user_mastery(user_id)
            
            # Find weak concepts (mastery < 0.6) at current level
            all_concepts = self.get_concepts()
            
            for concept_id, meta in all_concepts.items():
                if len(recommendations) >= limit:
                    break
                    
                # Check if this is a concept at appropriate level
                # (Keywords don't have level stored yet, so check all)
                mastery_score = user_mastery.get(concept_id, 0.5)
                
                if mastery_score < 0.6:
                    recommendations.append({
                        "id": concept_id,
                        "title": meta.get("title", ""),
                        "mastery": mastery_score,
                        "reason": "Low mastery - needs practice",
                    })
            
            # If not enough recommendations, add unseen concepts
            if len(recommendations) < limit:
                for concept_id, meta in all_concepts.items():
                    if len(recommendations) >= limit:
                        break
                    if concept_id not in user_mastery:
                        recommendations.append({
                            "id": concept_id,
                            "title": meta.get("title", ""),
                            "mastery": 0.5,
                            "reason": "New concept to explore",
                        })
                        
        except Exception:
            pass
        
        return recommendations[:limit]

    async def get_prerequisites(self, concept_id: str) -> List[str]:
        """
        Get prerequisites for a concept (concepts that should be mastered first).
        
        Returns:
            List of prerequisite concept IDs
        """
        prerequisites: List[str] = []
        
        try:
            result = self._conn.execute(
                "MATCH (a:Concept)-[e:Edge]->(b:Concept) "
                "WHERE b.id = $cid AND e.relation = 'prerequisite_of' "
                "RETURN a.id",
                {"cid": concept_id},
            )
            while result.has_next():  # type: ignore[union-attr]
                row: list = result.get_next()  # type: ignore[union-attr]
                prerequisites.append(row[0])
        except Exception:
            pass
        
        return prerequisites

    async def get_next_concepts(self, concept_id: str) -> List[str]:
        """
        Get concepts that this concept is a prerequisite for.
        
        Returns:
            List of concept IDs that build on this concept
        """
        next_concepts: List[str] = []
        
        try:
            result = self._conn.execute(
                "MATCH (a:Concept)-[e:Edge]->(b:Concept) "
                "WHERE a.id = $cid AND e.relation = 'prerequisite_of' "
                "RETURN b.id",
                {"cid": concept_id},
            )
            while result.has_next():  # type: ignore[union-attr]
                row: list = result.get_next()  # type: ignore[union-attr]
                next_concepts.append(row[0])
        except Exception:
            pass
        
        return next_concepts

    def get_concept_count(self) -> int:
        """Get total number of concepts in the graph."""
        try:
            result = self._conn.execute("MATCH (c:Concept) RETURN count(c)")
            if result.has_next():  # type: ignore[union-attr]
                return result.get_next()[0]  # type: ignore[union-attr]
        except Exception:
            pass
        return 0

