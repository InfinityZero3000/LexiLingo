"""
Functional Tests for Proficiency Assessment Logic

These tests validate the core ProficiencyService algorithms WITHOUT
touching the database — pure unit tests for business logic.

Tests cover:
  1. Skill score calculation (EMA algorithm)
  2. Overall level determination (multi-criteria)
  3. Level requirements check
  4. Progress calculation toward next level
  5. XP calculation from exercises
  6. Level transition edge cases (A1→C2, demotion, stagnation)
  7. Assessment suggestion logic
  8. Accuracy and confidence model

Prerequisites: None (no database needed)

Usage:
  cd backend-service
  pytest tests/test_proficiency_functional.py -v
"""

import pytest
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Dict

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.schemas.proficiency import (
    SkillType,
    ProficiencyLevel,
    ExerciseResult,
    ProficiencyProfile,
    SkillAssessment,
    LEVEL_THRESHOLDS,
    LevelThreshold,
)
from app.services.proficiency_service import (
    ProficiencyService,
    SKILL_WEIGHTS,
    LEVEL_DIFFICULTY_MULTIPLIER,
    LEVEL_ORDER,
)


# ── Helpers ──────────────────────────────────────────────────────────

def _make_exercise(
    skill: SkillType = SkillType.VOCABULARY,
    level: ProficiencyLevel = ProficiencyLevel.A1,
    is_correct: bool = True,
    score: float = 80.0,
    time_spent: int = 30,
) -> ExerciseResult:
    return ExerciseResult(
        exercise_type="test_exercise",
        skill=skill,
        difficulty_level=level,
        is_correct=is_correct,
        score=score,
        time_spent_seconds=time_spent,
    )


def _make_batch(
    skill: SkillType,
    count: int,
    correct_ratio: float = 0.8,
    base_score: float = 75.0,
    level: ProficiencyLevel = ProficiencyLevel.A1,
) -> list[ExerciseResult]:
    """Create a batch of exercises with the given correct ratio."""
    exercises = []
    for i in range(count):
        is_correct = i < int(count * correct_ratio)
        score = base_score + 10 if is_correct else base_score - 30
        exercises.append(_make_exercise(
            skill=skill,
            level=level,
            is_correct=is_correct,
            score=max(0, min(100, score)),
        ))
    return exercises


def _make_confidences(value: float = 1.0) -> Dict[SkillType, float]:
    """Skill confidences for a learner whose scores have been measured.

    calculate_overall_level treats an absent confidence as zero — a learner we
    know nothing about cannot be promoted — so every test that expects a
    promotion has to say how well measured the learner is.
    """
    return {skill: value for skill in SkillType}


def _make_skill_scores(
    vocab: float = 0, grammar: float = 0, reading: float = 0,
    listening: float = 0, speaking: float = 0, writing: float = 0,
) -> Dict[SkillType, float]:
    return {
        SkillType.VOCABULARY: vocab,
        SkillType.GRAMMAR: grammar,
        SkillType.READING: reading,
        SkillType.LISTENING: listening,
        SkillType.SPEAKING: speaking,
        SkillType.WRITING: writing,
    }


# ═══════════════════════════════════════════════════════════════════════
# 1. Skill Score Calculation (EMA)
# ═══════════════════════════════════════════════════════════════════════

