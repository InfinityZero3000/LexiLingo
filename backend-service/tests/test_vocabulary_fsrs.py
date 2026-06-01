from datetime import datetime, timedelta, timezone

from app.crud.vocabulary import VocabularyCRUD


def test_initial_easy_review_creates_fsrs_schedule():
    crud = VocabularyCRUD()
    now = datetime(2026, 5, 25, tzinfo=timezone.utc)

    result = crud.calculate_fsrs_review(
        quality=5,
        stability=0.0,
        difficulty=0.0,
        scheduled_days=0,
        reps=0,
        lapses=0,
        fsrs_last_review=None,
        sm2_last_review=None,
        now=now,
    )

    assert result["fsrs_reps"] == 1
    assert result["fsrs_lapses"] == 0
    assert result["fsrs_state"] == 2
    assert result["fsrs_stability"] > 0
    assert result["fsrs_difficulty"] < 7
    assert result["fsrs_scheduled_days"] >= 1
    assert result["next_review_date"] == now + timedelta(days=result["fsrs_scheduled_days"])


def test_failed_review_increments_lapse_and_resets_interval():
    crud = VocabularyCRUD()
    now = datetime(2026, 5, 25, tzinfo=timezone.utc)
    last_review = now - timedelta(days=5)

    result = crud.calculate_fsrs_review(
        quality=1,
        stability=4.0,
        difficulty=5.0,
        scheduled_days=4,
        reps=3,
        lapses=1,
        fsrs_last_review=last_review,
        sm2_last_review=None,
        now=now,
    )

    assert result["fsrs_elapsed_days"] == 5
    assert result["fsrs_reps"] == 4
    assert result["fsrs_lapses"] == 2
    assert result["fsrs_state"] == 3
    assert result["fsrs_scheduled_days"] == 1
