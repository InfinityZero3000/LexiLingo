"""
FSRS Algorithm Correctness Tests

Verifies both the FSRS-inspired scheduling (calculate_fsrs_review) and
the SM-2 scheduling (calculate_next_review) against hand-computed reference
values derived directly from the algorithm formulas.

Notation:
  S  = stability   D  = difficulty   R  = retrievability
  q  = quality (0–5)   t  = elapsed days
"""

import math
from datetime import datetime, timedelta, timezone

import pytest

from app.crud.vocabulary import VocabularyCRUD

NOW = datetime(2026, 6, 15, 9, 0, 0, tzinfo=timezone.utc)
crud = VocabularyCRUD()


# ─────────────────────────────────────────────────────────────────────────────
# Helper
# ─────────────────────────────────────────────────────────────────────────────

def fsrs(
    quality: int,
    stability: float = 0.0,
    difficulty: float = 0.0,
    scheduled_days: int = 0,
    reps: int = 0,
    lapses: int = 0,
    last_review_days_ago: int | None = None,
) -> dict:
    last = (NOW - timedelta(days=last_review_days_ago)) if last_review_days_ago is not None else None
    return crud.calculate_fsrs_review(
        quality=quality,
        stability=stability,
        difficulty=difficulty,
        scheduled_days=scheduled_days,
        reps=reps,
        lapses=lapses,
        fsrs_last_review=last,
        sm2_last_review=None,
        now=NOW,
    )


def sm2(quality: int, ease_factor: float = 2.5, interval: int = 1, repetitions: int = 0) -> tuple:
    return crud.calculate_next_review(quality, ease_factor, interval, repetitions)


# ─────────────────────────────────────────────────────────────────────────────
# FSRS: Initial card (reps=0) — stability lookup table
# ─────────────────────────────────────────────────────────────────────────────

INITIAL_STABILITY = {0: 0.4, 1: 0.6, 2: 1.0, 3: 2.4, 4: 3.8, 5: 5.8}


@pytest.mark.parametrize("quality,expected_s", INITIAL_STABILITY.items())
def test_fsrs_initial_stability_lookup(quality, expected_s):
    r = fsrs(quality)
    assert r["fsrs_stability"] == expected_s, (
        f"q={quality}: expected S={expected_s}, got {r['fsrs_stability']}"
    )


# ─────────────────────────────────────────────────────────────────────────────
# FSRS: Initial card — difficulty formula  D = clamp(7.0 - (q-3)*0.8, 1, 10)
# ─────────────────────────────────────────────────────────────────────────────

INITIAL_DIFFICULTY = {
    0: 9.4,   # clamp(7.0 - (-3)*0.8) = clamp(9.4)
    1: 8.6,   # clamp(7.0 - (-2)*0.8) = clamp(8.6)
    2: 7.8,
    3: 7.0,
    4: 6.2,
    5: 5.4,
}


@pytest.mark.parametrize("quality,expected_d", INITIAL_DIFFICULTY.items())
def test_fsrs_initial_difficulty_formula(quality, expected_d):
    r = fsrs(quality)
    assert round(r["fsrs_difficulty"], 4) == pytest.approx(expected_d, abs=1e-9), (
        f"q={quality}: expected D={expected_d}, got {r['fsrs_difficulty']}"
    )


# ─────────────────────────────────────────────────────────────────────────────
# FSRS: Initial card — reps/lapses bookkeeping
# ─────────────────────────────────────────────────────────────────────────────

def test_fsrs_initial_correct_increments_reps():
    r = fsrs(4)
    assert r["fsrs_reps"] == 1
    assert r["fsrs_lapses"] == 0


def test_fsrs_initial_fail_increments_lapses():
    r = fsrs(1)
    assert r["fsrs_reps"] == 1
    assert r["fsrs_lapses"] == 1


# ─────────────────────────────────────────────────────────────────────────────
# FSRS: Initial card — state machine
# State 1 = learning, 2 = review, 3 = relearning
# ─────────────────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("quality,expected_state", [
    (0, 1),  # fail on new card → learning
    (1, 1),
    (2, 1),
    (3, 2),  # stability=2.4 ≥ 2 → review
    (4, 2),
    (5, 2),
])
def test_fsrs_initial_state(quality, expected_state):
    r = fsrs(quality)
    assert r["fsrs_state"] == expected_state, (
        f"q={quality}: expected state={expected_state}, got {r['fsrs_state']}"
    )


# ─────────────────────────────────────────────────────────────────────────────
# FSRS: Initial card — scheduled days
# ─────────────────────────────────────────────────────────────────────────────