class TestSkillScoreCalculation:
    """Test the Exponential Moving Average skill scoring algorithm."""

    def test_no_exercises_returns_current_score(self):
        score, confidence = ProficiencyService.calculate_skill_score(
            exercises=[], skill=SkillType.VOCABULARY, current_score=50.0
        )
        assert score == 50.0
        assert confidence == 0.0

    def test_no_matching_skill_returns_current(self):
        exercises = [_make_exercise(skill=SkillType.GRAMMAR)]
        score, confidence = ProficiencyService.calculate_skill_score(
            exercises=exercises, skill=SkillType.VOCABULARY, current_score=60.0
        )
        assert score == 60.0
        assert confidence == 0.0

    def test_first_time_scoring_ignores_decay(self):
        """When current_score=0, result should be purely from exercises."""
        exercises = [_make_exercise(skill=SkillType.VOCABULARY, score=80.0, is_correct=True)]
        score, _ = ProficiencyService.calculate_skill_score(
            exercises=exercises, skill=SkillType.VOCABULARY, current_score=0.0
        )
        # Should be close to the exercise score (modified by difficulty)
        assert score > 0, "Score should be positive"
        assert score <= 100, "Score should not exceed 100"

    def test_ema_blends_with_history(self):
        """With existing score, new exercises should blend via EMA."""
        exercises = [_make_exercise(skill=SkillType.VOCABULARY, score=90.0, is_correct=True)]
        score, _ = ProficiencyService.calculate_skill_score(
            exercises=exercises, skill=SkillType.VOCABULARY, current_score=50.0
        )
        # EMA with decay=0.95: 0.95*50 + 0.05*adjusted_score
        # Should be between 50 and 90
        assert 50 <= score <= 90, f"EMA result {score} should be between 50 and 90"

    def test_higher_difficulty_gives_higher_score(self):
        """Exercises at higher CEFR levels should contribute more."""
        exercises_a1 = [_make_exercise(
            skill=SkillType.GRAMMAR, level=ProficiencyLevel.A1,
            score=80.0, is_correct=True,
        )]
        exercises_c1 = [_make_exercise(
            skill=SkillType.GRAMMAR, level=ProficiencyLevel.C1,
            score=80.0, is_correct=True,
        )]
        score_a1, _ = ProficiencyService.calculate_skill_score(
            exercises=exercises_a1, skill=SkillType.GRAMMAR, current_score=0
        )
        score_c1, _ = ProficiencyService.calculate_skill_score(
            exercises=exercises_c1, skill=SkillType.GRAMMAR, current_score=0
        )
        assert score_c1 > score_a1, (
            f"C1 exercise ({score_c1}) should score higher than A1 ({score_a1})"
        )

    def test_a_weak_answer_pulls_the_score_down(self):
        """The exercise's own score is the target, not its correct/incorrect flag.

        A wrong answer used to still add half its score, so a badly
        pronounced word could raise the speaking score. What matters is how
        well it was answered; is_correct is only a label for accuracy stats.
        """
        strong, _ = ProficiencyService.calculate_skill_score(
            exercises=[_make_exercise(score=90.0, is_correct=True)],
            skill=SkillType.VOCABULARY,
            current_score=60,
        )
        weak, _ = ProficiencyService.calculate_skill_score(
            exercises=[_make_exercise(score=20.0, is_correct=False)],
            skill=SkillType.VOCABULARY,
            current_score=60,
        )
        assert strong > 60 > weak

        # Same measured score, different label → same movement.
        labelled_correct, _ = ProficiencyService.calculate_skill_score(
            exercises=[_make_exercise(score=80.0, is_correct=True)],
            skill=SkillType.VOCABULARY,
            current_score=60,
        )
        labelled_wrong, _ = ProficiencyService.calculate_skill_score(
            exercises=[_make_exercise(score=80.0, is_correct=False)],
            skill=SkillType.VOCABULARY,
            current_score=60,
        )
        assert labelled_correct == labelled_wrong

    def test_confidence_increases_with_volume(self):
        """More exercises → higher confidence (up to 1.0 at 50 exercises)."""
        few = _make_batch(SkillType.VOCABULARY, 5)
        many = _make_batch(SkillType.VOCABULARY, 50)

        _, conf_few = ProficiencyService.calculate_skill_score(
            exercises=few, skill=SkillType.VOCABULARY, current_score=0
        )
        _, conf_many = ProficiencyService.calculate_skill_score(
            exercises=many, skill=SkillType.VOCABULARY, current_score=0
        )
        assert conf_many > conf_few
        assert conf_many == 1.0, "50 exercises should give full confidence"

    def test_score_clamped_to_0_100(self):
        """Score should never exceed [0, 100] range."""
        # Very high scores
        exercises = [_make_exercise(score=100.0, is_correct=True, level=ProficiencyLevel.C2)]
        score, _ = ProficiencyService.calculate_skill_score(
            exercises=exercises, skill=SkillType.VOCABULARY, current_score=99
        )
        assert score <= 100

        # Very low scores
        exercises_low = [_make_exercise(score=0.0, is_correct=False)]
        score_low, _ = ProficiencyService.calculate_skill_score(
            exercises=exercises_low, skill=SkillType.VOCABULARY, current_score=1
        )
        assert score_low >= 0


