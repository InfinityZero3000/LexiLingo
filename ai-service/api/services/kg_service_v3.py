"""V3 Knowledge Graph service.

This is a thin interface for:
- Expanding concepts (graph hops)
- Writing/learning edges after each interaction

Uses KuzuDB as the graph database backend.
Singleton pattern ensures the database is created once and reused.
"""

from __future__ import annotations

import asyncio
import logging
from typing import Any, Dict, List, Optional, Tuple
import os
import shutil
import time
import re

import kuzu

from api.core.config import settings
from api.models.v3_schemas import KGHits, KGExpandedNode, KGPath
from api.services.kg_data_loader import (
    load_json_object,
    merge_knowledge_payload,
    sync_knowledge_files,
)

logger = logging.getLogger(__name__)


def _env_enabled(name: str) -> bool:
    return os.getenv(name, "").strip().lower() in {"1", "true", "yes", "on"}

# ── Singleton instance ────────────────────────────────────────────────────────
_kg_instance: Optional["KnowledgeGraphServiceV3"] = None


def get_kg_service() -> "KnowledgeGraphServiceV3":
    """Get or create the singleton KnowledgeGraphServiceV3 instance."""
    global _kg_instance
    if _kg_instance is None:
        _kg_instance = KnowledgeGraphServiceV3()
    return _kg_instance


