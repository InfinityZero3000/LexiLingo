"""
Content Auto-Generation (CAG) API Routes

Endpoints for generating adaptive learning content
"""

from fastapi import APIRouter, HTTPException, Depends
from typing import Optional, List
from pydantic import BaseModel, Field

from api.services.cag_service import ContentAutoGenerator


router = APIRouter()
cag = ContentAutoGenerator()


# ============================================================
# Request/Response Models
# ============================================================

class GenerateVocabularyRequest(BaseModel):
    level: str = Field(..., description="User level (A1-C2)")
    topic: Optional[str] = Field(None, description="Topic (optional)")
    count: int = Field(10, description="Number of words", ge=1, le=50)
    error_patterns: Optional[List[str]] = Field(None, description="Error patterns to focus on")


class GenerateGrammarRequest(BaseModel):
    level: str = Field(..., description="User level (A1-C2)")
    grammar_point: Optional[str] = Field(None, description="Specific grammar point")
    error_patterns: Optional[List[str]] = Field(None, description="User's common errors")
    count: int = Field(10, description="Number of exercises", ge=1, le=30)


class GenerateConversationRequest(BaseModel):
    level: str = Field(..., description="User level (A1-C2)")
    topic: Optional[str] = Field(None, description="Conversation topic")
    scenario: Optional[str] = Field(None, description="Specific scenario")


class GenerateReadingRequest(BaseModel):
    level: str = Field(..., description="User level (A1-C2)")
    topic: Optional[str] = Field(None, description="Reading topic")
    length: str = Field("medium", description="Passage length (short/medium/long)")


class GenerateWritingRequest(BaseModel):
    level: str = Field(..., description="User level (A1-C2)")
    writing_type: str = Field("essay", description="Type of writing (essay/email/letter/story)")
    topic: Optional[str] = Field(None, description="Writing topic")


class GeneratePronunciationRequest(BaseModel):
    level: str = Field(..., description="User level (A1-C2)")
    focus: Optional[str] = Field(None, description="Focus area (phoneme/stress/intonation)")
    error_patterns: Optional[List[str]] = Field(None, description="Common pronunciation errors")


class GeneratePersonalizedLessonRequest(BaseModel):
    user_id: str = Field(..., description="User ID")
    user_level: str = Field(..., description="Current level")
    error_patterns: List[str] = Field(default_factory=list, description="Common errors")
    interests: List[str] = Field(default_factory=list, description="User interests")
    learning_history: dict = Field(default_factory=dict, description="Past performance")


# ============================================================
# Vocabulary Generation
# ============================================================

@router.post("/vocabulary", summary="Generate Vocabulary Exercise")
async def generate_vocabulary(request: GenerateVocabularyRequest):
    """
    Generate a vocabulary exercise with words, definitions, examples, and fill-in-the-blank tasks.
    
    **Use cases:**
    - Generate vocabulary list for a specific level and topic
    - Create exercises focusing on error patterns
    - Adaptive vocabulary building based on user needs
    
    **Example:**
    ```json
    {
      "level": "B1",
      "topic": "business",
      "count": 10,
      "error_patterns": ["vocabulary_range"]
    }
    ```
    """
    try:
        exercise = cag.generate_vocabulary_exercise(
            level=request.level,
            topic=request.topic,
            count=request.count,
            error_patterns=request.error_patterns
        )
        return exercise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to generate vocabulary: {str(e)}")


# ============================================================
# Grammar Generation
# ============================================================

@router.post("/grammar", summary="Generate Grammar Drill")
async def generate_grammar(request: GenerateGrammarRequest):
    """
    Generate a grammar drill focused on specific grammar points or error patterns.
    
    **Use cases:**
    - Practice specific grammar rules
    - Address common grammar mistakes
    - Progressive grammar learning
    
    **Example:**
    ```json
    {
      "level": "A2",
      "grammar_point": "past_simple",
      "error_patterns": ["tense_confusion"],
      "count": 15
    }
    ```
    """
    try:
        drill = cag.generate_grammar_drill(
            level=request.level,
            grammar_point=request.grammar_point,
            error_patterns=request.error_patterns,
            count=request.count
        )
        return drill
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to generate grammar drill: {str(e)}")


# ============================================================
# Conversation Generation
# ============================================================

@router.post("/conversation", summary="Generate Conversation Prompt")
async def generate_conversation(request: GenerateConversationRequest):
    """
    Generate a conversation prompt with role-play scenario for practice.
    
    **Use cases:**
    - Practice real-life conversations
    - Scenario-based learning (restaurant, job interview, etc.)
    - Improve speaking fluency
    
    **Example:**
    ```json
    {
      "level": "B1",
      "topic": "travel",
      "scenario": "hotel_checkin"
    }
    ```
    """
    try:
        prompt = cag.generate_conversation_prompt(
            level=request.level,
            topic=request.topic,
            scenario=request.scenario
        )
        return prompt
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to generate conversation: {str(e)}")


# ============================================================
# Reading Generation
# ============================================================