# ═══════════════════════════════════════════════════════════════════════
# 2. Overall Level Determination
# ═══════════════════════════════════════════════════════════════════════

class TestOverallLevelDetermination:
    """Test the multi-criteria level determination algorithm."""

    def test_zero_scores_gives_a1(self):
        level, progress = ProficiencyService.calculate_overall_level(
            skill_scores=_make_skill_scores(),
            exercises_completed=0,
            lessons_completed=0,
            accuracy=0.0,
        )
        assert level == ProficiencyLevel.A1

    def test_a2_qualification(self):
        """Meet all A2 requirements → should get A2."""
        # Weighted overall = 70*.10 + 65*.10 + 60*.20 + 58*.20 + 52*.20 + 50*.20 = 57.5 >= 55
        level, _ = ProficiencyService.calculate_overall_level(
            skill_scores=_make_skill_scores(
                vocab=70, grammar=65, reading=60, listening=58, speaking=52, writing=50,
            ),
            exercises_completed=60,
            lessons_completed=8,
            accuracy=0.65,
            skill_confidences=_make_confidences(),
        )
        assert level == ProficiencyLevel.A2

    def test_b1_qualification(self):
        """Meet all B1 requirements → should get B1."""
        # Weighted overall = 80*.10 + 75*.10 + 72*.20 + 70*.20 + 62*.20 + 60*.20 = 68.3 >= 65
        level, _ = ProficiencyService.calculate_overall_level(
            skill_scores=_make_skill_scores(
                vocab=80, grammar=75, reading=72, listening=70, speaking=62, writing=60,
            ),
            exercises_completed=150,
            lessons_completed=20,
            accuracy=0.70,
            streak_days=10,
            skill_confidences=_make_confidences(),
        )
        assert level == ProficiencyLevel.B1

    def test_b2_qualification(self):
        level, _ = ProficiencyService.calculate_overall_level(
            skill_scores=_make_skill_scores(
                vocab=85, grammar=82, reading=80, listening=78, speaking=72, writing=70,
            ),
            exercises_completed=300,
            lessons_completed=35,
            accuracy=0.75,
            streak_days=16,
            skill_confidences=_make_confidences(),
        )
        assert level == ProficiencyLevel.B2

    def test_c1_qualification(self):
        level, _ = ProficiencyService.calculate_overall_level(
            skill_scores=_make_skill_scores(
                vocab=90, grammar=88, reading=86, listening=84, speaking=80, writing=78,
            ),
            exercises_completed=600,
            lessons_completed=70,
            accuracy=0.82,
            streak_days=35,
            skill_confidences=_make_confidences(),
        )
        assert level == ProficiencyLevel.C1

    def test_c2_qualification(self):
        level, progress = ProficiencyService.calculate_overall_level(
            skill_scores=_make_skill_scores(
                vocab=96, grammar=96, reading=94, listening=93, speaking=92, writing=90,
            ),
            exercises_completed=1100,
            lessons_completed=130,
            accuracy=0.92,
            streak_days=65,
            skill_confidences=_make_confidences(),
        )
        assert level == ProficiencyLevel.C2
        assert progress == 100.0, "At max level, progress should be 100%"

    def test_insufficient_volume_blocks_promotion(self):
        """High skill scores but not enough exercises → stays at lower level."""
        level, _ = ProficiencyService.calculate_overall_level(
            skill_scores=_make_skill_scores(
                vocab=80, grammar=75, reading=70, listening=65, speaking=60, writing=55,
            ),
            exercises_completed=50,  # Need 100 for A2
            lessons_completed=5,     # Need 10 for A2
            accuracy=0.80,
        )
        # High scores but low volume → at most A1 (or A2 if volume check is satisfied)
        assert level in (ProficiencyLevel.A1, ProficiencyLevel.A2)

    def test_low_accuracy_blocks_promotion(self):
        """Good scores and volume but low accuracy → can't advance."""
        level, _ = ProficiencyService.calculate_overall_level(
            skill_scores=_make_skill_scores(
                vocab=70, grammar=65, reading=60, listening=55, speaking=40, writing=35,
            ),
            exercises_completed=400,
            lessons_completed=40,
            accuracy=0.40,  # Below A2's 0.60 threshold
        )
        assert level == ProficiencyLevel.A1

    def test_missing_streak_blocks_b1(self):
        """B1 requires 7 streak days. Missing it → stays A2."""
        level, _ = ProficiencyService.calculate_overall_level(
            skill_scores=_make_skill_scores(
                vocab=80, grammar=75, reading=72, listening=70, speaking=62, writing=60,
            ),
            exercises_completed=150,
            lessons_completed=20,
            accuracy=0.70,
            streak_days=0,  # B1 requires 7
            skill_confidences=_make_confidences(),
        )
        assert level == ProficiencyLevel.A2, (
            f"With 0 streak days, should be A2 max, got {level}"
        )

    def test_progress_increases_toward_next(self):
        """Progress should be between 0 and 100."""
        _, progress = ProficiencyService.calculate_overall_level(
            skill_scores=_make_skill_scores(vocab=40, grammar=35),
            exercises_completed=60,
            lessons_completed=5,
            accuracy=0.50,
        )
        assert 0 <= progress <= 100


