"""Load versioned knowledge-graph JSON files into KuzuDB."""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import logging
import os
from typing import Any, Iterable, Iterator, Mapping, TypeVar

logger = logging.getLogger(__name__)
_T = TypeVar("_T")
_MERGE_BATCH_SIZE = 500


class RuntimeKnowledgeIsolationError(ValueError):
    pass


def validate_runtime_knowledge_payload(
    payload: Mapping[str, Any],
    *,
    source_path: str = "<payload>",
) -> None:
    """Reject benchmark-only concepts at the production ingestion boundary."""
    for concept in payload.get("concepts") or []:
        concept_id = str(concept.get("id") or "") if isinstance(concept, dict) else ""
        if concept_id.startswith("concept:benchmark."):
            raise RuntimeKnowledgeIsolationError(
                f"Forbidden concept namespace in production KG source: {concept_id} ({source_path})"
            )
    for edge in payload.get("edges") or []:
        if not isinstance(edge, dict):
            continue
        for endpoint in (str(edge.get("from") or ""), str(edge.get("to") or "")):
            if endpoint.startswith("concept:benchmark."):
                raise RuntimeKnowledgeIsolationError(
                    f"Forbidden concept namespace in production KG source: {endpoint} ({source_path})"
                )


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


def _batches(items: list[_T], size: int = _MERGE_BATCH_SIZE) -> Iterator[list[_T]]:
    for start in range(0, len(items), size):
        yield items[start : start + size]


def _query_count(result: Any) -> int:
    if result is None or not result.has_next():
        return 0
    return int(result.get_next()[0])


def merge_knowledge_payload(connection: Any, payload: Mapping[str, Any]) -> MergeStats:
    """MERGE valid concepts and edges, preserving per-record fault tolerance."""
    concept_rows: list[dict[str, str]] = []
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
            concept_rows.append(
                {"id": node_id, "title": title, "keywords": keywords, "level": level}
            )

    concepts_inserted = 0
    for batch in _batches(concept_rows):
        try:
            connection.execute(
                "UNWIND $rows AS row "
                "MERGE (c:Concept {id: row.id}) "
                "ON CREATE SET c.title = row.title, c.keywords = row.keywords, c.level = row.level "
                "ON MATCH SET c.title = row.title, c.keywords = row.keywords, c.level = row.level",
                {"rows": batch},
            )
            concepts_inserted += len(batch)
        except Exception as exc:
            logger.warning(
                "[kg_data_loader] concept batch merge failed; retrying records: %s",
                type(exc).__name__,
            )
            for row in batch:
                try:
                    connection.execute(
                        "MERGE (c:Concept {id: $id}) "
                        "ON CREATE SET c.title = $title, c.keywords = $keywords, c.level = $level "
                        "ON MATCH SET c.title = $title, c.keywords = $keywords, c.level = $level",
                        row,
                    )
                    concepts_inserted += 1
                except Exception as record_exc:
                    logger.debug(
                        "[kg_data_loader] concept merge failed: %s", record_exc
                    )

    edge_rows: list[dict[str, str]] = []
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
            edge_rows.append({"from": from_id, "to": to_id, "relation": relation})

    edges_inserted = 0
    for batch in _batches(edge_rows):
        try:
            result = connection.execute(
                "UNWIND $rows AS row "
                "MATCH (a:Concept), (b:Concept) "
                "WHERE a.id = row.from AND b.id = row.to "
                "MERGE (a)-[:Edge {relation: row.relation}]->(b) "
                "RETURN count(*)",
                {"rows": batch},
            )
            matched = _query_count(result)
            if matched != len(batch):
                raise RuntimeError("edge endpoints missing")
            edges_inserted += matched
        except Exception as exc:
            logger.warning(
                "[kg_data_loader] edge batch merge failed; retrying records: %s",
                type(exc).__name__,
            )
            for row in batch:
                try:
                    result = connection.execute(
                        "MATCH (a:Concept), (b:Concept) "
                        "WHERE a.id = $from AND b.id = $to "
                        "MERGE (a)-[:Edge {relation: $relation}]->(b) "
                        "RETURN count(*)",
                        row,
                    )
                    edges_inserted += _query_count(result)
                except Exception as record_exc:
                    logger.debug("[kg_data_loader] edge merge failed: %s", record_exc)

    return MergeStats(concepts=concepts_inserted, edges=edges_inserted)


def sync_knowledge_files(
    connection: Any,
    paths: Iterable[str],
    metadata_path: str,
    *,
    forbidden_concept_prefixes: tuple[str, ...] = (),
) -> MergeStats:
    """Sync changed JSON files and persist hashes after successful graph writes."""
    metadata: dict[str, str] = {}
    if os.path.exists(metadata_path):
        try:
            loaded = load_json_object(metadata_path)
            metadata = {str(key): str(value) for key, value in loaded.items()}
        except RuntimeKnowledgeIsolationError:
            raise
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
            payload = load_json_object(path)
            if forbidden_concept_prefixes:
                validate_runtime_knowledge_payload(payload, source_path=path)
            pending.append((path, current_hash, payload))
        except RuntimeKnowledgeIsolationError:
            raise
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
        expected_concepts = sum(
            1
            for concept in payload.get("concepts", [])
            if isinstance(concept, dict) and str(concept.get("id") or "").strip()
        )
        expected_edges = sum(
            1
            for edge in payload.get("edges", [])
            if isinstance(edge, dict)
            and str(edge.get("from") or "").strip()
            and str(edge.get("to") or "").strip()
        )
        if stats.concepts or stats.edges:
            logger.info(
                "[KG] Synced %s: concepts=%d edges=%d",
                os.path.basename(path),
                stats.concepts,
                stats.edges,
            )
        total += stats
        if stats.concepts == expected_concepts and stats.edges == expected_edges:
            updated_metadata[path] = current_hash
        else:
            logger.warning("[KG] Sync incomplete for %s; hash not persisted", path)

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
