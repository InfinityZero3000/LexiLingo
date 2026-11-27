"""A placement test must not reward guessing."""

import pytest

from app.routes.proficiency import PLACEMENT_QUESTIONS, chance_corrected_percentage

BASE = "/api/v1/proficiency"


def _score(picks: dict[int, int]) -> int:
    return sum(q["points"] for q in PLACEMENT_QUESTIONS if picks.get(q["id"]) == q["correct"])


def test_chance_score_is_zero_and_perfect_is_hundred():
    expected_by_chance = sum(q["points"] / len(q["options"]) for q in PLACEMENT_QUESTIONS)
    assert chance_corrected_percentage(round(expected_by_chance)) == pytest.approx(0, abs=1)
    assert chance_corrected_percentage(sum(q["points"] for q in PLACEMENT_QUESTIONS)) == 100
    assert chance_corrected_percentage(0) == 0


async def test_answering_a_to_everything_stays_at_a1(async_client, auth_headers):
    answers = [{"question_id": q["id"], "selected_option": 0} for q in PLACEMENT_QUESTIONS]
    response = await async_client.post(
        f"{BASE}/placement-test/submit", json={"answers": answers}, headers=auth_headers
    )
    assert response.status_code == 200
    body = response.json()
    assert body["test_level"] == "A1"
    assert body["score_percentage"] < 20


async def test_a_real_strong_result_still_places_high(async_client, auth_headers):
    answers = [{"question_id": q["id"], "selected_option": q["correct"]} for q in PLACEMENT_QUESTIONS]
    response = await async_client.post(
        f"{BASE}/placement-test/submit", json={"answers": answers}, headers=auth_headers
    )
    assert response.json()["test_level"] == "C2"