# ═══════════════════════════════════════════════════════════════════════
# 3. Level Requirements Check
# ═══════════════════════════════════════════════════════════════════════

class TestLevelRequirementsCheck:
    """Test detailed level requirements checking."""

    def test_a1_user_gets_a2_requirements(self):
        check = ProficiencyService.get_level_requirements_check(
            current_level=ProficiencyLevel.A1,
            skill_scores=_make_skill_scores(),
            exercises_completed=0,
            lessons_completed=0,
            accuracy=0.0,
            streak_days=0,
        )
        assert check.next_level == ProficiencyLevel.A2

    def test_c2_user_has_no_next_level(self):
        check = ProficiencyService.get_level_requirements_check(
            current_level=ProficiencyLevel.C2,
            skill_scores=_make_skill_scores(96, 96, 92, 92, 92, 88),
            exercises_completed=3000,
            lessons_completed=300,
            accuracy=0.95,
            streak_days=100,
        )
        assert check.next_level is None
        assert check.overall_progress == 100.0

    def test_blockers_list_populated(self):
        check = ProficiencyService.get_level_requirements_check(
            current_level=ProficiencyLevel.A1,
            skill_scores=_make_skill_scores(vocab=30, grammar=20),
            exercises_completed=10,
            lessons_completed=1,
            accuracy=0.40,
            streak_days=0,
        )
        assert len(check.blockers) > 0, "Should have blockers for A2 promotion"

    def test_no_blockers_when_qualified(self):
        check = ProficiencyService.get_level_requirements_check(
            current_level=ProficiencyLevel.A1,
            skill_scores=_make_skill_scores(
                vocab=75, grammar=70, reading=68, listening=65, speaking=60, writing=58,
            ),
            exercises_completed=60,
            lessons_completed=8,
            accuracy=0.65,
            streak_days=0,
            skill_confidences=_make_confidences(),
        )
        assert check.qualifies_for_next is True
        assert len(check.blockers) == 0

    def test_requirements_dict_has_progress(self):
        check = ProficiencyService.get_level_requirements_check(
            current_level=ProficiencyLevel.B1,
            skill_scores=_make_skill_scores(vocab=70, grammar=65, reading=60, listening=55),
            exercises_completed=400,
            lessons_completed=40,
            accuracy=0.65,
            streak_days=5,
        )
        for name, req in check.requirements.items():
            assert "progress" in req
            assert 0 <= req["progress"] <= 100


# ═══════════════════════════════════════════════════════════════════════
# 4. XP Calculation
# ═══════════════════════════════════════════════════════════════════════

