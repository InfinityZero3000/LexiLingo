"""End-to-end: author a paper, sit it, submit, read the result.

The AI grader is patched with autospec — the real one costs a model call per
task, and a bare AsyncMock would happily accept a signature that no longer
exists.
"""

from unittest.mock import AsyncMock, patch

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.ielts import IeltsTest


def _full_paper() -> dict:
    return {
        "sections": [
            {
                "skill": "listening",
                "duration_minutes": 30,
                "parts": [
                    {
                        "order": 1,
                        "title": "Part 1",
                        "audio_url": "/media/ielts/l1.mp3",
                        "transcript": "WOMAN: The library closes at six.",
                        "question_groups": [
                            {
                                "question_type": "form_completion",
                                "instructions": "ONE WORD ONLY",
                                "questions": [
                                    {
                                        "key": "L1",
                                        "number": 1,
                                        "prompt": "The ___ closes at six.",
                                        "accepted_answers": ["library"],
                                    },
                                    {
                                        "key": "L2",
                                        "number": 2,
                                        "prompt": "It closes at ___.",
                                        "accepted_answers": ["six", "6"],
                                    },
                                ],
                            }
                        ],
                    }
                ],
            },
            {
                "skill": "reading",
                "duration_minutes": 60,
                "parts": [
                    {
                        "order": 1,
                        "passage_title": "Bees",
                        "passage_text": "Bees pollinate most flowering plants.",
                        "question_groups": [
                            {
                                "question_type": "true_false_notgiven",
                                "questions": [
                                    {
                                        "key": "R1",
                                        "number": 1,
                                        "prompt": "Bees pollinate plants.",
                                        "accepted_answers": ["true"],
                                    }
                                ],
                            }
                        ],
                    }
                ],
            },
            {
                "skill": "writing",
                "duration_minutes": 60,
                "parts": [
                    {
                        "order": 1,
                        "part_key": "writing_task_2",
                        "prompt": "Discuss whether university should be free.",
                        "min_words": 250,
                    }
                ],
            },
            {
                "skill": "speaking",
                "duration_minutes": 14,
                "parts": [
                    {
                        "order": 1,
                        "part_key": "speaking_part_2",
                        "cue_card": "Describe a book you enjoyed.",
                    }
                ],
            },
        ]
    }


@pytest.fixture
async def published_test(db_session: AsyncSession) -> IeltsTest:
    test = IeltsTest(
        title="IELTS Academic Mock 1",
        test_type="academic",
        skill_scope="full",
        content=_full_paper(),
        is_published=True,
    )
    db_session.add(test)
    await db_session.commit()
    await db_session.refresh(test)
    return test


async def test_paper_reaches_the_learner_without_its_answer_key(
    async_client: AsyncClient, auth_headers: dict, published_test: IeltsTest
):
    response = await async_client.get(
        f"/api/v1/ielts/tests/{published_test.id}", headers=auth_headers
    )
    assert response.status_code == 200
    body = response.json()["data"]
    serialized = str(body)
    # The answer key and the listening transcript must not ship to the client.
    assert "accepted_answers" not in serialized
    assert "library" not in serialized
    assert "transcript" not in serialized
    assert body["question_count"] == 3


async def test_start_is_idempotent_and_resumes(
    async_client: AsyncClient, auth_headers: dict, published_test: IeltsTest
):
    first = await async_client.post(
        f"/api/v1/ielts/tests/{published_test.id}/start", json={}, headers=auth_headers
    )
    second = await async_client.post(
        f"/api/v1/ielts/tests/{published_test.id}/start", json={}, headers=auth_headers
    )
    assert first.status_code == second.status_code == 200
    assert first.json()["data"]["attempt_id"] == second.json()["data"]["attempt_id"]


async def test_autosave_merges_rather_than_replaces(
    async_client: AsyncClient, auth_headers: dict, published_test: IeltsTest
):
    start = await async_client.post(
        f"/api/v1/ielts/tests/{published_test.id}/start", json={}, headers=auth_headers
    )
    attempt_id = start.json()["data"]["attempt_id"]

    await async_client.patch(
        f"/api/v1/ielts/attempts/{attempt_id}/answers",
        json={"answers": {"L1": "library"}},
        headers=auth_headers,
    )
    second = await async_client.patch(
        f"/api/v1/ielts/attempts/{attempt_id}/answers",
        json={"answers": {"R1": "true"}},
        headers=auth_headers,
    )
    # A Reading autosave must not wipe the Listening answers already stored.
    assert second.json()["data"]["saved"] == 2


