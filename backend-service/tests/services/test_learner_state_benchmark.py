"""Does the scheduler actually beat the traditional ones? Measure, don't assert taste.

A simulated learner has a *true* memory the scheduler cannot see. Each
scheduler picks review dates; at each date the learner recalls with the true
probability and is graded. Schedulers only ever observe the grade — the same
information a real app has.

The headline metric is calibration error: the engine schedules reviews
claiming ~TARGET_RETENTION recall, so |true recall at review - target| is how
badly it misses. A scheduler can always buy retention by reviewing constantly,
so retention is only meaningful next to workload.

Everything is seeded, so these numbers are reproducible rather than flaky.
"""

import random
import statistics
from dataclasses import dataclass, replace
from datetime import UTC, datetime, timedelta

import pytest

import app.services.learner_state as learner_state
from app.services.learner_state import (
    TARGET_RETENTION,
    LearnerStateSnapshot,
    evolve_state,
    grade_to_observation,
)

HORIZON_DAYS = 180.0
N_ITEMS = 60
EPOCH = datetime(2026, 1, 1, tzinfo=UTC)


@dataclass
class TrueMemory:
    """Ground truth. Deliberately not any scheduler's model of itself."""

    stability: float
    difficulty: float
    last_seen: float = 0.0

    def recall_prob(self, t: float) -> float:
        elapsed = max(0.0, t - self.last_seen)
        return (1.0 + (19 / 81) * elapsed / self.stability) ** -0.5

    def review(self, t: float, recalled: bool) -> None:
        if recalled:
            # Real spacing effect: retrieving a faded memory is worth more.
            gain = 1.0 + 0.9 * (1.0 - self.difficulty)
            gain *= 1.0 + 1.2 * (1.0 - self.recall_prob(t))
            self.stability *= gain
        else:
            self.stability = max(0.4, self.stability * 0.35)
        self.last_seen = t


def _grade(p_recall: float, recalled: bool) -> int:
    if not recalled:
        return 0 if p_recall < 0.3 else (1 if p_recall < 0.6 else 2)
    return 5 if p_recall > 0.85 else (4 if p_recall > 0.6 else 3)


class SM2Scheduler:
    """SuperMemo SM-2 — what Anki shipped for years, and what this repo used."""

    def __init__(self) -> None:
        self.ease, self.interval, self.reps = 2.5, 1, 0

    def next_interval(self, grade: int, _t: float) -> float:
        if grade < 3:
            self.reps, self.interval = 0, 1
        else:
            self.interval = (
                1 if self.reps == 0 else (6 if self.reps == 1 else int(self.interval * self.ease))
            )
            self.reps += 1
        self.ease = max(1.3, self.ease + (0.1 - (5 - grade) * (0.08 + (5 - grade) * 0.02)))
        return float(self.interval)


class LeitnerScheduler:
    """Leitner boxes — the paper-flashcard system these all descend from."""

    BOXES = (1, 2, 4, 8, 16, 32, 64)

    def __init__(self) -> None:
        self.box = 0

    def next_interval(self, grade: int, _t: float) -> float:
        self.box = min(self.box + 1, len(self.BOXES) - 1) if grade >= 3 else 0
        return float(self.BOXES[self.box])


class FixedIntervalScheduler:
    """The naive baseline: review everything weekly, performance be damned."""

    def next_interval(self, _grade: int, _t: float) -> float:
        return 7.0


class EngineScheduler:
    """The production engine, driven through its real entry points."""

    def __init__(self) -> None:
        self.state = LearnerStateSnapshot()

    def next_interval(self, grade: int, t: float) -> float:
        now = EPOCH + timedelta(days=t)
        self.state = evolve_state(self.state, *grade_to_observation(grade), now=now)
        return (self.state.next_review_at - now).total_seconds() / 86_400.0


def _homogeneous(rng: random.Random) -> list[tuple[float, float]]:
    return [(rng.uniform(0.15, 0.85), rng.uniform(0.5, 2.5)) for _ in range(N_ITEMS)]


def _heterogeneous(rng: random.Random) -> list[tuple[float, float]]:
    """A real deck: a few leeches, a lot of easy words, the rest in between."""
    items = []
    for _ in range(N_ITEMS):
        roll = rng.random()
        if roll < 0.20:
            items.append((rng.uniform(0.85, 0.98), rng.uniform(0.2, 0.6)))
        elif roll < 0.50:
            items.append((rng.uniform(0.02, 0.15), rng.uniform(2.0, 6.0)))
        else:
            items.append((rng.uniform(0.3, 0.7), rng.uniform(0.8, 2.5)))
    return items


def _simulate(scheduler_factory, items, *, target: float = TARGET_RETENTION) -> dict:
    misses: list[float] = []
    reviews: list[int] = []
    retentions: list[float] = []

    for index, (difficulty, stability) in enumerate(items):
        memory = TrueMemory(stability=stability, difficulty=difficulty)
        scheduler = scheduler_factory()
        rng = random.Random(1000 + index)
        t, count = 0.0, 0

        while t <= HORIZON_DAYS and count < 2000:
            probability = memory.recall_prob(t)
            if count > 0:  # first exposure teaches, it does not test
                misses.append(abs(probability - target))
            recalled = rng.random() < probability
            grade = _grade(probability, recalled)
            memory.review(t, recalled)
            count += 1
            t += max(scheduler.next_interval(grade, t), 1 / 24)

        reviews.append(count)
        retentions.append(memory.recall_prob(HORIZON_DAYS))

    return {
        "calibration": statistics.fmean(misses),
        "reviews": statistics.fmean(reviews),
        "retention": statistics.fmean(retentions),
    }


