import json

import pytest

from api.services.kg_data_loader import (
    RuntimeKnowledgeIsolationError,
    sync_knowledge_files,
    validate_runtime_knowledge_payload,
)
from api.services.kg_service_v3 import KnowledgeGraphServiceV3


def test_runtime_payload_rejects_benchmark_concept_namespace():
    payload = {
        "concepts": [{"id": "concept:benchmark.lobban", "title": "Lobban"}],
        "edges": [],
    }

    with pytest.raises(ValueError, match="benchmark"):
        validate_runtime_knowledge_payload(payload, source_path="runtime.json")


def test_runtime_payload_rejects_benchmark_edge_namespace():
    payload = {
        "concepts": [{"id": "concept:greeting", "title": "Greeting"}],
        "edges": [
            {
                "from": "concept:greeting",
                "to": "concept:benchmark.tell",
                "relation": "related_to",
            }
        ],
    }

    with pytest.raises(ValueError, match="benchmark"):
        validate_runtime_knowledge_payload(payload, source_path="runtime.json")


def test_runtime_sync_ignores_unallowlisted_json(tmp_path, monkeypatch):
    kg_dir = tmp_path / "kg"
    kg_dir.mkdir()
    (kg_dir / "seed_graph.json").write_text(
        json.dumps({"concepts": [{"id": "concept:greeting"}], "edges": []})
    )
    (kg_dir / "benchmark_entities.json").write_text(
        json.dumps({"concepts": [{"id": "concept:benchmark.tell"}], "edges": []})
    )
    captured_paths = []
    service = KnowledgeGraphServiceV3.__new__(KnowledgeGraphServiceV3)
    service._db_path = str(tmp_path / "runtime.kuzu")
    service._conn = object()
    service._allow_benchmark = False
    monkeypatch.setattr(service, "_kg_data_dir", lambda: str(kg_dir))
    monkeypatch.setattr(service, "_extended_knowledge_path", lambda: str(tmp_path / "missing.json"))
    monkeypatch.setattr(
        "api.services.kg_service_v3.sync_knowledge_files",
        lambda _connection, paths, _metadata, **_kwargs: captured_paths.extend(paths),
    )

    service._sync_external_knowledge()

    assert captured_paths == [str(kg_dir / "seed_graph.json")]


def test_runtime_kg_validator_rejects_existing_benchmark_nodes():
    class Result:
        def has_next(self):
            return True

        def get_next(self):
            return [1]

    class Connection:
        def execute(self, query):
            assert "concept:benchmark." in query
            return Result()

    service = KnowledgeGraphServiceV3.__new__(KnowledgeGraphServiceV3)
    service._conn = Connection()
    service._allow_benchmark = False

    with pytest.raises(RuntimeError, match="benchmark"):
        service._assert_runtime_namespace()


def test_sync_propagates_runtime_isolation_error(tmp_path):
    source = tmp_path / "runtime.json"
    source.write_text(
        json.dumps({"concepts": [{"id": "concept:benchmark.tell"}], "edges": []})
    )

    with pytest.raises(RuntimeKnowledgeIsolationError):
        sync_knowledge_files(
            object(),
            [str(source)],
            str(tmp_path / "metadata.json"),
            forbidden_concept_prefixes=("concept:benchmark.",),
        )


@pytest.mark.parametrize("environment", ["production", "Production"])
def test_production_rejects_benchmark_mode(monkeypatch, tmp_path, environment):
    import api.services.kg_service_v3 as kg_module

    monkeypatch.setattr(kg_module.settings, "ENVIRONMENT", environment)
    monkeypatch.setattr(kg_module.settings, "KUZU_DB_PATH", str(tmp_path / "runtime.kuzu"))
    monkeypatch.setenv("TRACECAG_KG_ALLOW_BENCHMARK", "true")

    with pytest.raises(RuntimeError, match="forbidden in production"):
        KnowledgeGraphServiceV3()


def test_invalid_configuration_never_triggers_recovery():
    service = KnowledgeGraphServiceV3.__new__(KnowledgeGraphServiceV3)
    service._strict_snapshot = False
    service._recovery_attempted = False
    called = False

    def hard_rebuild(*_args, **_kwargs):
        nonlocal called
        called = True

    service._hard_rebuild_db = hard_rebuild

    assert service._recover_and_retry("test", RuntimeError("Invalid configuration")) is False
    assert called is False
