import hashlib
import json
from types import SimpleNamespace

from api.routes import content_agent as content_agent_routes
from api.services.content_agent.service import ContentAgentService
from api.services.content_agent.store import ContentAgentStore
from api.services.content_etl.pipeline import ETLPipeline
from api.services.content_etl.storage import SnapshotStorage
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
    storage_root="/private/tmp/lexilingo-content-agent-test-storage",
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
        CONTENT_ETL_STORAGE_ROOT=str(storage_root),
    )
    monkeypatch.setattr(content_agent_routes, "get_settings", lambda: settings)

    app = FastAPI()
    app.include_router(content_agent_routes.router)
    app.dependency_overrides[content_agent_routes.get_content_agent_service] = lambda: service
    return TestClient(app)


def _stage_oewn_snapshot(tmp_path, *, count=8):
    storage = SnapshotStorage(tmp_path)
    records = [
        {
            "record_id": f"oewn:2025:{index}",
            "source_record_id": f"oewn-entry-{index}",
            "word": f"word{index:02d}",
            "part_of_speech": "noun",
            "definition": f"A complete lexical definition for word {index}.",
            "declared_cefr": "A1",
        }
        for index in range(count)
    ]
    raw = json.dumps(records, sort_keys=True).encode("utf-8")
    digest = hashlib.sha256(raw).hexdigest()
    temp = storage.create_temp_file()
    temp.write_bytes(raw)
    storage.promote_raw(
        temp,
        source_name="oewn",
        version="2025",
        filename="english-wordnet-2025.xml.gz",
        sha256=digest,
    )
    report = ETLPipeline(storage=storage).run(
        source_name="oewn",
        source_version="2025",
        adapter_name="oewn",
        adapter_version=1,
        license_id="CC-BY-4.0",
        license_url="https://creativecommons.org/licenses/by/4.0/",
        attribution_text="Open English WordNet 2025",
        raw_records=records,
        raw_bytes=raw,
        official_url="https://en-word.net/static/english-wordnet-2025.xml.gz",
    )
    assert report.status == "approved"
    return storage.read_active_manifest("oewn")


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


def test_generation_ignores_attached_sources_not_selected_by_request(
    monkeypatch,
    tmp_path,
):
    manifest = _stage_oewn_snapshot(tmp_path)
    client = _client(monkeypatch, storage_root=tmp_path)
    headers = {"X-Content-Agent-Token": TOKEN}
    base = "/api/v1/internal/content-agent/jobs/source-filter"
    assert client.post(f"{base}/records", json=_payload(), headers=headers).status_code == 202
    attached = client.post(
        f"{base}/snapshots",
        json={
            "snapshots": [
                {
                    "source_id": "oewn",
                    "source_version": "2025",
                    "snapshot_id": manifest.snapshot_id,
                }
            ]
        },
        headers=headers,
    )
    assert attached.status_code == 202, attached.text

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


def test_sources_endpoint_returns_only_active_verified_sources(monkeypatch, tmp_path):
    manifest = _stage_oewn_snapshot(tmp_path)
    client = _client(monkeypatch, storage_root=tmp_path)
    headers = {"X-Content-Agent-Token": TOKEN}

    response = client.get(
        "/api/v1/internal/content-agent/sources",
        headers=headers,
    )

    assert response.status_code == 200
    entries = response.json()
    assert isinstance(entries, list)
    assert len(entries) == 1
    source_names = {e["source_name"] for e in entries}
    assert source_names == {"oewn"}
    assert entries[0]["snapshot_id"] == manifest.snapshot_id
    assert entries[0]["status"] == "active"
    assert entries[0]["record_count"] == 8
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
        "/api/v1/internal/content-agent/jobs/job-attach/snapshots",
        json={
            "snapshots": [
                {
                    "source_id": "oewn",
                    "source_version": "2025",
                    "snapshot_id": "oewn:2025:" + ("a" * 64),
                }
            ]
        },
        headers=headers,
    )

    assert response.status_code == 422


def test_snapshot_attachment_loads_exact_records_for_generation(monkeypatch, tmp_path):
    manifest = _stage_oewn_snapshot(tmp_path)
    client = _client(monkeypatch, storage_root=tmp_path)
    headers = {"X-Content-Agent-Token": TOKEN}
    base = "/api/v1/internal/content-agent/jobs/snapshot-job"

    attached = client.post(
        f"{base}/snapshots",
        json={
            "snapshots": [
                {
                    "source_id": "oewn",
                    "source_version": manifest.source_version,
                    "snapshot_id": manifest.snapshot_id,
                }
            ]
        },
        headers=headers,
    )
    assert attached.status_code == 202, attached.text
    assert attached.json() == {
        "attached_snapshots": 1,
        "stored_records": 8,
    }

    generated = client.post(
        f"{base}/generate",
        json={
            "levels": ["A1"],
            "sources": ["oewn"],
            "units_per_course": 1,
            "lessons_per_unit": 1,
            "words_per_lesson": 8,
        },
        headers=headers,
    )
    assert generated.status_code == 200
    source_manifest = generated.json()["source_manifest"]
    assert len(source_manifest) == 1
    assert source_manifest[0]["snapshot_id"] == manifest.snapshot_id
    assert source_manifest[0]["raw_checksum"] == manifest.raw_sha256
