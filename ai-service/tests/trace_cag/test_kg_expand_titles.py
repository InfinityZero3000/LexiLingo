import asyncio

import kuzu
import pytest

from api.services import kg_service_v3 as kg_module


@pytest.fixture()
def kg(monkeypatch, tmp_path):
    db_path = tmp_path / "kg.db"
    db = kuzu.Database(str(db_path))
    conn = kuzu.Connection(db)
    conn.execute(
        "CREATE NODE TABLE Concept(id STRING, title STRING, keywords STRING, level STRING DEFAULT 'B1', PRIMARY KEY(id))"
    )
    conn.execute("CREATE REL TABLE Edge(FROM Concept TO Concept, relation STRING)")
    conn.execute(
        "CREATE (:Concept {id: 'concept:a', title: 'Present Perfect', keywords: 'have has been', level: 'B1'})"
    )
    conn.execute(
        "CREATE (:Concept {id: 'concept:b', title: 'Past Simple', keywords: 'yesterday ago', level: 'B1'})"
    )
    conn.execute(
        "MATCH (a:Concept), (b:Concept) WHERE a.id = 'concept:a' AND b.id = 'concept:b' "
        "CREATE (a)-[:Edge {relation: 'contrasts_with'}]->(b)"
    )

    service = kg_module.KnowledgeGraphServiceV3.__new__(kg_module.KnowledgeGraphServiceV3)
    service._conn = conn
    service._db = db
    service._lock = asyncio.Lock()
    service._recovery_attempted = True
    monkeypatch.setattr(
        kg_module.KnowledgeGraphServiceV3,
        "_recover_and_retry",
        lambda *_a, **_k: False,
    )
    return service


def test_expanded_nodes_carry_title_and_keywords(kg, monkeypatch):
    # Redis is optional here; force the miss path so the test never needs a server.
    monkeypatch.setitem(
        __import__("sys").modules,
        "api.core.redis_client",
        type("_M", (), {"RedisClient": type("_R", (), {"get_instance": staticmethod(lambda: (_ for _ in ()).throw(RuntimeError("no redis")))})}),
    )

    hits = asyncio.run(
        kg.expand_best_first(seed_nodes=["concept:a"], learner_level="B1", max_hops=1, max_nodes=5)
    )

    assert [n.id for n in hits.expanded_nodes] == ["concept:b"]
    props = hits.expanded_nodes[0].properties
    assert props["title"] == "Past Simple"
    assert props["keywords"] == "yesterday ago"
    assert props["relation"] == "contrasts_with"