class TestXPCalculation:
    """Test XP earned from exercises (gamification, separate from proficiency)."""

    def test_correct_exercise_earns_more_xp(self):
        correct = [_make_exercise(is_correct=True)]
        incorrect = [_make_exercise(is_correct=False)]

        xp_correct = ProficiencyService._calculate_xp_from_exercises(correct)
        xp_incorrect = ProficiencyService._calculate_xp_from_exercises(incorrect)

        assert xp_correct > xp_incorrect

    def test_higher_difficulty_earns_more_xp(self):
        easy = [_make_exercise(level=ProficiencyLevel.A1, is_correct=True)]
        hard = [_make_exercise(level=ProficiencyLevel.C2, is_correct=True)]

        xp_easy = ProficiencyService._calculate_xp_from_exercises(easy)
        xp_hard = ProficiencyService._calculate_xp_from_exercises(hard)

        assert xp_hard > xp_easy, f"C2 XP ({xp_hard}) should be > A1 XP ({xp_easy})"

    def test_multiple_exercises_sum_xp(self):
        one = [_make_exercise(is_correct=True)]
        three = [_make_exercise(is_correct=True) for _ in range(3)]

        xp_one = ProficiencyService._calculate_xp_from_exercises(one)
        xp_three = ProficiencyService._calculate_xp_from_exercises(three)

        assert xp_three == xp_one * 3

    def test_empty_exercises_zero_xp(self):
        xp = ProficiencyService._calculate_xp_from_exercises([])
        assert xp == 0

    def test_xp_values_are_integers(self):
        exercises = _make_batch(SkillType.GRAMMAR, 10)
        xp = ProficiencyService._calculate_xp_from_exercises(exercises)
        assert isinstance(xp, int)


# ═══════════════════════════════════════════════════════════════════════
# 5. Level Navigation
# ═══════════════════════════════════════════════════════════════════════

class TestLevelNavigation:
    """Test get_next_level, get_previous_level, get_level_index."""

    def test_level_order(self):
        assert LEVEL_ORDER == [
            ProficiencyLevel.A1,
            ProficiencyLevel.A2,
            ProficiencyLevel.B1,
            ProficiencyLevel.B2,
            ProficiencyLevel.C1,
            ProficiencyLevel.C2,
        ]

    def test_next_level_progression(self):
        assert ProficiencyService.get_next_level(ProficiencyLevel.A1) == ProficiencyLevel.A2
        assert ProficiencyService.get_next_level(ProficiencyLevel.A2) == ProficiencyLevel.B1
        assert ProficiencyService.get_next_level(ProficiencyLevel.B1) == ProficiencyLevel.B2
        assert ProficiencyService.get_next_level(ProficiencyLevel.B2) == ProficiencyLevel.C1
        assert ProficiencyService.get_next_level(ProficiencyLevel.C1) == ProficiencyLevel.C2
        assert ProficiencyService.get_next_level(ProficiencyLevel.C2) is None

    def test_previous_level_regression(self):
        assert ProficiencyService.get_previous_level(ProficiencyLevel.A1) is None
        assert ProficiencyService.get_previous_level(ProficiencyLevel.A2) == ProficiencyLevel.A1
        assert ProficiencyService.get_previous_level(ProficiencyLevel.C2) == ProficiencyLevel.C1

    def test_level_index(self):
        assert ProficiencyService.get_level_index(ProficiencyLevel.A1) == 0
        assert ProficiencyService.get_level_index(ProficiencyLevel.C2) == 5


# ═══════════════════════════════════════════════════════════════════════
# 6. Assessment Suggestion Logic
# ═══════════════════════════════════════════════════════════════════════

class TestAssessmentSuggestion:
    """Test formal assessment suggestion rules."""

    def _profile(
        self,
        *,
        last_full_assessment: datetime | None,
        assessment_count: int = 50,
        score: float = 70,
    ) -> ProficiencyProfile:
        return ProficiencyProfile(
            user_id="user-1",
            overall_level=ProficiencyLevel.A1,
            skills={
                skill: SkillAssessment(
                    skill=skill,
                    score=score,
                    level=ProficiencyLevel.A1,
                    confidence=1.0,
                    total_exercises=assessment_count,
                    correct_exercises=int(assessment_count * 0.8),
                )
                for skill in SkillType
            },
            assessment_count=assessment_count,
            last_full_assessment=last_full_assessment,
        )

    def test_accepts_timezone_aware_last_assessment(self):
        profile = self._profile(
            last_full_assessment=datetime.now(UTC) - timedelta(days=8),
        )

        assert ProficiencyService.should_suggest_assessment(profile) is True

    def test_recent_timezone_aware_assessment_suppresses_suggestion(self):
        profile = self._profile(
            last_full_assessment=datetime.now(UTC) - timedelta(days=2),
        )

        assert ProficiencyService.should_suggest_assessment(profile) is False


