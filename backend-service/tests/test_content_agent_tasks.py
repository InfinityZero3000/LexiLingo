import httpx
import pytest

from app.schemas.content_agent import ContentAgentArtifact
from app.tasks.content_agent import (
    _attach_pinned_snapshots,
    _public_error_message,
    _with_transient_retry,
)


async def test_transient_ai_calls_retry_with_a_bound(monkeypatch):
    attempts = 0

    async def operation():
        nonlocal attempts
        attempts += 1
        if attempts < 3:
            raise httpx.ConnectError("temporary secret endpoint failure")
        return "ok"

    async def no_sleep(_delay):
        return None

    monkeypatch.setattr("app.tasks.content_agent.asyncio.sleep", no_sleep)

    assert await _with_transient_retry(operation) == "ok"
    assert attempts == 3


async def test_non_transient_ai_calls_are_not_retried(monkeypatch):
    attempts = 0
    request = httpx.Request("POST", "https://ai.internal/generate")
    response = httpx.Response(422, request=request)

    async def operation():
        nonlocal attempts
        attempts += 1
        raise httpx.HTTPStatusError(
            "payload included a private definition",
            request=request,
            response=response,
        )

    with pytest.raises(httpx.HTTPStatusError):
        await _with_transient_retry(operation)
    assert attempts == 1


def test_public_task_errors_do_not_expose_exception_payloads():
    request = httpx.Request("POST", "https://ai.internal/generate")
    response = httpx.Response(422, request=request)
    error = httpx.HTTPStatusError(
        "private uploaded definition: do not expose",
        request=request,
        response=response,
    )

    message = _public_error_message(error)

    assert message == "AI content service request failed with status 422"
    assert "private uploaded definition" not in message


async def test_worker_attaches_exact_pinned_snapshots_before_generation():
    calls = []

    class FakeClient:
        async def attach_snapshots(self, job_id, snapshots):
            calls.append((job_id, snapshots))
            return {"attached_snapshots": len(snapshots)}

    job_id = __import__("uuid").uuid4()
    snapshots = [
        {
            "source_id": "oewn",
            "source_version": "2025",
            "snapshot_id": "oewn:2025:" + ("a" * 64),
        }
    ]

    await _attach_pinned_snapshots(FakeClient(), job_id, snapshots)

    assert calls == [(job_id, snapshots)]


def test_strict_artifact_manifest_serializes_to_json_primitives():
    artifact = ContentAgentArtifact.model_validate(
        {
            "schema_version": 2,
            "prompt_version": "cefr-course-v2",
            "generation_key": "a" * 64,
            "source_manifest": [
                {
                    "snapshot_id": f"oewn:2025:{'b' * 64}",
                    "source_name": "oewn",
                    "source_version": "2025",
                    "official_url": "https://en-word.net/static/english-wordnet-2025.xml.gz",
                    "license_id": "CC-BY-4.0",
                    "license_url": "https://creativecommons.org/licenses/by/4.0/",
                    "attribution_text": "Open English WordNet 2025",
                    "retrieved_at": "2026-06-15T00:00:00Z",
                    "raw_checksum": "b" * 64,
                    "normalized_sha256": "c" * 64,
                    "normalized_bytes": 128,
                    "record_checksum_root": "d" * 64,
                    "adapter_version": 1,
                    "record_count": 1,
                }
            ],
            "courses": [
                {
                    "title": "A1",
                    "level": "A1",
                    "units": [
                        {
                            "title": "Unit",
                            "order_index": 0,
                            "lessons": [
                                {
                                    "title": "Lesson",
                                    "order_index": 0,
                                    "vocabulary": [
                                        {
                                            "word": "hello",
                                            "definition": "A complete greeting definition.",
                                            "part_of_speech": "interjection",
                                            "difficulty_level": "A1",
                                        }
                                    ],
                                    "exercises": [
                                        {
                                            "id": "ex-1",
                                            "type": "translate",
                                            "ui_type": "speaking_repeat",
                                            "question": "Repeat hello.",
                                            "correct_answer": "hello",
                                        }
                                    ],
                                }
                            ],
                        }
                    ],
                }
            ],
        }
    )

    serialized = [
        item.model_dump(mode="json") for item in artifact.source_manifest
    ]
    assert isinstance(serialized[0]["retrieved_at"], str)
    assert serialized[0]["snapshot_id"].startswith("oewn:2025:")
