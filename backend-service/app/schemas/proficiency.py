"""
Proficiency Assessment Schemas

Advanced level assessment system that evaluates user proficiency based on
multiple skill dimensions rather than just XP accumulation.

CEFR Level Progression Requirements:
- A1 → A2: Basic communication + vocabulary foundation
- A2 → B1: Grammar accuracy + conversational fluency
- B1 → B2: Complex sentence handling + topic variety
- B2 → C1: Advanced grammar + nuanced expression
- C1 → C2: Near-native fluency + academic/professional language
"""

from typing import Optional, List, Dict
from datetime import datetime
from pydantic import BaseModel, Field
from enum import Enum


class SkillType(str, Enum):
    """Core language skill types aligned with CEFR."""
    VOCABULARY = "vocabulary"      # Word knowledge and usage
    GRAMMAR = "grammar"            # Grammatical accuracy
    READING = "reading"            # Reading comprehension
    LISTENING = "listening"        # Listening comprehension
    SPEAKING = "speaking"          # Pronunciation and fluency
    WRITING = "writing"            # Written expression


class ProficiencyLevel(str, Enum):
    """CEFR proficiency levels."""
    A1 = "A1"
    A2 = "A2"
    B1 = "B1"
    B2 = "B2"
    C1 = "C1"
    C2 = "C2"


class SkillAssessment(BaseModel):
    """Assessment result for a single skill."""
    skill: SkillType
    score: float = Field(..., ge=0, le=100, description="Skill score 0-100")
    level: ProficiencyLevel = Field(..., description="Estimated level for this skill")
    confidence: float = Field(..., ge=0, le=1, description="Confidence in assessment 0-1")
    total_exercises: int = Field(default=0, description="Total exercises attempted")
    correct_exercises: int = Field(default=0, description="Correct exercises")
    last_assessed: Optional[datetime] = Field(default=None)
    
    @property
    def accuracy(self) -> float:
        """Calculate accuracy rate."""
        if self.total_exercises == 0:
            return 0.0
        return self.correct_exercises / self.total_exercises


class ProficiencyProfile(BaseModel):
    """
    Comprehensive proficiency profile for a user.
    
    This replaces the simple XP-based level system with a multi-dimensional
    assessment that considers:
    1. Skill-specific scores (vocabulary, grammar, etc.)
    2. Exercise accuracy and consistency
    3. Performance trends over time
    4. Content difficulty mastered
    """
    user_id: str
    
    # Overall level (computed from skill assessments)
    overall_level: ProficiencyLevel = Field(default=ProficiencyLevel.A1)
    overall_score: float = Field(default=0, ge=0, le=100)
    
    # Individual skill assessments
    skills: Dict[SkillType, SkillAssessment] = Field(default_factory=dict)
    
    # XP (for gamification, separate from proficiency)
    total_xp: int = Field(default=0, description="XP for gamification/rewards")
    
    # Assessment metadata
    last_full_assessment: Optional[datetime] = Field(default=None)
    assessment_count: int = Field(default=0)
    
    # Level history
    level_history: List[Dict] = Field(default_factory=list)
    
    class Config:
        from_attributes = True


# =====================
# Level Thresholds
# =====================

class LevelThreshold(BaseModel):
    """
    Requirements to reach and maintain a CEFR level.
    
    Users must meet ALL criteria to be promoted to a level:
    1. Minimum score in each required skill
    2. Sufficient exercise volume (can't skip to C2 with 10 exercises)
    3. Consistent performance (not just lucky streaks)
    """
    level: ProficiencyLevel
    
    # Minimum scores per skill (0-100)
    min_vocabulary_score: float = Field(..., ge=0, le=100)
    min_grammar_score: float = Field(..., ge=0, le=100)
    min_reading_score: float = Field(default=0, ge=0, le=100)
    min_listening_score: float = Field(default=0, ge=0, le=100)
    min_speaking_score: float = Field(default=0, ge=0, le=100)
    min_writing_score: float = Field(default=0, ge=0, le=100)
    
    # Minimum overall score (weighted average of skills)
    min_overall_score: float = Field(..., ge=0, le=100)
    
    # Volume requirements
    min_exercises_completed: int = Field(..., description="Minimum exercises to qualify")
    min_lessons_completed: int = Field(..., description="Minimum lessons to qualify")
    
    # Consistency requirements
    min_accuracy: float = Field(..., ge=0, le=1, description="Minimum accuracy rate")
    min_streak_days: int = Field(default=0, description="Minimum consecutive study days")