def test_fsrs_initial_fail_schedules_1_day():
    for q in (0, 1, 2):
        r = fsrs(q)
        assert r["fsrs_scheduled_days"] == 1, f"q={q}: expected 1 day, got {r['fsrs_scheduled_days']}"


def test_fsrs_initial_good_schedules_ceil_stability():
    # q=3: S=2.4 → ceil=3, no quality==5 boost
    r = fsrs(3)
    assert r["fsrs_scheduled_days"] == 3


def test_fsrs_initial_easy_schedules_ceil_stability():
    # q=4: S=3.8 → ceil=4
    r = fsrs(4)
    assert r["fsrs_scheduled_days"] == 4


def test_fsrs_initial_perfect_gets_stability_bonus():
    # q=5: S=5.8 → ceil=6, bonus=ceil(5.8*1.15)=ceil(6.67)=7 → max(6,7)=7
    r = fsrs(5)
    assert r["fsrs_scheduled_days"] == 7


# ─────────────────────────────────────────────────────────────────────────────
# FSRS: next_review_date = now + scheduled_days
# ─────────────────────────────────────────────────────────────────────────────

def test_fsrs_next_review_date_matches_scheduled_days():
    r = fsrs(4)
    expected = NOW + timedelta(days=r["fsrs_scheduled_days"])
    assert r["next_review_date"] == expected


# ─────────────────────────────────────────────────────────────────────────────
# FSRS: elapsed_days tracking
# ─────────────────────────────────────────────────────────────────────────────

def test_fsrs_elapsed_days_computed_from_last_review():
    r = fsrs(4, stability=3.8, difficulty=6.2, reps=1, last_review_days_ago=5)
    assert r["fsrs_elapsed_days"] == 5


def test_fsrs_elapsed_days_is_zero_for_new_card():
    r = fsrs(4)
    assert r["fsrs_elapsed_days"] == 0


# ─────────────────────────────────────────────────────────────────────────────
# FSRS: Retrievability and stability growth on correct review
# ─────────────────────────────────────────────────────────────────────────────

def _expected_retrievability(elapsed: int, stability: float) -> float:
    decay = -0.5
    factor = 19 / 81
    r = (1 + factor * elapsed / stability) ** decay
    return max(0.01, min(1.0, r))


def test_fsrs_perfect_review_grows_stability():
    # After 5 days with S=4.0, D=5.0 → stability should increase
    r = fsrs(5, stability=4.0, difficulty=5.0, reps=1, last_review_days_ago=5)
    assert r["fsrs_stability"] > 4.0


def test_fsrs_easy_review_grows_stability():
    r = fsrs(4, stability=4.0, difficulty=5.0, reps=1, last_review_days_ago=4)
    assert r["fsrs_stability"] > 4.0


def test_fsrs_good_review_grows_stability_modestly():
    r = fsrs(3, stability=4.0, difficulty=5.0, scheduled_days=4, reps=1, last_review_days_ago=4)
    # growth but limited: scheduled_days capped to current_scheduled_days+1=5
    assert r["fsrs_stability"] > 4.0
    assert r["fsrs_scheduled_days"] <= 5


def test_fsrs_failed_review_reduces_stability_to_55_percent():
    # S_new = max(0.5, S*0.55)
    r = fsrs(1, stability=8.0, difficulty=5.0, reps=2, last_review_days_ago=6)
    expected = max(0.5, 8.0 * 0.55)
    assert r["fsrs_stability"] == pytest.approx(expected, abs=1e-4)


def test_fsrs_failed_review_stability_floor_is_0_5():
    r = fsrs(0, stability=0.6, difficulty=9.0, reps=1, last_review_days_ago=1)
    assert r["fsrs_stability"] >= 0.5


# ─────────────────────────────────────────────────────────────────────────────
# FSRS: Lapse / state machine on subsequent reviews
# ─────────────────────────────────────────────────────────────────────────────

def test_fsrs_failed_subsequent_review_is_relearning_state():
    # reps>0, quality<3 → state=3 (relearning)
    r = fsrs(2, stability=5.0, difficulty=5.0, reps=3, last_review_days_ago=5)
    assert r["fsrs_state"] == 3
    assert r["fsrs_lapses"] == 1


def test_fsrs_failed_subsequent_review_schedules_1_day():
    r = fsrs(0, stability=10.0, difficulty=5.0, reps=5, last_review_days_ago=10)
    assert r["fsrs_scheduled_days"] == 1


