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

from typing import Optional, List, Dict, Tuple
from datetime import datetime, timedelta
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, and_

from app.schemas.proficiency import (
    SkillType,
    ProficiencyLevel,
    SkillAssessment,
    ProficiencyProfile,
    LevelThreshold,
    LEVEL_THRESHOLDS,
    ExerciseResult,
    ProficiencyAssessmentResult,
    LevelCheckResponse,
)


# Skill weights for overall score calculation
SKILL_WEIGHTS = {
    SkillType.VOCABULARY: 0.25,
    SkillType.GRAMMAR: 0.25,
    SkillType.READING: 0.15,
    SkillType.LISTENING: 0.15,
    SkillType.SPEAKING: 0.10,
    SkillType.WRITING: 0.10,
}

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


class ProficiencyService:
    """Service for calculating and managing user proficiency."""
    
    @staticmethod
    def get_level_index(level: ProficiencyLevel) -> int:
        """Get numeric index of level (0 = A1, 5 = C2)."""
        return LEVEL_ORDER.index(level)
    
    @staticmethod
    def get_next_level(level: ProficiencyLevel) -> Optional[ProficiencyLevel]:
        """Get the next level, or None if at C2."""
        idx = LEVEL_ORDER.index(level)
        if idx >= len(LEVEL_ORDER) - 1:
            return None
        return LEVEL_ORDER[idx + 1]
    
    @staticmethod
    def get_previous_level(level: ProficiencyLevel) -> Optional[ProficiencyLevel]:
        """Get the previous level, or None if at A1."""
        idx = LEVEL_ORDER.index(level)
        if idx <= 0:
            return None
        return LEVEL_ORDER[idx - 1]
    
    @staticmethod
    def calculate_skill_score(
        exercises: List[ExerciseResult],
        skill: SkillType,
        current_score: float = 0,
        decay_factor: float = 0.95
    ) -> Tuple[float, float]:
        """
        Calculate updated skill score using Exponential Moving Average (EMA).
        
        This gives more weight to recent exercises while still considering
        historical performance. Exercises at higher difficulty levels
        contribute more to the score.
        
        Args:
            exercises: List of exercise results for this skill
            skill: The skill type being assessed
            current_score: Current skill score (0-100)
            decay_factor: How much to weight historical score (0.95 = 95% history)
            
        Returns:
            Tuple of (new_score, confidence)
        """
        if not exercises:
            return current_score, 0.0
        
        # Filter exercises for this skill
        skill_exercises = [e for e in exercises if e.skill == skill]
        if not skill_exercises:
            return current_score, 0.0
        
        # Calculate weighted average of new exercise scores
        total_weight = 0.0
        weighted_sum = 0.0
        
        for exercise in skill_exercises:
            # Weight by difficulty level
            difficulty_mult = LEVEL_DIFFICULTY_MULTIPLIER.get(
                exercise.difficulty_level, 1.0
            )
            
            # Correct answers at higher difficulty worth more
            weight = difficulty_mult
            
            # Add bonus for being correct at user's level or above
            if exercise.is_correct:
                # Score contribution (0-100 range)
                score_contribution = exercise.score * (1 + 0.1 * difficulty_mult)
            else:
                # Incorrect answers still contribute but less
                score_contribution = exercise.score * 0.5
            
            weighted_sum += score_contribution * weight
            total_weight += weight
        
        if total_weight == 0:
            return current_score, 0.0
        
        # New score from recent exercises
        new_exercise_score = weighted_sum / total_weight
        
        # Blend with historical score using EMA
        if current_score > 0:
            final_score = (decay_factor * current_score) + ((1 - decay_factor) * new_exercise_score)
        else:
            # First time scoring this skill
            final_score = new_exercise_score
        
        # Clamp to valid range
        final_score = max(0, min(100, final_score))
        
        # Calculate confidence based on number of exercises
        # More exercises = higher confidence
        confidence = min(1.0, len(skill_exercises) / 50)  # 50+ exercises = full confidence
        
        return round(final_score, 2), round(confidence, 2)
    
    @staticmethod
    def calculate_overall_level(
        skill_scores: Dict[SkillType, float],
        exercises_completed: int,
        lessons_completed: int,
        accuracy: float,
        streak_days: int = 0,
        current_level: ProficiencyLevel = ProficiencyLevel.A1
    ) -> Tuple[ProficiencyLevel, float]:
        """
        Determine user's CEFR level based on skill scores and requirements.
        
        This is the core algorithm that prevents "XP grinding" to higher levels.
        Users must demonstrate competency in multiple skills to advance.
        
        Returns:
            Tuple of (level, progress_to_next_level)
        """
        # Calculate weighted overall score
        overall_score = 0.0
        total_weight = 0.0
        
        for skill, weight in SKILL_WEIGHTS.items():
            if skill in skill_scores:
                overall_score += skill_scores[skill] * weight
                total_weight += weight
        
        if total_weight > 0:
            overall_score = overall_score / total_weight * sum(SKILL_WEIGHTS.values())
        
        # Check each level from highest to lowest to find qualifying level
        qualifying_level = ProficiencyLevel.A1
        
        for level in reversed(LEVEL_ORDER):
            threshold = LEVEL_THRESHOLDS.get(level)
            if threshold is None:
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
        skill_scores: Dict[SkillType, float],
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
        skill_scores: Dict[SkillType, float],
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
        skill_scores: Dict[SkillType, float],
        exercises_completed: int,
        lessons_completed: int,
        accuracy: float,
        streak_days: int,
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
        add_req("Vocabulary Score", skill_scores.get(SkillType.VOCABULARY, 0), 
                threshold.min_vocabulary_score, "%")
        add_req("Grammar Score", skill_scores.get(SkillType.GRAMMAR, 0), 
                threshold.min_grammar_score, "%")
        
        if threshold.min_reading_score > 0:
            add_req("Reading Score", skill_scores.get(SkillType.READING, 0), 
                    threshold.min_reading_score, "%")
        if threshold.min_listening_score > 0:
            add_req("Listening Score", skill_scores.get(SkillType.LISTENING, 0), 
                    threshold.min_listening_score, "%")
        if threshold.min_speaking_score > 0:
            add_req("Speaking Score", skill_scores.get(SkillType.SPEAKING, 0), 
                    threshold.min_speaking_score, "%")
        if threshold.min_writing_score > 0:
            add_req("Writing Score", skill_scores.get(SkillType.WRITING, 0), 
                    threshold.min_writing_score, "%")
        
        add_req("Overall Score", sum(skill_scores.values()) / max(1, len(skill_scores)), 
                threshold.min_overall_score, "%")
        add_req("Exercises Completed", exercises_completed, threshold.min_exercises_completed)
        add_req("Lessons Completed", lessons_completed, threshold.min_lessons_completed)
        add_req("Accuracy Rate", accuracy * 100, threshold.min_accuracy * 100, "%")
        
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
        results: List[ExerciseResult],
    ) -> ProficiencyAssessmentResult:
        """
        Process exercise results and update proficiency profile.
        
        This is called after a user completes exercises to update their
        skill scores and potentially their level.
        """
        previous_level = profile.overall_level
        
        # Group results by skill
        skill_results: Dict[SkillType, List[ExerciseResult]] = {}
        for result in results:
            if result.skill not in skill_results:
                skill_results[result.skill] = []
            skill_results[result.skill].append(result)
        
        # Update each skill score
        skill_updates = {}
        new_skill_scores = {}
        
        for skill_type in SkillType:
            current_assessment = profile.skills.get(skill_type)
            current_score = current_assessment.score if current_assessment else 0.0
            
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
            recommended_focus=f"Focus on improving your {weakest_skills[0].value} skills" if weakest_skills else None,
            xp_earned=xp_earned,
            total_xp=profile.total_xp + xp_earned,
        )
    
    @staticmethod
    def _calculate_xp_from_exercises(results: List[ExerciseResult]) -> int:
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
            difficulty_mult = LEVEL_DIFFICULTY_MULTIPLIER.get(
                result.difficulty_level, 1.0
            )
            
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
        current_idx = ProficiencyService.get_level_index(profile.overall_level)
        next_level = ProficiencyService.get_next_level(profile.overall_level)
        
        if not next_level:
            return False
        
        # Check if last assessment was over a week ago
        if profile.last_full_assessment:
            days_since = (datetime.now() - profile.last_full_assessment).days
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
