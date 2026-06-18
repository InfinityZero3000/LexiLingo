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
        record_id = parameters.get("id") or parameters.get("from")
        if record_id in self.failing_ids:
            raise RuntimeError("simulated merge failure")
        self.calls.append((query, parameters))


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
        "from": "greeting",
        "to": "response",
        "relation": "related_to",
    }


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