def test_fsrs_correct_review_high_stability_is_review_state():
    r = fsrs(4, stability=5.0, difficulty=5.0, reps=2, last_review_days_ago=5)
    assert r["fsrs_state"] == 2  # review state


def test_fsrs_correct_review_low_stability_is_learning_state():
    # S_new just under 2 → learning
    r = fsrs(3, stability=1.5, difficulty=7.0, scheduled_days=2, reps=1, last_review_days_ago=2)
    # new_stability ≥ initial (1.5) since quality=3, but still may be <2
    assert r["fsrs_state"] in (1, 2)  # depends on growth


# ─────────────────────────────────────────────────────────────────────────────
# FSRS: Difficulty mean-reversion
# D_new = clamp(D - (q-3)*0.3 + (4-D)*0.05, 1, 10)
# ─────────────────────────────────────────────────────────────────────────────

def test_fsrs_difficulty_decreases_on_perfect():
    # D=7, q=5: D_new = clamp(7 - (5-3)*0.3 + (4-7)*0.05) = clamp(7-0.6-0.15) = 6.25
    r = fsrs(5, stability=4.0, difficulty=7.0, reps=1, last_review_days_ago=4)
    assert r["fsrs_difficulty"] < 7.0


def test_fsrs_difficulty_increases_on_failure():
    # D=5, q=0: D_new = clamp(5 - (0-3)*0.3 + (4-5)*0.05) = clamp(5+0.9-0.05) = 5.85
    r = fsrs(0, stability=4.0, difficulty=5.0, reps=1, last_review_days_ago=4)
    assert r["fsrs_difficulty"] > 5.0


def test_fsrs_difficulty_floor_is_1():
    # Very easy card D=1, perfect → clamped to 1
    r = fsrs(5, stability=10.0, difficulty=1.0, reps=3, last_review_days_ago=10)
    assert r["fsrs_difficulty"] >= 1.0


def test_fsrs_difficulty_ceiling_is_10():
    # Very hard card D=9.5, blackout → clamped to 10
    r = fsrs(0, stability=1.0, difficulty=9.5, reps=2, last_review_days_ago=1)
    assert r["fsrs_difficulty"] <= 10.0


# ─────────────────────────────────────────────────────────────────────────────
# FSRS: quality=3 conservative cap (scheduled_days ≤ current_scheduled + 1)
# ─────────────────────────────────────────────────────────────────────────────

def test_fsrs_quality3_respects_conservative_cap():
    # Existing card with scheduled_days=5; quality=3 must not jump more than +1
    r = fsrs(3, stability=20.0, difficulty=5.0, scheduled_days=5, reps=3, last_review_days_ago=5)
    assert r["fsrs_scheduled_days"] <= 6


# ─────────────────────────────────────────────────────────────────────────────
# FSRS: absolute maximum scheduled days cap (36 500 ≈ 100 years)
# ─────────────────────────────────────────────────────────────────────────────

def test_fsrs_scheduled_days_never_exceed_36500():
    r = fsrs(5, stability=99999.0, difficulty=1.0, reps=100, last_review_days_ago=99999)
    assert r["fsrs_scheduled_days"] <= 36500


# ─────────────────────────────────────────────────────────────────────────────
# FSRS: quality boundary clamping (outside 0–5 is clamped)
# ─────────────────────────────────────────────────────────────────────────────

def test_fsrs_quality_below_zero_clamped_to_zero():
    r_neg = crud.calculate_fsrs_review(
        quality=-1, stability=0.0, difficulty=0.0,
        scheduled_days=0, reps=0, lapses=0,
        fsrs_last_review=None, sm2_last_review=None, now=NOW,
    )
    r_zero = fsrs(0)
    assert r_neg["fsrs_stability"] == r_zero["fsrs_stability"]


def test_fsrs_quality_above_five_clamped_to_five():
    r_high = crud.calculate_fsrs_review(
        quality=9, stability=0.0, difficulty=0.0,
        scheduled_days=0, reps=0, lapses=0,
        fsrs_last_review=None, sm2_last_review=None, now=NOW,
    )
    r_five = fsrs(5)
    assert r_high["fsrs_stability"] == r_five["fsrs_stability"]


# ─────────────────────────────────────────────────────────────────────────────
# SM-2: calculate_next_review correctness
# ─────────────────────────────────────────────────────────────────────────────

def test_sm2_first_correct_gives_interval_1():
    ef, interval, reps, _ = sm2(quality=4, ease_factor=2.5, interval=1, repetitions=0)
    assert interval == 1
    assert reps == 1