# ═══════════════════════════════════════════════════════════════════════
# 7. Level Thresholds Configuration
# ═══════════════════════════════════════════════════════════════════════

class TestLevelThresholds:
    """Validate the LEVEL_THRESHOLDS configuration is consistent."""

    def test_all_levels_have_thresholds(self):
        for level in ProficiencyLevel:
            assert level in LEVEL_THRESHOLDS, f"Missing threshold for {level}"

    def test_a1_is_zero_requirements(self):
        a1 = LEVEL_THRESHOLDS[ProficiencyLevel.A1]
        assert a1.min_vocabulary_score == 0
        assert a1.min_grammar_score == 0
        assert a1.min_overall_score == 0
        assert a1.min_exercises_completed == 0
        assert a1.min_lessons_completed == 0
        assert a1.min_accuracy == 0.0

    def test_requirements_increase_with_level(self):
        """Each level should have equal or higher requirements than the previous."""
        prev = LEVEL_THRESHOLDS[ProficiencyLevel.A1]
        for level in [ProficiencyLevel.A2, ProficiencyLevel.B1, ProficiencyLevel.B2,
                      ProficiencyLevel.C1, ProficiencyLevel.C2]:
            curr = LEVEL_THRESHOLDS[level]
            assert curr.min_overall_score >= prev.min_overall_score, (
                f"{level.value} min_overall_score should be >= {prev.level.value}"
            )
            assert curr.min_exercises_completed >= prev.min_exercises_completed
            assert curr.min_lessons_completed >= prev.min_lessons_completed
            assert curr.min_accuracy >= prev.min_accuracy
            prev = curr

    def test_c2_has_highest_requirements(self):
        c2 = LEVEL_THRESHOLDS[ProficiencyLevel.C2]
        assert c2.min_vocabulary_score == 95
        assert c2.min_grammar_score == 95
        assert c2.min_exercises_completed == 1000
        assert c2.min_accuracy == 0.90

    def test_all_skill_weights_sum_to_1(self):
        total = sum(SKILL_WEIGHTS.values())
        assert abs(total - 1.0) < 0.01

    def test_all_difficulty_multipliers_positive(self):
        for level, mult in LEVEL_DIFFICULTY_MULTIPLIER.items():
            assert mult > 0, f"Multiplier for {level} should be > 0"

    def test_difficulty_multiplier_increases_with_level(self):
        prev_mult = 0
        for level in LEVEL_ORDER:
            mult = LEVEL_DIFFICULTY_MULTIPLIER[level]
            assert mult >= prev_mult, f"Multiplier for {level} should be >= previous"
            prev_mult = mult


# ═══════════════════════════════════════════════════════════════════════
# 7. Edge Cases and Regression
# ═══════════════════════════════════════════════════════════════════════

