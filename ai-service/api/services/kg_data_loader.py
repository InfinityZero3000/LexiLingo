"""Load versioned knowledge-graph JSON files into KuzuDB."""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import logging
import os
from typing import Any, Iterable, Mapping

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class MergeStats:
    concepts: int = 0
    edges: int = 0

    def __add__(self, other: "MergeStats") -> "MergeStats":
        return MergeStats(
            concepts=self.concepts + other.concepts,
            edges=self.edges + other.edges,
        )


def load_json_object(path: str) -> dict[str, Any]:
    with open(path, "r", encoding="utf-8") as file:
        payload = json.load(file)
    if not isinstance(payload, dict):
        raise ValueError(f"Knowledge graph payload must be an object: {path}")
    return payload


def file_md5(path: str) -> str:
    hasher = hashlib.md5(usedforsecurity=False)
    with open(path, "rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def merge_knowledge_payload(connection: Any, payload: Mapping[str, Any]) -> MergeStats:
    """MERGE valid concepts and edges, preserving per-record fault tolerance."""
    concepts_inserted = 0
    concepts = payload.get("concepts")
    if isinstance(concepts, list):
        for concept in concepts:
            if not isinstance(concept, dict):
                continue
            node_id = str(concept.get("id") or "").strip()
            if not node_id:
                continue
            title = str(concept.get("title") or node_id).strip()
            keywords = str(concept.get("keywords") or "").strip()
            level = str(concept.get("level") or "B1").strip() or "B1"
            try:
                connection.execute(
                    "MERGE (c:Concept {id: $id}) "
                    "ON CREATE SET c.title = $title, c.keywords = $keywords, c.level = $level "
                    "ON MATCH SET c.title = $title, c.keywords = $keywords, c.level = $level",
                    {
                        "id": node_id,
                        "title": title,
                        "keywords": keywords,
                        "level": level,
                    },
                )
                concepts_inserted += 1
            except Exception as exc:
                logger.debug("[kg_data_loader] concept merge failed: %s", exc)

    edges_inserted = 0
    edges = payload.get("edges")
    if isinstance(edges, list):
        for edge in edges:
            if not isinstance(edge, dict):
                continue
            from_id = str(edge.get("from") or "").strip()
            to_id = str(edge.get("to") or "").strip()
            relation = str(edge.get("relation") or "related_to").strip() or "related_to"
            if not from_id or not to_id:
                continue
            try:
                connection.execute(
                    "MATCH (a:Concept), (b:Concept) WHERE a.id = $from AND b.id = $to "
                    "MERGE (a)-[:Edge {relation: $relation}]->(b)",
                    {"from": from_id, "to": to_id, "relation": relation},
                )
                edges_inserted += 1
            except Exception as exc:
                logger.debug("[kg_data_loader] edge merge failed: %s", exc)

    return MergeStats(concepts=concepts_inserted, edges=edges_inserted)


def sync_knowledge_files(
    connection: Any,
    paths: Iterable[str],
    metadata_path: str,
) -> MergeStats:
    """Sync changed JSON files and persist hashes after successful graph writes."""
    metadata: dict[str, str] = {}
    if os.path.exists(metadata_path):
        try:
            loaded = load_json_object(metadata_path)
            metadata = {str(key): str(value) for key, value in loaded.items()}
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            logger.warning("[KG] Failed loading sync metadata %s: %s", metadata_path, exc)

    pending: list[tuple[str, str, dict[str, Any]]] = []
    for path in paths:
        if not os.path.isfile(path):
            continue
        try:
            current_hash = file_md5(path)
            if metadata.get(path) == current_hash:
                continue
            pending.append((path, current_hash, load_json_object(path)))
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            logger.warning("[KG] Failed loading %s: %s", path, exc)

    if not pending:
        logger.info("[KG] All external knowledge files are up-to-date (skipped sync)")
        return MergeStats()

    total = MergeStats()
    updated_metadata = dict(metadata)
    for path, current_hash, payload in pending:
        if not isinstance(payload.get("concepts"), list):
            continue
        stats = merge_knowledge_payload(connection, payload)
        if stats.concepts or stats.edges:
            logger.info(
                "[KG] Synced %s: concepts=%d edges=%d",
                os.path.basename(path),
                stats.concepts,
                stats.edges,
            )
        total += stats
        updated_metadata[path] = current_hash

    if total.concepts or total.edges:
        logger.info(
            "[KG] Total synced: concepts=%d edges=%d",
            total.concepts,
            total.edges,
        )
        try:
            with open(metadata_path, "w", encoding="utf-8") as file:
                json.dump(updated_metadata, file, indent=2)
        except OSError as exc:
            logger.warning("[KG] Failed to write synced files metadata cache: %s", exc)

    return total