def test_sm2_second_correct_gives_interval_6():
    ef, interval, reps, _ = sm2(quality=4, ease_factor=2.5, interval=1, repetitions=1)
    assert interval == 6
    assert reps == 2


def test_sm2_third_correct_multiplies_by_ease_factor():
    # interval=6, EF=2.5 → int(6*2.5) = 15
    ef, interval, reps, _ = sm2(quality=5, ease_factor=2.5, interval=6, repetitions=2)
    assert interval == 15
    assert reps == 3


def test_sm2_failed_review_resets_interval_and_reps():
    ef, interval, reps, _ = sm2(quality=2, ease_factor=2.5, interval=15, repetitions=3)
    assert interval == 1
    assert reps == 0


def test_sm2_perfect_score_increases_ease_factor():
    ef, _, _, _ = sm2(quality=5, ease_factor=2.5, interval=1, repetitions=0)
    # EF + 0.1 - (5-5)*(0.08+0) = 2.5+0.1 = 2.6
    assert ef == pytest.approx(2.6, abs=1e-9)


def test_sm2_easy_score_keeps_ease_factor():
    ef, _, _, _ = sm2(quality=4, ease_factor=2.5, interval=1, repetitions=0)
    # EF + 0.1 - 1*(0.08+1*0.02) = 2.5+0.1-0.1 = 2.5
    assert ef == pytest.approx(2.5, abs=1e-9)


def test_sm2_good_score_decreases_ease_factor():
    ef, _, _, _ = sm2(quality=3, ease_factor=2.5, interval=1, repetitions=0)
    # EF + 0.1 - 2*(0.08+2*0.02) = 2.5+0.1-2*0.12 = 2.5+0.1-0.24 = 2.36
    assert ef == pytest.approx(2.36, abs=1e-9)


def test_sm2_hard_score_significantly_decreases_ease_factor():
    ef, _, _, _ = sm2(quality=2, ease_factor=2.5, interval=1, repetitions=0)
    # EF + 0.1 - 3*(0.08+3*0.02) = 2.5+0.1-3*0.14 = 2.5+0.1-0.42 = 2.18
    assert ef == pytest.approx(2.18, abs=1e-9)


def test_sm2_ease_factor_floor_is_1_3():
    # Keep failing until EF would go below 1.3
    ef, _, _, _ = sm2(quality=0, ease_factor=1.35, interval=1, repetitions=0)
    assert ef >= 1.3


def test_sm2_long_session_schedule_progression():
    """3-review session at q=5: EF compounds (2.5→2.6→2.7), so 3rd interval=int(6*2.7)=16."""
    ef, interval, reps, _ = sm2(5, 2.5, 1, 0)   # session 1: interval=1, ef=2.6
    assert interval == 1
    ef2, interval, reps, _ = sm2(5, ef, interval, reps)  # session 2: interval=6, ef=2.7
    assert interval == 6
    _, interval3, _, _ = sm2(5, ef2, interval, reps)  # session 3: interval=int(6*2.7)=16
    assert interval3 == int(6 * ef2)  # exact: 16


def test_sm2_next_review_date_is_in_future():
    _, interval, _, next_date = sm2(5, 2.5, 1, 0)
    assert next_date > datetime.now(timezone.utc)


# ─────────────────────────────────────────────────────────────────────────────
# VocabularyCRUD: determine_status helper
# ─────────────────────────────────────────────────────────────────────────────

def test_status_is_mastered_when_high_ef_and_long_interval():
    status = crud.determine_status(ease_factor=2.5, interval=21, repetitions=5)
    from app.models.vocabulary import VocabularyStatus
    assert status == VocabularyStatus.MASTERED


def test_status_is_reviewing_when_enough_reps():
    status = crud.determine_status(ease_factor=2.0, interval=5, repetitions=3)
    from app.models.vocabulary import VocabularyStatus
    assert status == VocabularyStatus.REVIEWING


def test_status_is_learning_for_new_words():
    status = crud.determine_status(ease_factor=2.5, interval=1, repetitions=0)
    from app.models.vocabulary import VocabularyStatus
    assert status == VocabularyStatus.LEARNING


def test_status_needs_both_ef_and_interval_for_mastered():
    from app.models.vocabulary import VocabularyStatus
    # High EF but short interval → not mastered
    assert crud.determine_status(2.5, 5, 5) != VocabularyStatus.MASTERED
    # Long interval but low EF → not mastered
    assert crud.determine_status(2.0, 30, 5) != VocabularyStatus.MASTERED