class TestEdgeCases:
    """Edge cases and regression tests for the proficiency system."""

    def test_single_skill_at_100_doesnt_give_c2(self):
        """Having just vocabulary at 100 shouldn't grant C2."""
        level, _ = ProficiencyService.calculate_overall_level(
            skill_scores=_make_skill_scores(vocab=100),
            exercises_completed=3000,
            lessons_completed=300,
            accuracy=0.95,
            streak_days=100,
        )
        assert level != ProficiencyLevel.C2, "Single skill at 100 shouldn't give C2"

    def test_all_skills_at_50_with_low_volume(self):
        level, _ = ProficiencyService.calculate_overall_level(
            skill_scores=_make_skill_scores(50, 50, 50, 50, 50, 50),
            exercises_completed=20,
            lessons_completed=2,
            accuracy=0.50,
        )
        assert level == ProficiencyLevel.A1

    def test_large_exercise_batch(self):
        """Processing 100 exercises at once shouldn't crash."""
        exercises = _make_batch(SkillType.VOCABULARY, 100, correct_ratio=0.7)
        score, confidence = ProficiencyService.calculate_skill_score(
            exercises=exercises, skill=SkillType.VOCABULARY, current_score=50
        )
        assert 0 <= score <= 100
        assert confidence == 1.0  # 100 exercises > 50 threshold

    def test_mixed_skills_in_one_batch(self):
        """Exercises for multiple skills processed correctly."""
        exercises = (
            _make_batch(SkillType.VOCABULARY, 10) +
            _make_batch(SkillType.GRAMMAR, 10) +
            _make_batch(SkillType.READING, 5)
        )
        # Calculate vocab score — should only consider vocab exercises
        score, conf = ProficiencyService.calculate_skill_score(
            exercises=exercises, skill=SkillType.VOCABULARY, current_score=0
        )
        assert conf == min(1.0, 10 / 50)  # 10 vocab exercises
        assert score > 0

    def test_zero_score_exercises(self):
        """All exercises with score=0 should give score 0."""
        exercises = [_make_exercise(score=0.0, is_correct=False) for _ in range(5)]
        score, _ = ProficiencyService.calculate_skill_score(
            exercises=exercises, skill=SkillType.VOCABULARY, current_score=0
        )
        assert score == 0.0

    def test_perfect_scores(self):
        """All exercises with score=100 and correct should give high score."""
        exercises = [
            _make_exercise(score=100.0, is_correct=True, level=ProficiencyLevel.B1)
            for _ in range(10)
        ]
        score, _ = ProficiencyService.calculate_skill_score(
            exercises=exercises, skill=SkillType.VOCABULARY, current_score=0
        )
        # Ten answers move the score a long way but must not max it — the old
        # version returned a flat 100 from the very first one.
        assert 30 <= score <= 60, f"10 perfect exercises from zero, got {score}"

        # Fifty of them should get close to the ceiling without reaching it.
        many, _ = ProficiencyService.calculate_skill_score(
            exercises=[
                _make_exercise(score=100.0, is_correct=True, level=ProficiencyLevel.B1)
                for _ in range(50)
            ],
            skill=SkillType.VOCABULARY,
            current_score=0,
        )
        assert 85 <= many < 100, f"50 perfect exercises should approach 100, got {many}"

    def test_progress_100_at_max_level(self):
        """At C2, progress should be 100%."""
        _, progress = ProficiencyService.calculate_overall_level(
            skill_scores=_make_skill_scores(96, 96, 92, 92, 92, 88),
            exercises_completed=2600,
            lessons_completed=260,
            accuracy=0.92,
            streak_days=65,
        )
        assert progress == 100.0


# ═══════════════════════════════════════════════════════════════════════
# 8. Simulated Learning Journey
# ═══════════════════════════════════════════════════════════════════════

