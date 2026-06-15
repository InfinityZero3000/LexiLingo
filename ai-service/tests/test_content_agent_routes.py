from types import SimpleNamespace

from api.routes import content_agent as content_agent_routes
from api.services.content_agent.service import ContentAgentService
from api.services.content_agent.store import ContentAgentStore
from fastapi import FastAPI
from fastapi.testclient import TestClient

TOKEN = "test-content-agent-token"


def _payload(count=8):
    return {
        "source_name": "admin_upload",
        "records": [
            {
                "record_id": f"upload:{index}",
                "word": f"word{index:02d}",
                "part_of_speech": "noun",
                "declared_cefr": "A1",
                "declared_topic": "daily_life",
            }
            for index in range(count)
        ],
    }


def _client(
    monkeypatch,
    *,
    clock=None,
    ttl_seconds=60,
    max_records=20,
    max_batch=10,
    token=TOKEN,
):
    store = ContentAgentStore(
        ttl_seconds=ttl_seconds,
        max_records=max_records,
        clock=clock,
    )
    service = ContentAgentService(store=store)
    settings = SimpleNamespace(
        CONTENT_AGENT_SERVICE_TOKEN=token,
        CONTENT_AGENT_MAX_BATCH_RECORDS=max_batch,
    )
    monkeypatch.setattr(content_agent_routes, "get_settings", lambda: settings)

    app = FastAPI()
    app.include_router(content_agent_routes.router)
    app.dependency_overrides[content_agent_routes.get_content_agent_service] = lambda: service
    return TestClient(app)


def test_internal_routes_require_correct_service_token(monkeypatch):
    client = _client(monkeypatch)
    path = "/api/v1/internal/content-agent/jobs/job-1/records"

    assert client.post(path, json=_payload()).status_code == 403
    assert client.post(
        path,
        json=_payload(),
        headers={"X-Content-Agent-Token": "wrong"},
    ).status_code == 403


def test_internal_routes_fail_closed_when_service_token_is_unconfigured(monkeypatch):
    client = _client(monkeypatch, token="")

    response = client.post(
        "/api/v1/internal/content-agent/jobs/job-1/records",
        json=_payload(),
        headers={"X-Content-Agent-Token": TOKEN},
    )

    assert response.status_code == 503


def test_record_generate_delete_lifecycle(monkeypatch):
    client = _client(monkeypatch)
    headers = {"X-Content-Agent-Token": TOKEN}
    base = "/api/v1/internal/content-agent/jobs/job-1"

    ingested = client.post(f"{base}/records", json=_payload(), headers=headers)
    assert ingested.status_code == 202
    assert ingested.json()["stored_records"] == 8

    generated = client.post(
        f"{base}/generate",
        json={
            "levels": ["A1"],
            "units_per_course": 1,
            "lessons_per_unit": 1,
            "words_per_lesson": 8,
        },
        headers=headers,
    )
    assert generated.status_code == 200
    artifact = generated.json()
    assert artifact["schema_version"] == 2
    assert [course["level"] for course in artifact["courses"]] == ["A1"]
    exercises = artifact["courses"][0]["units"][0]["lessons"][0]["exercises"]
    assert len(exercises) == 10

    assert client.delete(base, headers=headers).status_code == 204
    assert client.post(
        f"{base}/generate",
        json={"levels": ["A1"], "units_per_course": 1, "lessons_per_unit": 1},
        headers=headers,
    ).status_code == 404


def test_generate_fails_closed_without_an_approved_existing_cefr_snapshot(monkeypatch):
    client = _client(monkeypatch)
    headers = {"X-Content-Agent-Token": TOKEN}
    response = client.post(
        "/api/v1/internal/content-agent/jobs/existing-only/generate",
        json={
            "levels": ["A1"],
            "sources": ["existing_cefr"],
            "upload_id": None,
            "title_focus": None,
            "topic_focus": [],
            "units_per_course": 1,
            "lessons_per_unit": 1,
            "words_per_lesson": 8,
            "exercises_per_lesson": 10,
            "confidence_threshold": 0.7,
            "revision": False,
            "apply_on_success": False,
        },
        headers=headers,
    )

    assert response.status_code == 404