async def test_submit_scores_objective_now_and_queues_ai_grading(
    async_client: AsyncClient, auth_headers: dict, published_test: IeltsTest
):
    start = await async_client.post(
        f"/api/v1/ielts/tests/{published_test.id}/start", json={}, headers=auth_headers
    )
    attempt_id = start.json()["data"]["attempt_id"]

    graded = {
        "criteria": {
            "task_achievement": 6.0,
            "coherence_cohesion": 6.0,
            "lexical_resource": 6.5,
            "grammatical_range": 6.5,
        },
        "band": 6.5,
        "feedback": {"reasoning": "ok", "strengths": [], "improvements": [], "corrections": []},
        "word_count": 260,
        "grader_version": "ielts-grader-v1",
        "model": "test",
    }

    with patch(
        "app.routes.ielts.grade_ielts_submission",
        new=AsyncMock(return_value=graded),
    ):
        response = await async_client.post(
            f"/api/v1/ielts/attempts/{attempt_id}/submit",
            json={
                "answers": {
                    "L1": "The Library",
                    "L2": "6",
                    "R1": "TRUE",
                    "writing_task_2": "word " * 260,
                    "speaking_part_2": "I read The Alchemist last year.",
                },
                "time_spent_seconds": 3600,
            },
            headers=auth_headers,
        )

    assert response.status_code == 200
    data = response.json()["data"]
    # Case, articles and digit-vs-word variants all score.
    assert data["raw_scores"]["listening"] == {"raw": 2, "total": 2}
    assert data["raw_scores"]["reading"] == {"raw": 1, "total": 1}
    assert data["listening_band"] == 9.0
    assert data["pending_gradings"] == 2


async def test_result_exposes_per_question_review(
    async_client: AsyncClient, auth_headers: dict, published_test: IeltsTest
):
    start = await async_client.post(
        f"/api/v1/ielts/tests/{published_test.id}/start", json={}, headers=auth_headers
    )
    attempt_id = start.json()["data"]["attempt_id"]
    await async_client.post(
        f"/api/v1/ielts/attempts/{attempt_id}/submit",
        json={"answers": {"L1": "library", "L2": "seven", "R1": "false"}},
        headers=auth_headers,
    )

    result = await async_client.get(
        f"/api/v1/ielts/attempts/{attempt_id}/result", headers=auth_headers
    )
    assert result.status_code == 200
    review = result.json()["data"]["review"]
    listening = {item["key"]: item for item in review["listening"]}
    assert listening["L1"]["is_correct"] is True
    assert listening["L2"]["is_correct"] is False
    # Review is the one place the correct answer is meant to be visible.
    assert listening["L2"]["correct_answer"] == ["six", "6"]


async def test_another_learner_cannot_read_the_attempt(
    async_client: AsyncClient,
    auth_headers: dict,
    admin_headers: dict,
    published_test: IeltsTest,
):
    start = await async_client.post(
        f"/api/v1/ielts/tests/{published_test.id}/start", json={}, headers=auth_headers
    )
    attempt_id = start.json()["data"]["attempt_id"]
    response = await async_client.get(
        f"/api/v1/ielts/attempts/{attempt_id}/result", headers=admin_headers
    )
    assert response.status_code == 404


async def test_publish_is_blocked_until_the_paper_is_sittable(
    async_client: AsyncClient, admin_headers: dict, db_session: AsyncSession
):
    draft = IeltsTest(
        title="Broken paper",
        test_type="academic",
        skill_scope="full",
        content={
            "sections": [
                {
                    "skill": "listening",
                    "parts": [
                        {
                            "order": 1,
                            "question_groups": [
                                {"questions": [{"key": "L1", "prompt": "?"}]}
                            ],
                        }
                    ],
                }
            ]
        },
        is_published=False,
    )
    db_session.add(draft)
    await db_session.commit()
    await db_session.refresh(draft)

    response = await async_client.put(
        f"/api/v1/admin/ielts/tests/{draft.id}",
        json={"title": "Broken paper", "is_published": True},
        headers=admin_headers,
    )
    assert response.status_code == 400
    problems = str(response.json())
    assert "answer key" in problems
    assert "audio_url" in problems
    assert "missing" in problems.lower()
