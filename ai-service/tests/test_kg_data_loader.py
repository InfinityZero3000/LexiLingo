import json

from api.services.kg_data_loader import (
    MergeStats,
    merge_knowledge_payload,
    sync_knowledge_files,
)


class FakeConnection:
    def __init__(self, failing_ids=None):
        self.calls = []
        self.failing_ids = set(failing_ids or [])

    def execute(self, query, parameters):
        rows = parameters.get("rows")
        if rows and any(
            (row.get("id") or row.get("from")) in self.failing_ids for row in rows
        ):
            raise RuntimeError("simulated batch merge failure")
        record_id = parameters.get("id") or parameters.get("from")
        if record_id in self.failing_ids:
            raise RuntimeError("simulated merge failure")
        self.calls.append((query, parameters))
        if "RETURN count(*)" in query:
            count = len(rows) if rows else 1
            return FakeCountResult(count)


class FakeCountResult:
    def __init__(self, count):
        self.count = count
        self.read = False

    def has_next(self):
        return not self.read

    def get_next(self):
        self.read = True
        return [self.count]


def test_merge_payload_preserves_defaults_and_skips_invalid_records():
    connection = FakeConnection(failing_ids={"broken"})
    payload = {
        "concepts": [
            {"id": "greeting"},
            {"id": "broken", "title": "Broken"},
            {"title": "Missing ID"},
            "invalid",
        ],
        "edges": [
            {"from": "greeting", "to": "response"},
            {"from": "", "to": "response"},
            "invalid",
        ],
    }

    stats = merge_knowledge_payload(connection, payload)

    assert stats == MergeStats(concepts=1, edges=1)
    assert connection.calls[0][1] == {
        "id": "greeting",
        "title": "greeting",
        "keywords": "",
        "level": "B1",
    }
    assert connection.calls[1][1] == {
        "rows": [
            {
                "from": "greeting",
                "to": "response",
                "relation": "related_to",
            }
        ]
    }


def test_merge_batches_concepts_and_edges_with_expected_parameters():
    connection = FakeConnection()
    payload = {
        "concepts": [
            {"id": "a", "title": "A", "level": "A1"},
            {"id": "b", "keywords": "bee"},
        ],
        "edges": [{"from": "a", "to": "b", "relation": "requires"}],
    }

    stats = merge_knowledge_payload(connection, payload)

    assert stats == MergeStats(concepts=2, edges=1)
    assert len(connection.calls) == 2
    assert "UNWIND $rows" in connection.calls[0][0]
    assert connection.calls[0][1]["rows"] == [
        {"id": "a", "title": "A", "keywords": "", "level": "A1"},
        {"id": "b", "title": "b", "keywords": "bee", "level": "B1"},
    ]
    assert "UNWIND $rows" in connection.calls[1][0]
    assert connection.calls[1][1]["rows"] == [
        {"from": "a", "to": "b", "relation": "requires"}
    ]


def test_merge_chunks_more_than_five_hundred_records():
    connection = FakeConnection()
    payload = {"concepts": [{"id": f"c-{index}"} for index in range(1_001)]}

    stats = merge_knowledge_payload(connection, payload)

    assert stats == MergeStats(concepts=1_001, edges=0)
    assert len(connection.calls) == 3
    assert [len(call[1]["rows"]) for call in connection.calls] == [500, 500, 1]


def test_failed_batch_falls_back_per_record_and_preserves_partial_stats():
    connection = FakeConnection(failing_ids={"broken-concept", "broken-edge"})
    payload = {
        "concepts": [
            {"id": "good-concept"},
            {"id": "broken-concept"},
        ],
        "edges": [
            {"from": "good-edge", "to": "target"},
            {"from": "broken-edge", "to": "target"},
        ],
    }

    stats = merge_knowledge_payload(connection, payload)

    assert stats == MergeStats(concepts=1, edges=1)
    assert len(connection.calls) == 2
    assert connection.calls[0][1]["id"] == "good-concept"
    assert connection.calls[1][1]["from"] == "good-edge"


def test_sync_only_merges_changed_files_and_persists_hashes(tmp_path):
    knowledge_path = tmp_path / "travel.json"
    metadata_path = tmp_path / "synced.json"
    knowledge_path.write_text(
        json.dumps(
            {
                "concepts": [
                    {
                        "id": "travel",
                        "title": "Travel",
                        "keywords": "airport",
                        "level": "A2",
                    }
                ],
                "edges": [],
            }
        ),
        encoding="utf-8",
    )
    connection = FakeConnection()

    first = sync_knowledge_files(
        connection,
        [str(knowledge_path)],
        str(metadata_path),
    )
    call_count = len(connection.calls)
    second = sync_knowledge_files(
        connection,
        [str(knowledge_path)],
        str(metadata_path),
    )

    assert first == MergeStats(concepts=1, edges=0)
    assert second == MergeStats()
    assert len(connection.calls) == call_count
    assert str(knowledge_path) in json.loads(metadata_path.read_text(encoding="utf-8"))


def test_missing_edge_endpoint_does_not_persist_hash_and_retries_later(tmp_path):
    class CountResult:
        def __init__(self, count):
            self.count = count

        def has_next(self):
            return True

        def get_next(self):
            return [self.count]

    class EndpointConnection:
        available = False

        def execute(self, query, _parameters):
            if "RETURN count(*)" in query:
                return CountResult(1 if self.available else 0)
            return None

    knowledge = tmp_path / "graph.json"
    metadata = tmp_path / "hashes.json"
    knowledge.write_text(
        json.dumps(
            {
                "concepts": [{"id": "a"}],
                "edges": [{"from": "a", "to": "later"}],
            }
        )
    )
    connection = EndpointConnection()

    first = sync_knowledge_files(connection, [str(knowledge)], str(metadata))
    persisted = json.loads(metadata.read_text())
    connection.available = True
    second = sync_knowledge_files(connection, [str(knowledge)], str(metadata))

    assert first == MergeStats(concepts=1, edges=0)
    assert str(knowledge) not in persisted
    assert second == MergeStats(concepts=1, edges=1)
    assert str(knowledge) in json.loads(metadata.read_text())