def test_direct_existing_cefr_ingest_is_rejected(monkeypatch):
    client = _client(monkeypatch)
    headers = {"X-Content-Agent-Token": TOKEN}
    payload = _payload()
    payload["source_name"] = "existing_cefr"

    response = client.post(
        "/api/v1/internal/content-agent/jobs/alias-bypass/records",
        json=payload,
        headers=headers,
    )

    assert response.status_code == 422
    assert "snapshot" in response.json()["detail"].lower()


def test_generation_ignores_ingested_sources_not_selected_by_request(monkeypatch):
    client = _client(monkeypatch)
    headers = {"X-Content-Agent-Token": TOKEN}
    base = "/api/v1/internal/content-agent/jobs/source-filter"
    assert client.post(f"{base}/records", json=_payload(), headers=headers).status_code == 202
    oewn_payload = _payload()
    oewn_payload["source_name"] = "oewn"
    assert client.post(
        f"{base}/records",
        json=oewn_payload,
        headers=headers,
    ).status_code == 202

    response = client.post(
        f"{base}/generate",
        json={
            "levels": ["A1"],
            "sources": ["admin_upload"],
            "units_per_course": 1,
            "lessons_per_unit": 1,
            "words_per_lesson": 8,
        },
        headers=headers,
    )

    assert response.status_code == 200
    assert {
        item["source_name"] for item in response.json()["source_manifest"]
    } == {"admin_upload"}


def test_record_batches_and_total_records_are_bounded(monkeypatch):
    headers = {"X-Content-Agent-Token": TOKEN}
    batch_client = _client(monkeypatch, max_batch=2)
    path = "/api/v1/internal/content-agent/jobs/job-1/records"
    assert batch_client.post(path, json=_payload(3), headers=headers).status_code == 413

    total_client = _client(monkeypatch, max_batch=10, max_records=8)
    assert total_client.post(path, json=_payload(8), headers=headers).status_code == 202
    assert total_client.post(path, json=_payload(1), headers=headers).status_code == 413


def test_expired_job_context_returns_not_found(monkeypatch):
    now = [100.0]
    client = _client(monkeypatch, clock=lambda: now[0], ttl_seconds=5)
    headers = {"X-Content-Agent-Token": TOKEN}
    base = "/api/v1/internal/content-agent/jobs/job-expired"

    assert client.post(f"{base}/records", json=_payload(), headers=headers).status_code == 202
    now[0] += 6

    response = client.post(
        f"{base}/generate",
        json={"levels": ["A1"], "units_per_course": 1, "lessons_per_unit": 1},
        headers=headers,
    )
    assert response.status_code == 404


def test_sources_endpoint_returns_all_registered_sources(monkeypatch):
    client = _client(monkeypatch)
    headers = {"X-Content-Agent-Token": TOKEN}

    response = client.get(
        "/api/v1/internal/content-agent/sources",
        headers=headers,
    )

    assert response.status_code == 200
    entries = response.json()
    assert isinstance(entries, list)
    assert len(entries) > 0
    source_names = {e["source_name"] for e in entries}
    assert "oewn" in source_names
    assert "cmudict" in source_names
    assert "admin_upload" in source_names
    # Denied sources must not appear.
    assert "voa" not in source_names
    assert "bbc" not in source_names


def test_sources_endpoint_requires_token(monkeypatch):
    client = _client(monkeypatch)

    response = client.get("/api/v1/internal/content-agent/sources")
    assert response.status_code == 403


def test_snapshots_endpoint_requires_approved_manifest(monkeypatch, tmp_path):
    from api.routes import content_agent as routes_module

    client = _client(monkeypatch)
    headers = {"X-Content-Agent-Token": TOKEN}

    # Patch settings to use a temp storage root with no manifests.
    fake_settings = SimpleNamespace(
        CONTENT_AGENT_SERVICE_TOKEN=TOKEN,
        CONTENT_AGENT_MAX_BATCH_RECORDS=10,
        CONTENT_ETL_STORAGE_ROOT=str(tmp_path),
    )
    monkeypatch.setattr(routes_module, "get_settings", lambda: fake_settings)

    response = client.post(
        "/api/v1/internal/content-agent/jobs/oewn/snapshots",
        json={"source_version": "2025"},
        headers=headers,
    )

    assert response.status_code == 422