class KnowledgeGraphServiceV3:
    """KuzuDB-backed KG service for V3 pipeline (singleton via get_kg_service())."""

    def __init__(self) -> None:
        db_path = getattr(settings, "KUZU_DB_PATH", None) or os.path.join(
            os.path.dirname(__file__), "..", "..", "data", "kuzu"
        )
        self._db_path = os.path.abspath(db_path)
        self._strict_snapshot = _env_enabled("TRACECAG_KG_STRICT_SNAPSHOT")
        self._recovery_attempted = False
        self._lock = asyncio.Lock()

        # ── In-memory caches (Phase 1) ─────────────────────────────────────
        # _concepts_cache: None = cold (not yet built); Dict = warm
        self._concepts_cache: Optional[Dict[str, Dict[str, str]]] = None
        # inverted index: keyword → [concept_id, ...]  (O(1) lookup)
        self._keyword_index: Dict[str, List[str]] = {}
        # TF-IDF structures (Phase 3, pure Python)
        self._tfidf_concept_ids: List[str] = []
        self._tfidf_idf: Dict[str, float] = {}
        self._tfidf_vectors: List[Dict[str, float]] = []
        # ──────────────────────────────────────────────────────────────────

        # Create parent directory if doesn't exist
        parent_dir = os.path.dirname(self._db_path)
        os.makedirs(parent_dir, exist_ok=True)
        
        # Only destroy and recreate if the DB is corrupted or missing.
        # Check if schema already exists to avoid unnecessary re-seed.
        needs_seed = not os.path.exists(self._db_path)
        
        try:
            self._db = kuzu.Database(self._db_path)
            self._conn = kuzu.Connection(self._db)
            self._ensure_schema()
            
            # Only seed if this is a fresh database
            concept_count = self.get_concept_count()
            if self._strict_snapshot and (needs_seed or concept_count == 0):
                raise RuntimeError(
                    f"Benchmark strict snapshot is missing or empty: {self._db_path}"
                )
            if needs_seed or concept_count == 0:
                logger.info("[KG] Seeding default knowledge graph...")
                self._seed_default_graph()
                # Clear synced files metadata cache on fresh database
                cache_path = self._db_path + "_synced_files.json"
                if os.path.exists(cache_path):
                    try:
                        os.remove(cache_path)
                    except Exception as _exc:
                        logger.debug("[kg_service_v3] ignored: %s", _exc)
                        pass
            else:
                logger.info(f"[KG] Reusing existing KG with {self.get_concept_count()} concepts")

            # Benchmark evaluation is read-oriented and must not mutate the KG
            # snapshot that the run is meant to measure.
            if os.getenv("TRACECAG_KG_SKIP_SYNC", "").lower() not in {"1", "true", "yes", "on"}:
                self._sync_external_knowledge()

            # Warm in-memory caches after all DB writes are done.
            self._build_concept_cache()
        except Exception as e:
            if self._strict_snapshot:
                logger.error("[KG] Strict snapshot initialization failed: %s", e)
                raise
            logger.warning(f"[KG] DB may be corrupted, rebuilding: {e}")
            self._hard_rebuild_db(reason=str(e))

    def _hard_rebuild_db(self, reason: str = "unknown") -> None:
        """Rebuild Kuzu DB from scratch when corruption is detected."""
        if self._strict_snapshot:
            raise RuntimeError(f"KG rebuild disabled for benchmark strict snapshot: {reason}")
        logger.warning("[KG] Hard rebuild triggered: %s", reason)
        if os.path.isdir(self._db_path):
            if "lock" in reason.lower():
                logger.error("[KG] DB locked, cannot rebuild safely: %s", self._db_path)
                raise RuntimeError(reason)
            ts = int(time.time() * 1000)
            quarantine = f"{self._db_path}.corrupt.{ts}"
            suffix = 1
            while os.path.exists(quarantine):
                quarantine = f"{self._db_path}.corrupt.{ts}.{suffix}"
                suffix += 1
            try:
                os.rename(self._db_path, quarantine)
                logger.warning("[KG] Quarantined corrupted DB to %s", quarantine)
            except Exception:
                shutil.rmtree(self._db_path, ignore_errors=True)
        elif os.path.exists(self._db_path):
            os.remove(self._db_path)

        # Current Kuzu Python releases use a database file at ``_db_path``.
        # Creating a directory with that name makes the subsequent open fail
        # with "Database path cannot be a directory".
        os.makedirs(os.path.dirname(self._db_path), exist_ok=True)
        # Clear synced files metadata cache on rebuild
        cache_path = self._db_path + "_synced_files.json"
        if os.path.exists(cache_path):
            try:
                os.remove(cache_path)
            except Exception as _exc:
                logger.debug("[kg_service_v3] ignored: %s", _exc)
                pass
        self._db = kuzu.Database(self._db_path)
        self._conn = kuzu.Connection(self._db)
        self._ensure_schema()
        self._seed_default_graph()
        if os.getenv("TRACECAG_KG_SKIP_SYNC", "").lower() not in {"1", "true", "yes", "on"}:
            self._sync_external_knowledge()
        self._build_concept_cache()
        self._recovery_attempted = True

    def _is_corruption_error(self, exc: Exception) -> bool:
        text = str(exc).lower()
        return (
            "reading past the end of the file" in text
            or "corrupt" in text
            or "checksum" in text
            or "invalid" in text
        )

    def _recover_and_retry(self, op_name: str) -> bool:
        if self._strict_snapshot:
            logger.error("[KG] Recovery disabled for benchmark strict snapshot: %s", op_name)
            return False
        if self._recovery_attempted:
            return False
        try:
            logger.warning("[KG] Attempting one-time recovery for %s", op_name)
            self._hard_rebuild_db(reason=f"runtime failure during {op_name}")
            return True
        except Exception as rebuild_exc:
            logger.error("[KG] Recovery failed for %s: %s", op_name, rebuild_exc)
            return False

    def _ensure_schema(self) -> None:
        # Create tables if they do not exist.
        statements = [
            "CREATE NODE TABLE IF NOT EXISTS Concept(id STRING, title STRING, keywords STRING, level STRING DEFAULT 'B1', PRIMARY KEY(id))",
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
        # Add level column to existing Concept table if it was created without it
        try:
            self._conn.execute("ALTER TABLE Concept ADD level STRING DEFAULT 'B1'")
        except Exception:
            pass  # column already exists

    def _seed_default_graph(self) -> None:
        """Seed built-in curriculum concepts from data/kg/seed_graph.json.

        The JSON file is the source of truth for the default graph.  Editing
        seed_graph.json and restarting the service (or deleting the Kuzu DB)
        is enough to update the seeded knowledge — no code changes required.
        """
        seed_path = os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "data", "kg", "seed_graph.json")
        )
        try:
            payload = load_json_object(seed_path)
        except (OSError, ValueError) as exc:
            logger.error("[KG] Cannot load seed_graph.json (%s): %s", seed_path, exc)
            return

        stats = merge_knowledge_payload(self._conn, payload)
        logger.info(
            "[KG] Seeded from seed_graph.json: concepts=%d edges=%d",
            stats.concepts,
            stats.edges,
        )

    def _extended_knowledge_path(self) -> str:
        configured = os.getenv("KG_EXTENDED_KNOWLEDGE_PATH", "").strip()
        if configured:
            return os.path.abspath(configured)
        default_path = os.path.join(os.path.dirname(__file__), "..", "..", "data", "knowledge_extended.json")
        return os.path.abspath(default_path)

    def _kg_data_dir(self) -> str:
        """Return path to the domain-specific KG data directory (data/kg/)."""
        return os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "data", "kg")
        )

    def _sync_external_knowledge(self) -> None:
        """Load all knowledge JSON files into KuzuDB (non-destructive MERGE).

        Sources (in order):
        1. data/knowledge_extended.json  — legacy single-file, for backward compat
        2. data/kg/*.json                 — domain-specific files, one per topic area
        """
        cache_path = self._db_path + "_synced_files.json"
        paths: List[str] = []
        legacy = self._extended_knowledge_path()
        if os.path.isfile(legacy):
            paths.append(legacy)

        kg_dir = self._kg_data_dir()
        if os.path.isdir(kg_dir):
            for fname in sorted(os.listdir(kg_dir)):
                if fname.endswith(".json"):
                    paths.append(os.path.join(kg_dir, fname))

        sync_knowledge_files(self._conn, paths, cache_path)

    def get_concepts(self) -> Dict[str, Dict[str, str]]:
        # Return warm in-memory cache if available (Phase 1 optimisation).
        if self._concepts_cache is not None:
            return self._concepts_cache

        concepts: Dict[str, Dict[str, str]] = {}
        try:
            result = self._conn.execute("MATCH (c:Concept) RETURN c.id, c.title, c.keywords, c.level")
            while result.has_next():  # type: ignore[union-attr]
                row: list = result.get_next()  # type: ignore[union-attr]
                concepts[row[0]] = {
                    "title": row[1],
                    "keywords": row[2] or "",
                    "level": row[3] or "B1",
                }
        except Exception as exc:
            if self._is_corruption_error(exc) and self._recover_and_retry("get_concepts"):
                return self.get_concepts()
            return concepts
        return concepts

    # ── Phase 1: In-Memory Concept Cache + Inverted Keyword Index ─────────────

    def _build_concept_cache(self) -> None:
        """Query KuzuDB once, populate _concepts_cache + _keyword_index + TF-IDF."""
        cache: Dict[str, Dict[str, str]] = {}
        keyword_index: Dict[str, List[str]] = {}
        try:
            result = self._conn.execute(
                "MATCH (c:Concept) RETURN c.id, c.title, c.keywords, c.level"
            )
            while result.has_next():  # type: ignore[union-attr]
                row: list = result.get_next()  # type: ignore[union-attr]
                cid: str = row[0]
                title: str = row[1] or ""
                keywords: str = row[2] or ""
                level: str = row[3] or "B1"
                cache[cid] = {"title": title, "keywords": keywords, "level": level}
                # Build inverted keyword index
                for tok in re.findall(r"[a-z0-9_']+", (f"{title} {keywords}").lower()):
                    if len(tok) >= 3:
                        keyword_index.setdefault(tok, []).append(cid)
        except Exception as exc:
            logger.warning("[KG] _build_concept_cache failed: %s", exc)
            return

        self._concepts_cache = cache
        self._keyword_index = keyword_index
        logger.info(
            "[KG] Concept cache warmed: %d concepts, %d index keys",
            len(cache), len(keyword_index),
        )
        self._build_tfidf_index()

    def _invalidate_concept_cache(self) -> None:
        """Clear concept cache so next get_concepts() rebuilds from KuzuDB."""
        self._concepts_cache = None
        self._keyword_index = {}
        self._tfidf_concept_ids = []
        self._tfidf_idf = {}
        self._tfidf_vectors = []

    def get_seed_concepts_fast(self, text: str) -> List[str]:
        """O(words_in_text) concept seeding via inverted keyword index.

        Replaces the O(n_concepts × n_keywords) loop in kg_expand_node Phase 1.
        """
        if not self._keyword_index:
            return []
        tokens = re.findall(r"[a-z0-9_']+", text.lower())
        seen: set = set()
        seeds: List[str] = []
        for tok in tokens:
            if len(tok) < 3:
                continue
            for cid in self._keyword_index.get(tok, []):
                if cid not in seen:
                    seen.add(cid)
                    seeds.append(cid)
        return seeds

    # ── Phase 3: Pure-Python TF-IDF Semantic Matching ─────────────────────────

    def _build_tfidf_index(self) -> None:
        """Build a lightweight TF-IDF index over concept keyword strings.

        Uses pure Python (no sklearn) — fast enough for ~150 concept documents.
        """
        import math

        if not self._concepts_cache:
            return

        concept_ids = list(self._concepts_cache.keys())
        corpus: List[str] = [
            f"{self._concepts_cache[cid]['title']} {self._concepts_cache[cid]['keywords']}"
            for cid in concept_ids
        ]

        # Tokenise each document
        tokenised: List[List[str]] = [
            [tok for tok in re.findall(r"[a-z0-9_']+", doc.lower()) if len(tok) >= 3]
            for doc in corpus
        ]

        N = len(tokenised)
        if N == 0:
            return

        # Document frequency per term
        df: Dict[str, int] = {}
        for tokens in tokenised:
            for tok in set(tokens):
                df[tok] = df.get(tok, 0) + 1

        # IDF with smoothing
        idf: Dict[str, float] = {
            tok: math.log((N + 1) / (cnt + 1)) + 1.0
            for tok, cnt in df.items()
        }

        # TF-IDF vectors (normalised)
        vectors: List[Dict[str, float]] = []
        for tokens in tokenised:
            if not tokens:
                vectors.append({})
                continue
            tf: Dict[str, float] = {}
            for tok in tokens:
                tf[tok] = tf.get(tok, 0) + 1.0
            total = len(tokens)
            vec: Dict[str, float] = {}
            norm = 0.0
            for tok, cnt in tf.items():
                v = (cnt / total) * idf.get(tok, 1.0)
                vec[tok] = v
                norm += v * v
            if norm > 0:
                sqrt_norm = norm ** 0.5
                vec = {t: v / sqrt_norm for t, v in vec.items()}
            vectors.append(vec)

        self._tfidf_concept_ids = concept_ids
        self._tfidf_idf = idf
        self._tfidf_vectors = vectors
        logger.info("[KG] TF-IDF index built: %d concepts, %d unique terms", N, len(idf))

    def semantic_seed_concepts(self, text: str, top_k: int = 5) -> List[str]:
        """Return top-K concept IDs by TF-IDF cosine similarity to *text*.

        Complements get_seed_concepts_fast() by catching semantic matches that
        exact keyword matching misses (e.g. 'struggling' → 'error_*' concepts).
        """

        if not self._tfidf_vectors or not self._tfidf_idf:
            return []

        tokens = [tok for tok in re.findall(r"[a-z0-9_']+", text.lower()) if len(tok) >= 3]
        if not tokens:
            return []

        # Build query vector
        tf: Dict[str, float] = {}
        for tok in tokens:
            tf[tok] = tf.get(tok, 0) + 1.0
        total = len(tokens)
        query_vec: Dict[str, float] = {}
        norm = 0.0
        for tok, cnt in tf.items():
            if tok in self._tfidf_idf:
                v = (cnt / total) * self._tfidf_idf[tok]
                query_vec[tok] = v
                norm += v * v
        if norm == 0:
            return []
        sqrt_norm = norm ** 0.5
        query_vec = {t: v / sqrt_norm for t, v in query_vec.items()}

        # Cosine similarity (dot product of pre-normalised vectors)
        scores: List[Tuple[float, str]] = []
        for idx, doc_vec in enumerate(self._tfidf_vectors):
            sim = sum(query_vec.get(t, 0.0) * w for t, w in doc_vec.items())
            if sim > 0.05:
                scores.append((sim, self._tfidf_concept_ids[idx]))

        scores.sort(key=lambda x: x[0], reverse=True)
        return [cid for _, cid in scores[:top_k]]



    async def _execute(self, stmt: str, params: dict | None = None):
        """Run a KuzuDB query off the event loop, serialised via lock (KuzuDB is not thread-safe)."""
        async with self._lock:
            return await asyncio.to_thread(self._conn.execute, stmt, params or {})

    async def expand(self, seed_nodes: List[str], hops: int = 1) -> KGHits:
        expanded_nodes: List[KGExpandedNode] = []
        paths: List[KGPath] = []

        if not seed_nodes:
            return KGHits(seed_nodes=[], expanded_nodes=[], paths=[])

        try:
            for seed in seed_nodes:
                result = await self._execute(
                    "MATCH (a:Concept)-[e:Edge]->(b:Concept) "
                    "WHERE a.id = $seed RETURN b.id, e.relation, b.level",
                    {"seed": seed},
                )
                while result.has_next():  # type: ignore[union-attr]
                    row: list = result.get_next()  # type: ignore[union-attr]
                    expanded_nodes.append(KGExpandedNode(
                        id=row[0], type=row[1],
                        properties={"relation": row[1], "level": row[2] or "B1"},
                    ))
                    paths.append(KGPath(nodes=[seed, row[0]], edges=[row[1]]))
        except Exception as exc:
            if self._is_corruption_error(exc) and self._recover_and_retry("expand"):
                return await self.expand(seed_nodes=seed_nodes, hops=hops)
            return KGHits(seed_nodes=seed_nodes, expanded_nodes=[], paths=[])

        return KGHits(seed_nodes=seed_nodes, expanded_nodes=expanded_nodes, paths=paths)

    async def expand_best_first(
        self,
        seed_nodes: List[str],
        learner_level: str = "B1",
        max_hops: int = 2,
        max_nodes: int = 10,
    ) -> KGHits:
        """
        Level-aware best-first graph expansion (paper Alg. 4).

        Uses PedWeight priority: concepts at the learner's level get
        highest priority (1.0), ±1 level get 0.7, others 0.3.

        Phase 2 optimisation: results are cached in Redis keyed by
        sha1(sorted(seed_nodes) + learner_level + max_hops + max_nodes)
        with a 30-minute TTL to skip redundant BFS traversals.
        """
        import heapq
        import hashlib
        import json as _json

        if not seed_nodes:
            return KGHits(seed_nodes=[], expanded_nodes=[], paths=[])

        # ── Phase 2: Redis subgraph result cache ──────────────────────────
        _cache_key = (
            "kg:subgraph:"
            + hashlib.sha1(
                f"{sorted(seed_nodes)}:{learner_level}:{max_hops}:{max_nodes}".encode()
            ).hexdigest()
        )
        try:
            from api.core.redis_client import RedisClient
            _redis = await RedisClient.get_instance()
            _cached = await _redis.get(_cache_key)
            if _cached:
                _data = _json.loads(_cached)
                return KGHits(
                    seed_nodes=_data["seeds"],
                    expanded_nodes=[KGExpandedNode(**n) for n in _data["nodes"]],
                    paths=[KGPath(**p) for p in _data["paths"]],
                )
        except Exception:
            _redis = None
        # ─────────────────────────────────────────────────────────────────

        CEFR_ORD = {"A1": 1, "A2": 2, "B1": 3, "B2": 4, "C1": 5, "C2": 6}
        learner_ord = CEFR_ORD.get(learner_level, 3)

        def ped_weight(neighbor_level: str) -> float:
            n_ord = CEFR_ORD.get(neighbor_level, 3)
            diff = abs(n_ord - learner_ord)
            if diff == 0:
                return 1.0
            elif diff == 1:
                return 0.7
            return 0.3

        expanded_nodes: List[KGExpandedNode] = []
        paths: List[KGPath] = []
        visited: set = set(seed_nodes)

        # Priority queue: (-weight, hop_depth, concept_id, parent_id, relation)
        # Negate weight because heapq is a min-heap
        frontier: list = []
        for s in seed_nodes:
            heapq.heappush(frontier, (-1.0, 0, s, None, None))

        try:
            while frontier and len(expanded_nodes) < max_nodes:
                neg_w, depth, cid, parent, rel = heapq.heappop(frontier)

                if depth > 0:  # don't add seeds themselves as expanded
                    expanded_nodes.append(KGExpandedNode(
                        id=cid, type=rel or "related_to",
                        properties={"relation": rel or "related_to", "depth": depth},
                    ))
                    if parent:
                        paths.append(KGPath(nodes=[parent, cid], edges=[rel or "related_to"]))

                if depth >= max_hops:
                    continue

                # Expand neighbors
                result = await self._execute(
                    "MATCH (a:Concept)-[e:Edge]->(b:Concept) "
                    "WHERE a.id = $cid RETURN b.id, e.relation, b.level",
                    {"cid": cid},
                )
                while result.has_next():  # type: ignore[union-attr]
                    row = result.get_next()  # type: ignore[union-attr]
                    neighbor_id, edge_rel, neighbor_level = row[0], row[1], row[2] or "B1"
                    if neighbor_id not in visited:
                        visited.add(neighbor_id)
                        w = ped_weight(neighbor_level)
                        heapq.heappush(frontier, (-w, depth + 1, neighbor_id, cid, edge_rel))
        except Exception as e:
            if self._is_corruption_error(e) and self._recover_and_retry("expand_best_first"):
                return await self.expand_best_first(
                    seed_nodes=seed_nodes,
                    learner_level=learner_level,
                    max_hops=max_hops,
                    max_nodes=max_nodes,
                )
            logger.warning(f"[KG] expand_best_first error: {e}")

        hits = KGHits(seed_nodes=seed_nodes, expanded_nodes=expanded_nodes, paths=paths)

        # ── Phase 2: Store result in Redis (TTL 30 min) ───────────────────
        try:
            if _redis is not None:
                _payload = _json.dumps({
                    "seeds": seed_nodes,
                    "nodes": [
                        {"id": n.id, "type": n.type, "properties": n.properties}
                        for n in expanded_nodes
                    ],
                    "paths": [
                        {"nodes": p.nodes, "edges": p.edges}
                        for p in paths
                    ],
                })
                await _redis.setex(_cache_key, 1800, _payload)
        except Exception as _exc:
            logger.debug("[kg_service_v3] ignored: %s", _exc)
            pass
        # ─────────────────────────────────────────────────────────────────

        return hits



    async def record_interaction(
        self,
        user_id: str,
        session_id: str,
        linked_concepts: List[str],
        error_types: List[str],
    ) -> None:
        if not user_id or not linked_concepts:
            return None
        if not settings.KUZU_USER_MASTERY_WRITES_ENABLED:
            return None

        # Ensure user node exists
        try:
            await self._execute("MERGE (u:User {id: $id})", {"id": user_id})
        except Exception:
            return None

        for concept_id in linked_concepts:
            # Simple mastery update: decrease on errors, increase otherwise
            delta = -0.05 if error_types else 0.03
            try:
                await self._execute(
                    "MATCH (u:User), (c:Concept) "
                    "WHERE u.id = $uid AND c.id = $cid "
                    "MERGE (u)-[m:Mastery]->(c) "
                    "ON CREATE SET m.score = $score "
                    "ON MATCH SET m.score = min(1.0, max(0.0, m.score + $delta))",
                    {"uid": user_id, "cid": concept_id, "score": 0.5, "delta": delta},
                )
            except Exception as _exc:
                logger.debug("[kg_service_v3] ignored: %s", _exc)
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
            result = await self._execute(
                "MATCH (u:User)-[m:Mastery]->(c:Concept) "
                "WHERE u.id = $uid RETURN c.id, m.score",
                {"uid": user_id},
            )
            while result.has_next():  # type: ignore[union-attr]
                row: list = result.get_next()  # type: ignore[union-attr]
                mastery[row[0]] = row[1]
        except Exception as _exc:
            logger.debug("[kg_service_v3] ignored: %s", _exc)
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
                        
        except Exception as _exc:
            logger.debug("[kg_service_v3] ignored: %s", _exc)
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
            result = await self._execute(
                "MATCH (a:Concept)-[e:Edge]->(b:Concept) "
                "WHERE b.id = $cid AND e.relation = 'prerequisite_of' "
                "RETURN a.id",
                {"cid": concept_id},
            )
            while result.has_next():  # type: ignore[union-attr]
                row: list = result.get_next()  # type: ignore[union-attr]
                prerequisites.append(row[0])
        except Exception as _exc:
            logger.debug("[kg_service_v3] ignored: %s", _exc)
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
            result = await self._execute(
                "MATCH (a:Concept)-[e:Edge]->(b:Concept) "
                "WHERE a.id = $cid AND e.relation = 'prerequisite_of' "
                "RETURN b.id",
                {"cid": concept_id},
            )
            while result.has_next():  # type: ignore[union-attr]
                row: list = result.get_next()  # type: ignore[union-attr]
                next_concepts.append(row[0])
        except Exception as _exc:
            logger.debug("[kg_service_v3] ignored: %s", _exc)
            pass

        return next_concepts

    def get_concept_count(self) -> int:
        """Get total number of concepts in the graph."""
        try:
            result = self._conn.execute("MATCH (c:Concept) RETURN count(c)")
            if result.has_next():  # type: ignore[union-attr]
                return result.get_next()[0]  # type: ignore[union-attr]
        except Exception as _exc:
            logger.debug("[kg_service_v3] ignored: %s", _exc)
            pass
        return 0

    def query_concepts(self, query: str, learner_level: str = "B1", top_k: int = 8) -> List[Dict[str, Any]]:
        """Lexical + level-aware top-K concept retrieval for prompt grounding."""
        normalized = str(query or "").strip().lower()
        if not normalized or top_k <= 0:
            return []

        tokens = [tok for tok in re.findall(r"[a-z0-9_]+", normalized) if len(tok) >= 2]
        if not tokens:
            return []

        concepts = self.get_concepts()
        if not concepts:
            return []

        CEFR_ORD = {"A1": 1, "A2": 2, "B1": 3, "B2": 4, "C1": 5, "C2": 6}
        learner_ord = CEFR_ORD.get(str(learner_level or "B1").upper(), 3)

        scored: List[Tuple[float, str, Dict[str, str]]] = []
        token_set = set(tokens)
        for concept_id, meta in concepts.items():
            title = str(meta.get("title") or "")
            keywords = str(meta.get("keywords") or "")
            haystack = f"{title} {keywords}".lower()
            if not haystack:
                continue

            overlap = sum(1 for tok in token_set if tok in haystack)
            if overlap <= 0:
                continue

            level = str(meta.get("level") or "B1").upper()
            diff = abs(CEFR_ORD.get(level, 3) - learner_ord)
            level_boost = 1.0 if diff == 0 else (0.8 if diff == 1 else 0.6)
            score = (overlap / max(len(token_set), 1)) * level_boost
            scored.append((score, concept_id, meta))

        scored.sort(key=lambda item: item[0], reverse=True)
        return [
            {
                "id": concept_id,
                "title": meta.get("title", concept_id),
                "keywords": meta.get("keywords", ""),
                "level": meta.get("level", "B1"),
                "score": round(float(score), 4),
            }
            for score, concept_id, meta in scored[:top_k]
        ]
