"""
Proficiency Assessment Service

Implements the multi-dimensional proficiency assessment algorithm that
evaluates user language level based on skill performance, not just XP.

Key Features:
1. Skill-weighted scoring (vocabulary, grammar, reading, listening, speaking, writing)
2. Exercise difficulty consideration (harder exercises = more weight)
3. Consistency tracking (accuracy over time)
4. Volume requirements (can't skip levels with few exercises)
5. Trend analysis (improving or declining)
"""

from datetime import UTC, datetime

from app.schemas.proficiency import (
    LEVEL_THRESHOLDS,
    ExerciseResult,
    LevelCheckResponse,
    ProficiencyAssessmentResult,
    ProficiencyLevel,
    ProficiencyProfile,
    SkillType,
)

# Skill weights for overall score calculation.
#
# Weighted around the four skills rather than around form knowledge. The
# previous split put 50% on vocabulary+grammar and only 20% on speaking+writing,
# which measured something closer to a traditional grammar-and-vocabulary test
# than to CEFR — where vocabulary and grammar are *resources* serving reception,
# production and interaction, not two of the pillars.
SKILL_WEIGHTS = {
    SkillType.LISTENING: 0.20,
    SkillType.SPEAKING: 0.20,
    SkillType.READING: 0.20,
    SkillType.WRITING: 0.20,
    SkillType.VOCABULARY: 0.10,
    SkillType.GRAMMAR: 0.10,
}

# How many measured exercises make a skill score fully trustworthy. Reached
# gradually, so a brand-new skill reads as "barely measured" rather than as a
# confident zero.
CONFIDENCE_FULL_EXERCISES = 50

# Ceiling on how far one exercise may move a skill score, whatever its
# difficulty — without it a single C2 answer would swing the score by 10%.
MAX_SCORE_STEP = 0.15

# Level difficulty multipliers (exercises at higher levels worth more)
LEVEL_DIFFICULTY_MULTIPLIER = {
    ProficiencyLevel.A1: 0.5,
    ProficiencyLevel.A2: 0.7,
    ProficiencyLevel.B1: 1.0,
    ProficiencyLevel.B2: 1.3,
    ProficiencyLevel.C1: 1.6,
    ProficiencyLevel.C2: 2.0,
}

# Level ordering for comparison
LEVEL_ORDER = [
    ProficiencyLevel.A1,
    ProficiencyLevel.A2,
    ProficiencyLevel.B1,
    ProficiencyLevel.B2,
    ProficiencyLevel.C1,
    ProficiencyLevel.C2,
]

# What each game actually exercises. This used to be derived by splitting
# game_type on "_" and keyword-matching the pieces, which scored every game
# except grammar_quiz as vocabulary — fill_blank in particular draws from a
# grammar question bank (present simple, passive, conditionals) and was being
# credited to the wrong skill. Keep this in sync with the game_type values
# created in app/routes/games.py.
GAME_TYPE_SKILL = {
    "word_scramble": SkillType.VOCABULARY,
    "matching": SkillType.VOCABULARY,
    "spelling_bee": SkillType.VOCABULARY,
    "hangman": SkillType.VOCABULARY,
    "fill_blank": SkillType.GRAMMAR,
    "grammar_quiz": SkillType.GRAMMAR,
}