@router.post("/reading", summary="Generate Reading Passage")
async def generate_reading(request: GenerateReadingRequest):
    """
    Generate a reading passage with comprehension questions.
    
    **Use cases:**
    - Reading comprehension practice
    - Topic-based reading materials
    - Vocabulary in context
    
    **Example:**
    ```json
    {
      "level": "B2",
      "topic": "technology",
      "length": "medium"
    }
    ```
    """
    try:
        passage = cag.generate_reading_passage(
            level=request.level,
            topic=request.topic,
            length=request.length
        )
        return passage
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to generate reading: {str(e)}")


# ============================================================
# Writing Generation
# ============================================================

@router.post("/writing", summary="Generate Writing Prompt")
async def generate_writing(request: GenerateWritingRequest):
    """
    Generate a writing prompt with guidelines and structure.
    
    **Use cases:**
    - Writing practice (essays, emails, letters)
    - Structured writing assignments
    - Academic/business writing
    
    **Example:**
    ```json
    {
      "level": "C1",
      "writing_type": "essay",
      "topic": "climate_change"
    }
    ```
    """
    try:
        prompt = cag.generate_writing_prompt(
            level=request.level,
            writing_type=request.writing_type,
            topic=request.topic
        )
        return prompt
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to generate writing prompt: {str(e)}")


# ============================================================
# Pronunciation Generation
# ============================================================

@router.post("/pronunciation", summary="Generate Pronunciation Exercise")
async def generate_pronunciation(request: GeneratePronunciationRequest):
    """
    Generate a pronunciation exercise focusing on specific sounds or patterns.
    
    **Use cases:**
    - Practice difficult phonemes
    - Word stress and intonation training
    - Accent reduction
    
    **Example:**
    ```json
    {
      "level": "A2",
      "focus": "phoneme",
      "error_patterns": ["th_sound"]
    }
    ```
    """
    try:
        exercise = cag.generate_pronunciation_exercise(
            level=request.level,
            focus=request.focus,
            error_patterns=request.error_patterns
        )
        return exercise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to generate pronunciation: {str(e)}")


# ============================================================
# Personalized Lesson Generation
# ============================================================

@router.post("/personalized-lesson", summary="Generate Personalized Lesson")
async def generate_personalized_lesson(request: GeneratePersonalizedLessonRequest):
    """
    Generate a complete personalized lesson based on user profile, error patterns, and interests.
    
    **This is the MAIN endpoint for adaptive learning!**
    
    Combines multiple content types:
    - Grammar drills (if errors detected)
    - Vocabulary exercises (based on interests)
    - Conversation prompts (contextual)
    - Reading passages (level-appropriate)
    
    **Use cases:**
    - Daily personalized lessons
    - Adaptive curriculum generation
    - Error-focused practice
    - Interest-based learning
    
    **Example:**
    ```json
    {
      "user_id": "user123",
      "user_level": "B1",
      "error_patterns": ["past_tense", "articles"],
      "interests": ["travel", "food", "technology"],
      "learning_history": {
        "grammar_accuracy": 0.75,
        "vocabulary_progress": 0.82,
        "recent_topics": ["travel", "business"]
      }
    }
    ```
    """
    try:
        lesson = cag.generate_personalized_lesson(
            user_id=request.user_id,
            user_level=request.user_level,
            error_patterns=request.error_patterns,
            interests=request.interests,
            learning_history=request.learning_history
        )
        return lesson
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to generate personalized lesson: {str(e)}")


# ============================================================
# Batch Generation
# ============================================================

class GenerateBatchRequest(BaseModel):
    level: str = Field(..., description="User level (A1-C2)")
    types: List[str] = Field(..., description="Content types to generate (vocabulary, grammar, conversation, reading, writing, pronunciation)")
    topic: Optional[str] = Field(None, description="Topic (optional)")


@router.post("/batch", summary="Generate Multiple Content Types")
async def generate_batch(request: GenerateBatchRequest):
    """
    Generate multiple content types in one request.
    
    **Use cases:**
    - Create a complete lesson package
    - Generate variety of exercises at once
    
    **Example:**
    ```json
    {
      "level": "B1",
      "types": ["vocabulary", "grammar", "conversation"],
      "topic": "travel"
    }
    ```
    """
    try:
        results = {}
        
        if "vocabulary" in request.types:
            results["vocabulary"] = cag.generate_vocabulary_exercise(request.level, request.topic)
        
        if "grammar" in request.types:
            results["grammar"] = cag.generate_grammar_drill(request.level)
        
        if "conversation" in request.types:
            results["conversation"] = cag.generate_conversation_prompt(request.level, request.topic)
        
        if "reading" in request.types:
            results["reading"] = cag.generate_reading_passage(request.level, request.topic)
        
        if "writing" in request.types:
            results["writing"] = cag.generate_writing_prompt(request.level, topic=request.topic)
        
        if "pronunciation" in request.types:
            results["pronunciation"] = cag.generate_pronunciation_exercise(request.level)
        
        return {
            "level": request.level,
            "topic": request.topic,
            "content": results
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to generate batch: {str(e)}")


# ============================================================
# Health Check
# ============================================================

@router.get("/health", summary="CAG Health Check")
async def cag_health():
    """Check if CAG service is operational."""
    return {
        "status": "healthy",
        "service": "Content Auto-Generation (CAG)",
        "features": [
            "vocabulary_generation",
            "grammar_drills",
            "conversation_prompts",
            "reading_passages",
            "writing_prompts",
            "pronunciation_exercises",
            "personalized_lessons"
        ]
    }