@pytest.fixture(scope="module")
def homogeneous_items():
    return _homogeneous(random.Random(20260813))


@pytest.fixture(scope="module")
def heterogeneous_items():
    return _heterogeneous(random.Random(20260813))


def test_engine_schedules_closer_to_target_retention_than_sm2(heterogeneous_items):
    engine = _simulate(EngineScheduler, heterogeneous_items)
    sm2 = _simulate(SM2Scheduler, heterogeneous_items)

    assert engine["calibration"] < sm2["calibration"]
    assert engine["retention"] > sm2["retention"]


def test_engine_beats_leitner_on_a_mixed_difficulty_deck(heterogeneous_items):
    """Leitner's fixed ladder can tie an adaptive scheduler when every item is
    equally hard; it cannot adapt per item once a deck holds both leeches and
    easy words, which is what a real vocabulary deck looks like."""
    engine = _simulate(EngineScheduler, heterogeneous_items)
    leitner = _simulate(LeitnerScheduler, heterogeneous_items)

    assert engine["calibration"] < leitner["calibration"]
    assert engine["retention"] > leitner["retention"]


def test_no_traditional_scheduler_dominates_the_engine(homogeneous_items):
    """The honest comparison.

    Raw workload is not comparable across schedulers that hold different
    retention: SM-2 reviews least precisely because it lets recall decay
    furthest. So instead require Pareto-optimality — no scheduler may be both
    cheaper (fewer reviews) *and* better remembered than the engine. Whoever
    reviews less must also retain less, and whoever retains more must pay for
    it.
    """
    engine = _simulate(EngineScheduler, homogeneous_items)

    for name, factory in (
        ("SM-2", SM2Scheduler),
        ("Leitner", LeitnerScheduler),
        ("fixed-7-day", FixedIntervalScheduler),
    ):
        rival = _simulate(factory, homogeneous_items)
        dominates = (
            rival["reviews"] <= engine["reviews"]
            and rival["retention"] >= engine["retention"]
        )
        assert not dominates, (
            f"{name} beat the engine on both axes: "
            f"{rival['reviews']:.1f} reviews / {rival['retention']:.3f} retention "
            f"vs {engine['reviews']:.1f} / {engine['retention']:.3f}"
        )


def test_engine_is_not_just_reviewing_everything_constantly(homogeneous_items):
    """Retention bought by brute force is not a scheduling win: beat the
    naive 'review every 7 days' baseline on cost without losing recall."""
    engine = _simulate(EngineScheduler, homogeneous_items)
    fixed = _simulate(FixedIntervalScheduler, homogeneous_items)

    # Measured at this horizon: 0.63x the reviews for 0.017 less retention.
    # The bound is loose because the early learning phase legitimately needs
    # dense reviews; over a full year the ratio drops to ~0.37x.
    assert engine["reviews"] < fixed["reviews"] * 0.75
    assert engine["retention"] > fixed["retention"] - 0.05


def test_review_load_never_collapses_into_cramming(heterogeneous_items):
    """v1's failure mode: intervals pinned near the floor, so a year of study
    covered days. Guard the shape, not one magic number."""
    engine = _simulate(EngineScheduler, heterogeneous_items)

    reviews_per_item_per_day = engine["reviews"] / HORIZON_DAYS
    assert reviews_per_item_per_day < 0.5


@pytest.mark.parametrize("target", [0.80, 0.95])
def test_target_retention_is_a_working_dial(monkeypatch, homogeneous_items, target):
    """SM-2 and Leitner have no retention knob at all: their intervals are
    baked in. Here the target must actually move observed recall."""
    baseline = _simulate(EngineScheduler, homogeneous_items, target=TARGET_RETENTION)
    monkeypatch.setattr(learner_state, "TARGET_RETENTION", target)
    adjusted = _simulate(EngineScheduler, homogeneous_items, target=target)

    observed_baseline = TARGET_RETENTION - baseline["calibration"]
    observed_adjusted = target - adjusted["calibration"]

    if target < TARGET_RETENTION:
        assert adjusted["reviews"] <= baseline["reviews"]
        assert observed_adjusted < observed_baseline
    else:
        assert adjusted["reviews"] >= baseline["reviews"]
        assert observed_adjusted > observed_baseline


def test_lapses_do_not_strand_a_forgotten_word_far_in_the_future(heterogeneous_items):
    """The property SM-2 gets right and v1 inverted: forgetting brings a word
    back sooner, and a wrong answer never schedules later than a right one."""
    learned = LearnerStateSnapshot(
        mastery_probability=0.9,
        stability_days=60.0,
        difficulty=0.4,
        attempt_count=8,
        last_interacted_at=EPOCH,
    )
    now = EPOCH + timedelta(days=60)

    gaps = {}
    for quality in range(6):
        result = evolve_state(replace(learned), *grade_to_observation(quality), now=now)
        gaps[quality] = (result.next_review_at - now).total_seconds()

    assert gaps[0] < gaps[1] < gaps[2]
    assert max(gaps[0], gaps[1], gaps[2]) < min(gaps[3], gaps[4], gaps[5])