class ProficiencyService:
    """Service for calculating and managing user proficiency."""

    @staticmethod
    def resolve_lesson_skill(
        lesson_skill: str | None,
        course_skill: str | None,
        course_tags: list[str] | None,
    ) -> SkillType:
        """Which skill a finished lesson credits, most specific label first.

        lesson.skill beats course.skill beats guessing from tags. The guess is
        only reachable for content authored before the columns existed; new
        content sets them explicitly.
        """
        for label in (lesson_skill, course_skill):
            if not label:
                continue
            try:
                return SkillType(label.strip().lower())
            except ValueError:
                continue
        return ProficiencyService.infer_skill_from_tags(course_tags)

    @staticmethod
    def skill_for_game(game_type: str | None) -> SkillType:
        """SkillType a game session exercises. Unknown types fall back to
        VOCABULARY — add the new game to GAME_TYPE_SKILL instead of relying
        on that."""
        return GAME_TYPE_SKILL.get((game_type or "").strip().lower(), SkillType.VOCABULARY)

    @staticmethod
    def infer_skill_from_tags(tags: list[str] | None) -> SkillType:
        """Last-resort SkillType guess from a course's free-form tags.

        Only for legacy rows: courses and lessons carry an explicit `skill`
        column now, and `resolve_lesson_skill` consults that first. A tag
        list that matches nothing lands on VOCABULARY, which is why guessing
        used to mis-credit listening and speaking content."""
        skill_keywords = {
            SkillType.GRAMMAR: {"grammar"},
            SkillType.READING: {"reading"},
            SkillType.LISTENING: {"listening", "podcast"},
            SkillType.SPEAKING: {"speaking", "pronunciation", "conversation"},
            SkillType.WRITING: {"writing"},
        }
        normalized = {t.lower() for t in (tags or [])}
        for skill, keywords in skill_keywords.items():
            if normalized & keywords:
                return skill
        return SkillType.VOCABULARY

    @staticmethod
    def get_level_index(level: ProficiencyLevel) -> int:
        """Get numeric index of level (0 = A1, 5 = C2)."""
        return LEVEL_ORDER.index(level)

    @staticmethod
    def get_next_level(level: ProficiencyLevel) -> ProficiencyLevel | None:
        """Get the next level, or None if at C2."""
        idx = LEVEL_ORDER.index(level)
        if idx >= len(LEVEL_ORDER) - 1:
            return None
        return LEVEL_ORDER[idx + 1]

    @staticmethod
    def get_previous_level(level: ProficiencyLevel) -> ProficiencyLevel | None:
        """Get the previous level, or None if at A1."""
        idx = LEVEL_ORDER.index(level)
        if idx <= 0:
            return None
        return LEVEL_ORDER[idx - 1]

    @staticmethod
    def evaluate_exam_gated_promotion(
        current_level: ProficiencyLevel,
        exam_level: ProficiencyLevel,
        passed: bool,
        score: float,
        passing_score: float = 70.0,
    ) -> dict[str, object]:
        """
        Evaluate whether a user is eligible for CEFR promotion via exam gate.

        Skeleton rule set:
        1) User must pass the exam and meet passing_score.
        2) Exam level must be current level or higher.
        3) Promotion is at most one CEFR tier (to next tier).
        """
        if current_level == ProficiencyLevel.C2:
            return {
                "eligible": False,
                "promoted": False,
                "promoted_to": None,
                "reason": "Already at maximum CEFR tier (C2).",
            }

        if not passed or score < passing_score:
            return {
                "eligible": False,
                "promoted": False,
                "promoted_to": None,
                "reason": "Exam not passed at required threshold.",
            }

        current_idx = ProficiencyService.get_level_index(current_level)
        exam_idx = ProficiencyService.get_level_index(exam_level)
        if exam_idx < current_idx:
            return {
                "eligible": False,
                "promoted": False,
                "promoted_to": None,
                "reason": "Exam tier is below current CEFR level.",
            }

        promoted_to = ProficiencyService.get_next_level(current_level)
        return {
            "eligible": True,
            "promoted": promoted_to is not None,
            "promoted_to": promoted_to,
            "reason": "Eligible via exam-gated progression.",
        }

    @staticmethod
    def apply_exam_gated_promotion(
        current_level: ProficiencyLevel,
        exam_level: ProficiencyLevel,
        passed: bool,
        score: float,
        passing_score: float = 70.0,
    ) -> tuple[ProficiencyLevel, dict[str, object]]:
        """Apply exam-gated decision and return resulting level plus decision payload."""
        decision = ProficiencyService.evaluate_exam_gated_promotion(
            current_level=current_level,
            exam_level=exam_level,
            passed=passed,
            score=score,
            passing_score=passing_score,
        )

        promoted_to = decision.get("promoted_to")
        if decision.get("promoted") and isinstance(promoted_to, ProficiencyLevel):
            return promoted_to, decision
        return current_level, decision

    @staticmethod
    def calculate_skill_score(
        exercises: list[ExerciseResult],
        skill: SkillType,
        current_score: float | None = 0,
        decay_factor: float = 0.95,
        *,
        prior_exercises: int = 0,
        current_level: ProficiencyLevel = ProficiencyLevel.A1,
    ) -> tuple[float, float]:
        """
        Update a skill score by one exponential-moving-average step per exercise.

        Args:
            exercises: results from this call (any skill; filtered here)
            skill: the skill being updated
            current_score: score before this call, 0-100
            decay_factor: history weight; 0.95 means one average-difficulty
                exercise moves the score 5% of the way to its result
            prior_exercises: how many exercises this skill has already been
                scored on, for the confidence figure
            current_level: the learner's assessed CEFR level, used as the
                starting point when this skill has never been scored

        Returns:
            (new_score, confidence)

        Three properties this has to hold, each of which it did not before:

        * **One exercise cannot max the score.** The old version skipped the
          average entirely when the score was 0, so a single correct answer
          scored 100/100. It now starts from the floor of the learner's
          current level and moves gradually.
        * **Batching does not change the result.** The average used to be
          applied once per call, so six answers in one request moved the score
          far less than the same six sent separately — and News quizzes batch
          while Book quizzes do not. It is now applied once per exercise.
        * **Difficulty survives.** The old difficulty bonus went into the
          numerator and was then clipped at 100, so A1 and C2 answers landed
          identically. Difficulty now scales the step size instead.
        """
        skill_exercises = [e for e in exercises if e.skill == skill]

        score = current_score or 0.0
        if not skill_exercises:
            return round(score, 2), ProficiencyService._score_confidence(prior_exercises)

        if not score:
            # Never scored: start from what the learner's level already implies
            # rather than from whatever the first answer happened to be.
            threshold = LEVEL_THRESHOLDS.get(current_level)
            score = float(getattr(threshold, "min_overall_score", 0.0) or 0.0)

        base_step = 1.0 - decay_factor
        for exercise in skill_exercises:
            difficulty_mult = LEVEL_DIFFICULTY_MULTIPLIER.get(
                exercise.difficulty_level, 1.0
            )
            # Harder exercises are stronger evidence, so they move the score
            # further. Capped so a single C2 answer still cannot dominate.
            step = min(MAX_SCORE_STEP, base_step * difficulty_mult)
            # The exercise's own score is the target — a wrong answer is not
            # worth half credit, it is worth what it scored.
            score += step * (exercise.score - score)

        score = max(0.0, min(100.0, score))
        confidence = ProficiencyService._score_confidence(
            prior_exercises + len(skill_exercises)
        )
        return round(score, 2), confidence

    @staticmethod
    def weighted_overall(skill_scores: dict[SkillType, float]) -> float:
        """The one overall score, weighted by SKILL_WEIGHTS.

        There used to be three different answers to "what is this learner's
        overall score": this weighted one (used to decide level-ups but never
        stored), a plain unweighted mean written to the profile after every
        exercise, and the raw percentage from a placement test that overwrote
        it. The number a learner saw was therefore not the number their
        promotion was judged on. Every caller goes through here now.

        Skills with no score yet are left out rather than counted as zero, so
        an unmeasured skill does not drag the total down.
        """
        weighted = 0.0
        total_weight = 0.0
        for skill, weight in SKILL_WEIGHTS.items():
            score = skill_scores.get(skill)
            if score is None:
                continue
            weighted += score * weight
            total_weight += weight
        if total_weight <= 0:
            return 0.0
        return round(weighted / total_weight, 2)

    @staticmethod
    def weighted_confidence(
        skill_confidences: dict[SkillType, float] | None,
    ) -> float:
        """How well measured this learner is overall, on the same weights.

        Unmeasured skills count as zero here — unlike weighted_overall, where
        skipping them avoids dragging the score down. That difference is the
        point: a learner who has only ever done vocabulary drills is genuinely
        not well measured, and should not be promoted on that evidence.
        """
        if not skill_confidences:
            return 0.0
        total_weight = sum(SKILL_WEIGHTS.values())
        if total_weight <= 0:
            return 0.0
        weighted = sum(
            (skill_confidences.get(skill) or 0.0) * weight
            for skill, weight in SKILL_WEIGHTS.items()
        )
        return round(weighted / total_weight, 3)

    @staticmethod
    def _score_confidence(exercises_completed: int) -> float:
        """How much to trust a skill score, from how often it has been measured.

        This used to count only the exercises in the current request, so it sat
        at 0.02 forever and the "50+ exercises = full confidence" comment next
        to it was never true of any learner.
        """
        if exercises_completed <= 0:
            return 0.0
        return round(min(1.0, exercises_completed / CONFIDENCE_FULL_EXERCISES), 2)

    @staticmethod
    def calculate_overall_level(
        skill_scores: dict[SkillType, float],
        exercises_completed: int,
        lessons_completed: int,
        accuracy: float,
        streak_days: int = 0,
        current_level: ProficiencyLevel = ProficiencyLevel.A1,
        skill_confidences: dict[SkillType, float] | None = None,
    ) -> tuple[ProficiencyLevel, float]:
        """
        Determine user's CEFR level based on skill scores and requirements.

        This is the core algorithm that prevents "XP grinding" to higher levels.
        Users must demonstrate competency in multiple skills to advance.

        Returns:
            Tuple of (level, progress_to_next_level)
        """
        overall_score = ProficiencyService.weighted_overall(skill_scores)
        measured = ProficiencyService.weighted_confidence(skill_confidences)

        # Check each level from highest to lowest to find qualifying level
        qualifying_level = ProficiencyLevel.A1

        for level in reversed(LEVEL_ORDER):
            threshold = LEVEL_THRESHOLDS.get(level)
            if threshold is None:
                continue

            if measured < (threshold.min_skill_confidence or 0.0):
                # Not measured well enough to claim this level yet, however
                # good the scores look.
                continue

            if ProficiencyService._meets_level_requirements(
                level=level,
                skill_scores=skill_scores,
                overall_score=overall_score,
                exercises_completed=exercises_completed,
                lessons_completed=lessons_completed,
                accuracy=accuracy,
                streak_days=streak_days,
            ):
                qualifying_level = level
                break

        # Calculate progress to next level
        next_level = ProficiencyService.get_next_level(qualifying_level)
        if next_level:
            progress = ProficiencyService._calculate_progress_to_level(
                target_level=next_level,
                skill_scores=skill_scores,
                overall_score=overall_score,
                exercises_completed=exercises_completed,
                lessons_completed=lessons_completed,
                accuracy=accuracy,
                streak_days=streak_days,
            )
        else:
            progress = 100.0  # At max level

        return qualifying_level, round(progress, 2)

    @staticmethod
    def _meets_level_requirements(
        level: ProficiencyLevel,
        skill_scores: dict[SkillType, float],
        overall_score: float,
        exercises_completed: int,
        lessons_completed: int,
        accuracy: float,
        streak_days: int,
    ) -> bool:
        """Check if user meets all requirements for a level."""
        threshold = LEVEL_THRESHOLDS.get(level)
        if threshold is None:
            return level == ProficiencyLevel.A1

        # Check skill score requirements
        checks = [
            skill_scores.get(SkillType.VOCABULARY, 0) >= threshold.min_vocabulary_score,
            skill_scores.get(SkillType.GRAMMAR, 0) >= threshold.min_grammar_score,
            skill_scores.get(SkillType.READING, 0) >= threshold.min_reading_score,
            skill_scores.get(SkillType.LISTENING, 0) >= threshold.min_listening_score,
            skill_scores.get(SkillType.SPEAKING, 0) >= threshold.min_speaking_score,
            skill_scores.get(SkillType.WRITING, 0) >= threshold.min_writing_score,
            overall_score >= threshold.min_overall_score,
            exercises_completed >= threshold.min_exercises_completed,
            lessons_completed >= threshold.min_lessons_completed,
            accuracy >= threshold.min_accuracy,
            streak_days >= threshold.min_streak_days,
        ]

        return all(checks)

    @staticmethod
    def _calculate_progress_to_level(
        target_level: ProficiencyLevel,
        skill_scores: dict[SkillType, float],
        overall_score: float,
        exercises_completed: int,
        lessons_completed: int,
        accuracy: float,
        streak_days: int,
    ) -> float:
        """Calculate percentage progress toward meeting a level's requirements."""
        threshold = LEVEL_THRESHOLDS.get(target_level)
        if threshold is None:
            return 0.0

        requirements = [
            (skill_scores.get(SkillType.VOCABULARY, 0), threshold.min_vocabulary_score),
            (skill_scores.get(SkillType.GRAMMAR, 0), threshold.min_grammar_score),
            (skill_scores.get(SkillType.READING, 0), threshold.min_reading_score),
            (skill_scores.get(SkillType.LISTENING, 0), threshold.min_listening_score),
            (skill_scores.get(SkillType.SPEAKING, 0), threshold.min_speaking_score),
            (skill_scores.get(SkillType.WRITING, 0), threshold.min_writing_score),
            (overall_score, threshold.min_overall_score),
            (exercises_completed, threshold.min_exercises_completed),
            (lessons_completed, threshold.min_lessons_completed),
            (accuracy * 100, threshold.min_accuracy * 100),  # Convert to percentage
            (streak_days, threshold.min_streak_days),
        ]

        # Calculate average progress across all requirements
        progress_sum = 0.0
        count = 0

        for current, required in requirements:
            if required > 0:
                progress = min(100, (current / required) * 100)
                progress_sum += progress
                count += 1

        if count == 0:
            return 100.0

        return progress_sum / count

    @staticmethod
    def get_level_requirements_check(
        current_level: ProficiencyLevel,
        skill_scores: dict[SkillType, float],
        exercises_completed: int,
        lessons_completed: int,
        accuracy: float,
        streak_days: int,
        skill_confidences: dict[SkillType, float] | None = None,
    ) -> LevelCheckResponse:
        """
        Check what requirements are met/unmet for the next level.

        This provides detailed feedback to users about what they need
        to work on to advance their level.
        """
        next_level = ProficiencyService.get_next_level(current_level)

        if next_level is None:
            return LevelCheckResponse(
                user_id="",
                current_level=current_level,
                qualifies_for_next=False,
                next_level=None,
                requirements={},
                overall_progress=100.0,
                blockers=[],
            )

        threshold = LEVEL_THRESHOLDS.get(next_level)
        if threshold is None:
            return LevelCheckResponse(
                user_id="",
                current_level=current_level,
                qualifies_for_next=False,
                next_level=next_level,
                requirements={},
                overall_progress=0.0,
                blockers=["Level threshold not defined"],
            )

        # Build requirements dictionary
        requirements = {}
        blockers = []

        # Helper to add requirement check
        def add_req(name: str, current: float, required: float, unit: str = ""):
            met = current >= required
            requirements[name] = {
                "required": f"{required}{unit}",
                "current": f"{round(current, 1)}{unit}",
                "met": met,
                "progress": min(100, (current / required * 100)) if required > 0 else 100,
            }
            if not met:
                blockers.append(f"{name}: need {required}{unit}, have {round(current, 1)}{unit}")

        # Check all requirements
        add_req(
            "Vocabulary Score",
            skill_scores.get(SkillType.VOCABULARY, 0),
            threshold.min_vocabulary_score,
            "%",
        )
        add_req(
            "Grammar Score",
            skill_scores.get(SkillType.GRAMMAR, 0),
            threshold.min_grammar_score,
            "%",
        )

        if threshold.min_reading_score > 0:
            add_req(
                "Reading Score",
                skill_scores.get(SkillType.READING, 0),
                threshold.min_reading_score,
                "%",
            )
        if threshold.min_listening_score > 0:
            add_req(
                "Listening Score",
                skill_scores.get(SkillType.LISTENING, 0),
                threshold.min_listening_score,
                "%",
            )
        if threshold.min_speaking_score > 0:
            add_req(
                "Speaking Score",
                skill_scores.get(SkillType.SPEAKING, 0),
                threshold.min_speaking_score,
                "%",
            )
        if threshold.min_writing_score > 0:
            add_req(
                "Writing Score",
                skill_scores.get(SkillType.WRITING, 0),
                threshold.min_writing_score,
                "%",
            )

        add_req(
            "Overall Score",
            ProficiencyService.weighted_overall(skill_scores),
            threshold.min_overall_score,
            "%",
        )
        add_req("Exercises Completed", exercises_completed, threshold.min_exercises_completed)
        add_req("Lessons Completed", lessons_completed, threshold.min_lessons_completed)
        add_req("Accuracy Rate", accuracy * 100, threshold.min_accuracy * 100, "%")

        if threshold.min_skill_confidence > 0:
            add_req(
                "Skills Measured",
                ProficiencyService.weighted_confidence(skill_confidences) * 100,
                threshold.min_skill_confidence * 100,
                "%",
            )

        if threshold.min_streak_days > 0:
            add_req("Study Streak", streak_days, threshold.min_streak_days, " days")

        # Calculate overall progress
        total_progress = sum(r["progress"] for r in requirements.values()) / len(requirements)

        return LevelCheckResponse(
            user_id="",
            current_level=current_level,
            qualifies_for_next=len(blockers) == 0,
            next_level=next_level,
            requirements=requirements,
            overall_progress=round(total_progress, 1),
            blockers=blockers,
        )

    @staticmethod
    def process_exercise_results(
        profile: ProficiencyProfile,
        results: list[ExerciseResult],
    ) -> ProficiencyAssessmentResult:
        """
        Process exercise results and update proficiency profile.

        This is called after a user completes exercises to update their
        skill scores and potentially their level.
        """
        previous_level = profile.overall_level

        # Group results by skill
        skill_results: dict[SkillType, list[ExerciseResult]] = {}
        for result in results:
            if result.skill not in skill_results:
                skill_results[result.skill] = []
            skill_results[result.skill].append(result)

        # Update each skill score
        skill_updates = {}
        new_skill_scores = {}

        for skill_type in SkillType:
            current_assessment = profile.skills.get(skill_type)
            current_score = (
                current_assessment.score
                if current_assessment and current_assessment.score is not None
                else 0.0
            )

            new_score, confidence = ProficiencyService.calculate_skill_score(
                exercises=results,
                skill=skill_type,
                current_score=current_score,
            )

            skill_updates[skill_type] = {
                "previous_score": current_score,
                "new_score": new_score,
                "change": round(new_score - current_score, 2),
                "confidence": confidence,
            }
            new_skill_scores[skill_type] = new_score

        # Calculate overall level
        # Note: In production, these should come from database
        exercises_completed = profile.assessment_count + len(results)
        lessons_completed = 0  # Would be fetched from DB
        accuracy = sum(1 for r in results if r.is_correct) / max(1, len(results))

        new_level, progress = ProficiencyService.calculate_overall_level(
            skill_scores=new_skill_scores,
            exercises_completed=exercises_completed,
            lessons_completed=lessons_completed,
            accuracy=accuracy,
            current_level=previous_level,
        )

        # Calculate XP (separate from proficiency)
        xp_earned = ProficiencyService._calculate_xp_from_exercises(results)

        # Find weakest skills
        sorted_skills = sorted(new_skill_scores.items(), key=lambda x: x[1])
        weakest_skills = [s[0] for s in sorted_skills[:2]]

        # Get next level requirements
        next_level = ProficiencyService.get_next_level(new_level)

        return ProficiencyAssessmentResult(
            previous_level=previous_level,
            current_level=new_level,
            level_changed=new_level != previous_level,
            skill_updates=skill_updates,
            next_level=next_level,
            progress_to_next_level=progress,
            weakest_skills=weakest_skills,
            recommended_focus=f"Focus on improving your {weakest_skills[0].value} skills"
            if weakest_skills
            else None,
            xp_earned=xp_earned,
            total_xp=profile.total_xp + xp_earned,
        )

    @staticmethod
    def _calculate_xp_from_exercises(results: list[ExerciseResult]) -> int:
        """
        Calculate XP earned from exercises.

        XP is for gamification/rewards and is separate from proficiency.
        This keeps the dopamine hit of earning XP while ensuring level
        progression is based on actual skill.
        """
        total_xp = 0

        for result in results:
            base_xp = 10  # Base XP per exercise

            # Bonus for correct answers
            if result.is_correct:
                base_xp += 5

            # Bonus for higher difficulty
            difficulty_mult = LEVEL_DIFFICULTY_MULTIPLIER.get(result.difficulty_level, 1.0)

            xp = int(base_xp * difficulty_mult)
            total_xp += xp

        return total_xp

    @staticmethod
    def should_suggest_assessment(profile: ProficiencyProfile) -> bool:
        """
        Determine if the user should take a formal level assessment.

        This is suggested when:
        1. Skills suggest they might qualify for next level
        2. Haven't had a formal assessment recently
        3. Significant improvement in scores
        """
        # Check if skills are near next level threshold
        next_level = ProficiencyService.get_next_level(profile.overall_level)

        if not next_level:
            return False

        # Check if last assessment was over a week ago
        if profile.last_full_assessment:
            last_assessment = profile.last_full_assessment
            if last_assessment.tzinfo is None or last_assessment.utcoffset() is None:
                last_assessment = last_assessment.replace(tzinfo=UTC)
            days_since = (datetime.now(UTC) - last_assessment).days
            if days_since < 7:
                return False

        # Check if exercise count is significant
        if profile.assessment_count < 50:
            return False

        # Check if average skill score is close to next level
        avg_score = sum(s.score for s in profile.skills.values()) / max(1, len(profile.skills))
        threshold = LEVEL_THRESHOLDS.get(next_level)

        if threshold and avg_score >= threshold.min_overall_score * 0.85:
            return True

        return False