# Default level thresholds
LEVEL_THRESHOLDS = {
    ProficiencyLevel.A1: LevelThreshold(
        level=ProficiencyLevel.A1,
        min_vocabulary_score=0,
        min_grammar_score=0,
        min_overall_score=0,
        min_exercises_completed=0,
        min_lessons_completed=0,
        min_accuracy=0.0,
    ),
    ProficiencyLevel.A2: LevelThreshold(
        level=ProficiencyLevel.A2,
        min_vocabulary_score=60,
        min_grammar_score=55,
        min_overall_score=55,
        min_exercises_completed=100,
        min_lessons_completed=10,
        min_accuracy=0.6,
    ),
    ProficiencyLevel.B1: LevelThreshold(
        level=ProficiencyLevel.B1,
        min_vocabulary_score=70,
        min_grammar_score=65,
        min_reading_score=60,
        min_listening_score=55,
        min_overall_score=65,
        min_exercises_completed=300,
        min_lessons_completed=30,
        min_accuracy=0.65,
        min_streak_days=7,
    ),
    ProficiencyLevel.B2: LevelThreshold(
        level=ProficiencyLevel.B2,
        min_vocabulary_score=75,
        min_grammar_score=75,
        min_reading_score=70,
        min_listening_score=65,
        min_speaking_score=60,
        min_overall_score=72,
        min_exercises_completed=600,
        min_lessons_completed=60,
        min_accuracy=0.70,
        min_streak_days=14,
    ),
    ProficiencyLevel.C1: LevelThreshold(
        level=ProficiencyLevel.C1,
        min_vocabulary_score=85,
        min_grammar_score=85,
        min_reading_score=80,
        min_listening_score=75,
        min_speaking_score=75,
        min_writing_score=70,
        min_overall_score=80,
        min_exercises_completed=1200,
        min_lessons_completed=120,
        min_accuracy=0.80,
        min_streak_days=30,
    ),
    ProficiencyLevel.C2: LevelThreshold(
        level=ProficiencyLevel.C2,
        min_vocabulary_score=95,
        min_grammar_score=95,
        min_reading_score=90,
        min_listening_score=90,
        min_speaking_score=90,
        min_writing_score=85,
        min_overall_score=90,
        min_exercises_completed=2500,
        min_lessons_completed=250,
        min_accuracy=0.90,
        min_streak_days=60,
    ),
}


# =====================
# Assessment Requests/Responses
# =====================

class ExerciseResult(BaseModel):
    """Result of a single exercise for proficiency tracking."""
    exercise_type: str = Field(..., description="Type of exercise (vocab, grammar, etc.)")
    skill: SkillType
    difficulty_level: ProficiencyLevel = Field(..., description="CEFR level of the exercise")
    is_correct: bool
    score: float = Field(..., ge=0, le=100, description="Score 0-100")
    time_spent_seconds: int = Field(default=0)
    
    # Optional context
    lesson_id: Optional[str] = None
    course_id: Optional[str] = None


class UpdateProficiencyRequest(BaseModel):
    """Request to update proficiency based on exercise results."""
    user_id: str
    results: List[ExerciseResult]


class ProficiencyAssessmentResult(BaseModel):
    """Result of proficiency assessment after exercises."""
    previous_level: ProficiencyLevel
    current_level: ProficiencyLevel
    level_changed: bool = Field(default=False)
    
    # Skill breakdown
    skill_updates: Dict[SkillType, Dict] = Field(default_factory=dict)
    
    # Progress toward next level
    next_level: Optional[ProficiencyLevel] = None
    progress_to_next_level: float = Field(default=0, ge=0, le=100)
    requirements_met: Dict[str, bool] = Field(default_factory=dict)
    
    # Recommendations
    weakest_skills: List[SkillType] = Field(default_factory=list)
    recommended_focus: Optional[str] = None
    
    # Gamification (separate from proficiency)
    xp_earned: int = Field(default=0)
    total_xp: int = Field(default=0)


class LevelAssessmentRequest(BaseModel):
    """Request for a formal level assessment test."""
    user_id: str
    assessment_type: str = Field(default="quick", description="'quick' or 'comprehensive'")


class LevelCheckResponse(BaseModel):
    """Response for checking if user qualifies for level up."""
    user_id: str
    current_level: ProficiencyLevel
    
    # Qualification for next level
    qualifies_for_next: bool = Field(default=False)
    next_level: Optional[ProficiencyLevel] = None
    
    # Detailed requirements check
    requirements: Dict[str, Dict] = Field(
        default_factory=dict,
        description="Requirement name -> {required, current, met}"
    )
    
    # Percentage of requirements met
    overall_progress: float = Field(default=0, ge=0, le=100)
    
    # What's blocking level up
    blockers: List[str] = Field(default_factory=list)