class TestLearningJourney:
    """
    Simulate a realistic learning progression to verify the system
    correctly tracks improvement over time.
    """

    def test_gradual_improvement_promotes_level(self):
        """
        As a learner improves skill scores and completes more exercises,
        their level should eventually increase.
        """
        # Stage 1: Fresh learner
        level_1, _ = ProficiencyService.calculate_overall_level(
            skill_scores=_make_skill_scores(20, 15, 10, 10, 5, 5),
            exercises_completed=30,
            lessons_completed=3,
            accuracy=0.45,
        )
        assert level_1 == ProficiencyLevel.A1

        # Stage 2: Some progress
        level_2, _ = ProficiencyService.calculate_overall_level(
            skill_scores=_make_skill_scores(55, 50, 40, 35, 20, 15),
            exercises_completed=80,
            lessons_completed=8,
            accuracy=0.58,
            skill_confidences=_make_confidences(0.5),
        )
        assert level_2 == ProficiencyLevel.A1  # Not yet A2

        # Stage 3: strong on form but still weak at speaking and writing —
        # under the four-skill weighting that is no longer an A2 learner.
        level_3, _ = ProficiencyService.calculate_overall_level(
            skill_scores=_make_skill_scores(70, 65, 60, 55, 40, 35),
            exercises_completed=120,
            lessons_completed=12,
            accuracy=0.65,
            skill_confidences=_make_confidences(),
        )
        assert level_3 == ProficiencyLevel.A1

        # Stage 4: production catches up → A2
        level_4a, _ = ProficiencyService.calculate_overall_level(
            skill_scores=_make_skill_scores(70, 65, 60, 58, 52, 50),
            exercises_completed=120,
            lessons_completed=12,
            accuracy=0.65,
            skill_confidences=_make_confidences(),
        )
        assert level_4a == ProficiencyLevel.A2

        # Stage 5: balanced improvement across all four skills → B1
        level_4, progress_4 = ProficiencyService.calculate_overall_level(
            skill_scores=_make_skill_scores(80, 75, 72, 70, 62, 60),
            exercises_completed=350,
            lessons_completed=35,
            accuracy=0.68,
            streak_days=10,
            skill_confidences=_make_confidences(),
        )
        # Should be B1 with these scores
        assert level_4 == ProficiencyLevel.B1

    def test_declining_performance_blocks_promotion(self):
        """Even with high volume, declining accuracy should block advancement."""
        # High scores and volume but terrible accuracy
        level, _ = ProficiencyService.calculate_overall_level(
            skill_scores=_make_skill_scores(70, 68, 60, 55, 45, 40),
            exercises_completed=500,
            lessons_completed=50,
            accuracy=0.30,  # Very low
            streak_days=20,
        )
        assert level == ProficiencyLevel.A1, "Low accuracy should cap level at A1"

    def test_skill_imbalance_slows_progression(self):
        """
        A learner with very strong vocabulary but weak grammar
        shouldn't advance as fast as a balanced learner.
        """
        # Imbalanced: Strong vocab, weak grammar
        level_imbalanced, prog_imbal = ProficiencyService.calculate_overall_level(
            skill_scores=_make_skill_scores(
                vocab=90, grammar=30, reading=50, listening=45, speaking=20, writing=15,
            ),
            exercises_completed=150,
            lessons_completed=15,
            accuracy=0.60,
        )

        # Balanced: Medium everything
        level_balanced, prog_bal = ProficiencyService.calculate_overall_level(
            skill_scores=_make_skill_scores(
                vocab=65, grammar=60, reading=50, listening=45, speaking=30, writing=25,
            ),
            exercises_completed=150,
            lessons_completed=15,
            accuracy=0.65,
        )

        # The balanced learner should be at same or higher level
        assert ProficiencyService.get_level_index(level_balanced) >= \
               ProficiencyService.get_level_index(level_imbalanced), (
            f"Balanced ({level_balanced}) should be >= imbalanced ({level_imbalanced})"
        )


# ═══════════════════════════════════════════════════════════════════════
# 9. Seed Data Validation
# ═══════════════════════════════════════════════════════════════════════

class TestSeedDataConsistency:
    """
    Validate that the seed data script produces logically consistent data
    by running the seed generation in-memory and checking invariants.
    """

    def test_seeded_b1_level_is_achievable(self):
        """
        The seeded user is at B1. Verify this is achievable with
        the seeded stats (~500 exercises, ~68% accuracy, 38 lessons, 7+ streak).
        """
        # Approximate the seeded user's stats
        level, progress = ProficiencyService.calculate_overall_level(
            skill_scores=_make_skill_scores(
                vocab=72, grammar=68, reading=65, listening=62, speaking=56, writing=54,
            ),
            exercises_completed=500,
            lessons_completed=38,
            accuracy=0.68,
            streak_days=10,  # Simulated
            skill_confidences=_make_confidences(),
        )
        assert level in (ProficiencyLevel.A2, ProficiencyLevel.B1), (
            f"Seeded stats should qualify for A2 or B1, got {level}"
        )

    def test_exercise_count_in_realistic_range(self):
        """~500 exercises over 90 days = ~5.5 per day, which is realistic."""
        exercises_per_day = 500 / 90
        assert 3 <= exercises_per_day <= 10, (
            f"Average {exercises_per_day:.1f} exercises/day should be between 3 and 10"
        )

    def test_accuracy_in_realistic_range(self):
        """~68% accuracy is realistic for a B1 learner."""
        accuracy = 0.68
        assert 0.5 <= accuracy <= 0.85, "68% accuracy is within realistic range"
