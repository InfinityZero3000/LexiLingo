"""Admin routes — seed data, system info, and quota monitoring."""
from typing import Optional, List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_admin, get_current_super_admin
from app.models.user import User
from app.models.course import Course, Unit, Lesson
from app.models.course_category import CourseCategory
from app.models.vocabulary import VocabularyItem
from app.models.gamification import Achievement, ShopItem
from app.models.content import GrammarItem, QuestionItem, TestExam
from app.schemas.response import ApiResponse

router = APIRouter(prefix="/admin", tags=["Admin"])

require_admin = get_current_admin
require_super_admin = get_current_super_admin

# ============================================================================
# Seed Data Endpoint (Development Only)
# ============================================================================

@router.post("/seed", response_model=ApiResponse[dict])
async def seed_sample_data(
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    Seed sample data for development/testing.
    
    Creates sample achievements, shop items, course categories, and courses.
    Admin only endpoint.
    """
    created = {
        "achievements": 0,
        "shop_items": 0,
        "course_categories": 0,
        "courses": 0,
        "units": 0,
        "lessons": 0,
    }
    
    # Sample Achievements
    sample_achievements = [
        {"name": "First Steps", "description": "Complete your first lesson", 
         "condition_type": "lessons_completed", "condition_value": 1, 
         "category": "lessons", "rarity": "common", "xp_reward": 10, "gems_reward": 5},
        {"name": "Week Warrior", "description": "Maintain a 7-day streak", 
         "condition_type": "streak_days", "condition_value": 7, 
         "category": "streak", "rarity": "rare", "xp_reward": 50, "gems_reward": 20},
        {"name": "Word Collector", "description": "Add 100 words to vocabulary", 
         "condition_type": "vocab_count", "condition_value": 100, 
         "category": "vocabulary", "rarity": "epic", "xp_reward": 100, "gems_reward": 50},
        {"name": "Social Butterfly", "description": "Follow 10 friends", 
         "condition_type": "following_count", "condition_value": 10, 
         "category": "social", "rarity": "rare", "xp_reward": 30, "gems_reward": 15},
    ]
    
    for ach_data in sample_achievements:
        # Check if exists
        result = await db.execute(
            select(Achievement).where(Achievement.name == ach_data["name"])
        )
        if not result.scalar_one_or_none():
            achievement = Achievement(**ach_data)
            db.add(achievement)
            created["achievements"] += 1
    
    # Sample Shop Items
    from app.core.shop_catalog import SHOP_CATALOG
    sample_shop_items = SHOP_CATALOG
    
    for item_data in sample_shop_items:
        # Check if exists
        result = await db.execute(
            select(ShopItem).where(ShopItem.name == item_data["name"])
        )
        existing_item = result.scalar_one_or_none()
        if not existing_item:
            item = ShopItem(**item_data)
            db.add(item)
            created["shop_items"] += 1
        else:
            for field, value in item_data.items():
                setattr(existing_item, field, value)

    # Sample Course Categories
    sample_categories = [
        {
            "name": "Grammar",
            "slug": "grammar",
            "description": "Master English grammar rules and structures",
            "icon": "📚",
            "color": "#4CAF50",
            "order_index": 1,
        },
        {
            "name": "Vocabulary",
            "slug": "vocabulary",
            "description": "Build practical English vocabulary for daily use",
            "icon": "🧠",
            "color": "#2196F3",
            "order_index": 2,
        },
    ]

    category_ids: dict[str, UUID] = {}
    for category_data in sample_categories:
        result = await db.execute(
            select(CourseCategory).where(CourseCategory.slug == category_data["slug"])
        )
        category = result.scalar_one_or_none()
        if not category:
            category = CourseCategory(**category_data)
            db.add(category)
            await db.flush()
            created["course_categories"] += 1
        category_ids[category_data["slug"]] = category.id

    # Sample published courses with basic roadmap content
    sample_courses = [
        {
            "title": "English Grammar Foundations",
            "description": "Start with core grammar patterns for everyday communication.",
            "language": "en",
            "level": "A1",
            "category_slug": "grammar",
            "tags": ["grammar", "beginner", "fundamentals"],
            "total_xp": 120,
            "estimated_duration": 90,
            "thumbnail_url": "https://images.unsplash.com/photo-1456513080510-7bf3a84b82f8",
            "units": [
                {
                    "title": "Present Simple Basics",
                    "description": "Build confidence with daily routine sentences.",
                    "order_index": 1,
                    "background_color": "#1E3A8A",
                    "lessons": [
                        {
                            "title": "I/You/We/They + Verb",
                            "description": "Form positive present simple sentences.",
                            "order_index": 1,
                            "estimated_minutes": 12,
                            "xp_reward": 20,
                            "total_exercises": 10,
                            "exercises": [
                                {
                                    "id": "ex_g1_1",
                                    "type": "multiple_choice",
                                    "ui_type": "multiple_choice",
                                    "question": "Choose the correct form: 'I ___ coffee every morning.'",
                                    "options": [{"id": "0", "text": "drink", "is_correct": True}, {"id": "1", "text": "drinks", "is_correct": False}, {"id": "2", "text": "drinking", "is_correct": False}, {"id": "3", "text": "drunk", "is_correct": False}],
                                    "correct_answer": "drink",
                                    "explanation": "With I/You/We/They, use the base verb form."
                                },
                                {
                                    "id": "ex_g1_2",
                                    "type": "true_false",
                                    "ui_type": "true_or_false",
                                    "question": "True or False: 'They plays football' is grammatically correct.",
                                    "options": [{"id": "0", "text": "True", "is_correct": False}, {"id": "1", "text": "False", "is_correct": True}],
                                    "correct_answer": "False",
                                    "explanation": "'They' is plural and takes the base verb 'play', not 'plays'."
                                },
                                {
                                    "id": "ex_g1_3",
                                    "type": "fill_blank",
                                    "ui_type": "fill_in_the_blank",
                                    "question": "Complete the sentence: 'We {blank} in a big city.'",
                                    "correct_answer": "live",
                                    "explanation": "'We' takes the base verb 'live'."
                                },
                                {
                                    "id": "ex_g1_4",
                                    "type": "reorder",
                                    "ui_type": "arrange_the_sentence",
                                    "question": "Arrange: 'day / every / study / they'",
                                    "options": [{"id": "0", "text": "they"}, {"id": "1", "text": "study"}, {"id": "2", "text": "every"}, {"id": "3", "text": "day"}],
                                    "correct_answer": "they study every day",
                                    "explanation": "Subject + Verb + Time expression is the standard structure."
                                },
                                {
                                    "id": "ex_g1_5",
                                    "type": "translate",
                                    "ui_type": "translation_choice",
                                    "question": "Choose the translation for: 'Chúng tôi muốn học.'",
                                    "options": [{"id": "0", "text": "We want to learn.", "is_correct": True}, {"id": "1", "text": "We wants to learn.", "is_correct": False}, {"id": "2", "text": "We learning.", "is_correct": False}],
                                    "correct_answer": "We want to learn.",
                                    "explanation": "'Chúng tôi' translates to 'We', which takes the base verb 'want'."
                                },
                                {
                                    "id": "ex_g1_6",
                                    "type": "fill_blank",
                                    "ui_type": "dialogue_completion",
                                    "question": "A: Do you speak English? B: Yes, I {blank}.",
                                    "correct_answer": "do",
                                    "explanation": "Short answer to 'Do you...' is 'I do'."
                                },
                                {
                                    "id": "ex_g1_7",
                                    "type": "multiple_choice",
                                    "ui_type": "collocation_choice",
                                    "question": "Complete the phrase: 'They ___ homework together.'",
                                    "options": [{"id": "0", "text": "do", "is_correct": True}, {"id": "1", "text": "make", "is_correct": False}],
                                    "correct_answer": "do",
                                    "explanation": "The collocation is 'do homework'."
                                },
                                {
                                    "id": "ex_g1_8",
                                    "type": "fill_blank",
                                    "ui_type": "dictation",
                                    "question": "Listen and write what you hear: '{blank}'",
                                    "correct_answer": "We go home",
                                    "explanation": "Type the exact words heard in the audio."
                                },
                                {
                                    "id": "ex_g1_9",
                                    "type": "translate",
                                    "ui_type": "speaking_repeat",
                                    "question": "Repeat: 'I listen to music.'",
                                    "correct_answer": "I listen to music",
                                    "explanation": "Record yourself repeating this sentence."
                                },
                                {
                                    "id": "ex_g1_10",
                                    "type": "multiple_choice",
                                    "ui_type": "vocabulary_flashcard",
                                    "question": "Learn the card: 'Routine'",
                                    "options": [{"id": "0", "text": "Got it!", "is_correct": True}],
                                    "correct_answer": "Got it!",
                                    "explanation": "Routine is a sequence of actions regularly followed."
                                }
                            ]
                        },
                        {
                            "title": "He/She/It + Verb-s",
                            "description": "Use third-person singular correctly.",
                            "order_index": 2,
                            "estimated_minutes": 12,
                            "xp_reward": 20,
                            "total_exercises": 10,
                            "exercises": [
                                {
                                    "id": "ex_g2_1",
                                    "type": "multiple_choice",
                                    "ui_type": "multiple_choice",
                                    "question": "Choose correct: 'He ___ to school by bus.'",
                                    "options": [{"id": "0", "text": "go", "is_correct": False}, {"id": "1", "text": "goes", "is_correct": True}, {"id": "2", "text": "going", "is_correct": False}],
                                    "correct_answer": "goes",
                                    "explanation": "He/she/it takes verb+s/es."
                                },
                                {
                                    "id": "ex_g2_2",
                                    "type": "true_false",
                                    "ui_type": "true_or_false",
                                    "question": "True or False: 'It rain a lot' is correct.",
                                    "options": [{"id": "0", "text": "True", "is_correct": False}, {"id": "1", "text": "False", "is_correct": True}],
                                    "correct_answer": "False",
                                    "explanation": "It should be 'It rains a lot'."
                                },
                                {
                                    "id": "ex_g2_3",
                                    "type": "fill_blank",
                                    "ui_type": "fill_in_the_blank",
                                    "question": "Complete: 'She {blank} the piano well.'",
                                    "correct_answer": "plays",
                                    "explanation": "She requires plays."
                                },
                                {
                                    "id": "ex_g2_4",
                                    "type": "fill_blank",
                                    "ui_type": "grammar_correction",
                                    "question": "Correct the error: 'He play tennis.' -> '{blank}'",
                                    "correct_answer": "He plays tennis",
                                    "explanation": "Add 's' to play."
                                },
                                {
                                    "id": "ex_g2_5",
                                    "type": "multiple_choice",
                                    "ui_type": "image_based_choice",
                                    "question": "Choose the image that represents: 'She runs.'",
                                    "options": [{"id": "0", "text": "Running", "is_correct": True}, {"id": "1", "text": "Sleeping", "is_correct": False}],
                                    "correct_answer": "Running",
                                    "explanation": "Select the correct action card."
                                },
                                {
                                    "id": "ex_g2_6",
                                    "type": "multiple_choice",
                                    "ui_type": "listen_and_choose",
                                    "question": "Listen and select what he does.",
                                    "options": [{"id": "0", "text": "He eats breakfast", "is_correct": True}, {"id": "1", "text": "He plays games", "is_correct": False}],
                                    "correct_answer": "He eats breakfast",
                                    "explanation": "Audio matches breakfast."
                                },
                                {
                                    "id": "ex_g2_7",
                                    "type": "translate",
                                    "ui_type": "pronunciation_practice",
                                    "question": "Practice speaking: 'He plays tennis.'",
                                    "correct_answer": "He plays tennis",
                                    "explanation": "Evaluate pronunciation of He plays tennis."
                                },
                                {
                                    "id": "ex_g2_8",
                                    "type": "multiple_choice",
                                    "ui_type": "reading_comprehension",
                                    "question": "Read and answer: 'Tom is a chef. He works in a restaurant.' Where does Tom work?",
                                    "options": [{"id": "0", "text": "restaurant", "is_correct": True}, {"id": "1", "text": "office", "is_correct": False}],
                                    "correct_answer": "restaurant",
                                    "explanation": "The text states he works in a restaurant."
                                },
                                {
                                    "id": "ex_g2_9",
                                    "type": "fill_blank",
                                    "ui_type": "short_writing_answer",
                                    "question": "Write in English: 'Cô ấy nói tiếng Anh.'",
                                    "correct_answer": "She speaks English",
                                    "explanation": "Translate exactly."
                                },
                                {
                                    "id": "ex_g2_10",
                                    "type": "matching",
                                    "ui_type": "categorization",
                                    "question": "Categorize the pronouns: Singular vs Plural",
                                    "options": [{"id": "he", "text": "Singular"}, {"id": "they", "text": "Plural"}],
                                    "correct_answer": "he:Singular, they:Plural",
                                    "explanation": "He is singular, they is plural."
                                }
                            ]
                        },
                    ],
                },
            ],
        },
        {
            "title": "Daily Vocabulary Starter",
            "description": "Learn essential words and phrases for daily life.",
            "language": "en",
            "level": "A1",
            "category_slug": "vocabulary",
            "tags": ["vocabulary", "daily-life", "beginner"],
            "total_xp": 120,
            "estimated_duration": 80,
            "thumbnail_url": "https://images.unsplash.com/photo-1434030216411-0b793f4b4173",
            "units": [
                {
                    "title": "Home and Family",
                    "description": "Words you use every day at home.",
                    "order_index": 1,
                    "background_color": "#0F766E",
                    "lessons": [
                        {
                            "title": "Family Members",
                            "description": "Describe people in your family.",
                            "order_index": 1,
                            "estimated_minutes": 10,
                            "xp_reward": 20,
                            "total_exercises": 10,
                            "exercises": [
                                {
                                    "id": "ex_v1_1",
                                    "type": "multiple_choice",
                                    "ui_type": "multiple_choice",
                                    "question": "Your father's sister is your ___.",
                                    "options": [{"id": "0", "text": "aunt", "is_correct": True}, {"id": "1", "text": "uncle", "is_correct": False}],
                                    "correct_answer": "aunt",
                                    "explanation": "Father's sister is aunt."
                                },
                                {
                                    "id": "ex_v1_2",
                                    "type": "matching",
                                    "ui_type": "match_word_to_meaning",
                                    "question": "Match the family words with meanings.",
                                    "options": [{"id": "father", "text": "Male parent"}, {"id": "mother", "text": "Female parent"}],
                                    "correct_answer": "father:Male parent, mother:Female parent",
                                    "explanation": "Father is male parent, mother is female."
                                },
                                {
                                    "id": "ex_v1_3",
                                    "type": "fill_blank",
                                    "ui_type": "fill_in_the_blank",
                                    "question": "Complete: 'My mother's husband is my {blank}.'",
                                    "correct_answer": "father",
                                    "explanation": "Mother's husband is father."
                                },
                                {
                                    "id": "ex_v1_4",
                                    "type": "matching",
                                    "ui_type": "cognitive_fluidity",
                                    "question": "Match: mother, sister",
                                    "options": [{"id": "mother", "text": "female parent"}, {"id": "sister", "text": "female sibling"}],
                                    "correct_answer": "mother:female parent, sister:female sibling",
                                    "explanation": "Fast match."
                                },
                                {
                                    "id": "ex_v1_5",
                                    "type": "multiple_choice",
                                    "ui_type": "vocabulary_flashcard",
                                    "question": "Learn: 'Sibling' (anh chị em ruột)",
                                    "options": [{"id": "0", "text": "Got it!", "is_correct": True}],
                                    "correct_answer": "Got it!",
                                    "explanation": "A sibling is a brother or sister."
                                },
                                {
                                    "id": "ex_v1_6",
                                    "type": "true_false",
                                    "ui_type": "true_or_false",
                                    "question": "True or False: 'Cousin' is the child of your aunt or uncle.",
                                    "options": [{"id": "0", "text": "True", "is_correct": True}, {"id": "1", "text": "False", "is_correct": False}],
                                    "correct_answer": "True",
                                    "explanation": "Cousin is child of aunt/uncle."
                                },
                                {
                                    "id": "ex_v1_7",
                                    "type": "reorder",
                                    "ui_type": "arrange_the_sentence",
                                    "question": "Arrange: 'my / this / is / brother'",
                                    "options": [{"id": "0", "text": "this"}, {"id": "1", "text": "is"}, {"id": "2", "text": "my"}, {"id": "3", "text": "brother"}],
                                    "correct_answer": "this is my brother",
                                    "explanation": "Sentence structure."
                                },
                                {
                                    "id": "ex_v1_8",
                                    "type": "translate",
                                    "ui_type": "translation_choice",
                                    "question": "Translation of: 'Anh trai'",
                                    "options": [{"id": "0", "text": "brother", "is_correct": True}, {"id": "1", "text": "sister", "is_correct": False}],
                                    "correct_answer": "brother",
                                    "explanation": "Anh trai is brother."
                                },
                                {
                                    "id": "ex_v1_9",
                                    "type": "translate",
                                    "ui_type": "speaking_repeat",
                                    "question": "Repeat: 'My grandmother is nice.'",
                                    "correct_answer": "My grandmother is nice",
                                    "explanation": "Practice speaking."
                                },
                                {
                                    "id": "ex_v1_10",
                                    "type": "fill_blank",
                                    "ui_type": "dictation",
                                    "question": "Dictation: Listen and write '{blank}'",
                                    "correct_answer": "He is my uncle",
                                    "explanation": "Type what you hear."
                                }
                            ]
                        },
                        {
                            "title": "Rooms and Objects",
                            "description": "Talk about places and things at home.",
                            "order_index": 2,
                            "estimated_minutes": 10,
                            "xp_reward": 20,
                            "total_exercises": 10,
                            "exercises": [
                                {
                                    "id": "ex_v2_1",
                                    "type": "multiple_choice",
                                    "ui_type": "multiple_choice",
                                    "question": "You cook meals in the ___.",
                                    "options": [{"id": "0", "text": "kitchen", "is_correct": True}, {"id": "1", "text": "bedroom", "is_correct": False}],
                                    "correct_answer": "kitchen",
                                    "explanation": "Kitchen is for cooking."
                                },
                                {
                                    "id": "ex_v2_2",
                                    "type": "matching",
                                    "ui_type": "match_word_to_meaning",
                                    "question": "Match rooms with objects.",
                                    "options": [{"id": "bedroom", "text": "bed"}, {"id": "kitchen", "text": "fridge"}],
                                    "correct_answer": "bedroom:bed, kitchen:fridge",
                                    "explanation": "Bed in bedroom, fridge in kitchen."
                                },
                                {
                                    "id": "ex_v2_3",
                                    "type": "fill_blank",
                                    "ui_type": "fill_in_the_blank",
                                    "question": "Complete: 'I sleep in my {blank}.'",
                                    "correct_answer": "bedroom",
                                    "explanation": "Bedroom is for sleeping."
                                },
                                {
                                    "id": "ex_v2_4",
                                    "type": "true_false",
                                    "ui_type": "true_or_false",
                                    "question": "True or False: A sofa is typically placed in the living room.",
                                    "options": [{"id": "0", "text": "True", "is_correct": True}, {"id": "1", "text": "False", "is_correct": False}],
                                    "correct_answer": "True",
                                    "explanation": "Sofa in living room."
                                },
                                {
                                    "id": "ex_v2_5",
                                    "type": "reorder",
                                    "ui_type": "arrange_the_sentence",
                                    "question": "Arrange: 'in / the / bed / is / bedroom / the'",
                                    "options": [{"id": "0", "text": "the"}, {"id": "1", "text": "bed"}, {"id": "2", "text": "is"}, {"id": "3", "text": "in"}, {"id": "4", "text": "the"}, {"id": "5", "text": "bedroom"}],
                                    "correct_answer": "the bed is in the bedroom",
                                    "explanation": "Correct sentence structure."
                                },
                                {
                                    "id": "ex_v2_6",
                                    "type": "translate",
                                    "ui_type": "translation_choice",
                                    "question": "Translation of: 'Phòng tắm'",
                                    "options": [{"id": "0", "text": "bathroom", "is_correct": True}, {"id": "1", "text": "garden", "is_correct": False}],
                                    "correct_answer": "bathroom",
                                    "explanation": "Phòng tắm is bathroom."
                                },
                                {
                                    "id": "ex_v2_7",
                                    "type": "translate",
                                    "ui_type": "speaking_repeat",
                                    "question": "Repeat: 'The desk is clean.'",
                                    "correct_answer": "The desk is clean",
                                    "explanation": "Evaluate pronunciation."
                                },
                                {
                                    "id": "ex_v2_8",
                                    "type": "fill_blank",
                                    "ui_type": "dictation",
                                    "question": "Dictation: Listen and write '{blank}'",
                                    "correct_answer": "Open the window",
                                    "explanation": "Write what you hear."
                                },
                                {
                                    "id": "ex_v2_9",
                                    "type": "multiple_choice",
                                    "ui_type": "image_based_choice",
                                    "question": "Select the image that shows a table.",
                                    "options": [{"id": "0", "text": "Table", "is_correct": True}, {"id": "1", "text": "Chair", "is_correct": False}],
                                    "correct_answer": "Table",
                                    "explanation": "Card with table."
                                },
                                {
                                    "id": "ex_v2_10",
                                    "type": "multiple_choice",
                                    "ui_type": "vocabulary_flashcard",
                                    "question": "Learn: 'Furnishings'",
                                    "options": [{"id": "0", "text": "Got it!", "is_correct": True}],
                                    "correct_answer": "Got it!",
                                    "explanation": "Furniture and appliances in a room."
                                }
                            ]
                        },
                    ],
                },
            ],
        },
    ]

    for course_data in sample_courses:
        result = await db.execute(
            select(Course).where(Course.title == course_data["title"])
        )
        existing_course = result.scalar_one_or_none()
        if existing_course:
            await db.delete(existing_course)
            await db.flush()

        unit_seed = course_data.pop("units")
        category_slug = course_data.pop("category_slug")

        course = Course(
            **course_data,
            category_id=category_ids.get(category_slug),
            total_lessons=sum(len(unit["lessons"]) for unit in unit_seed),
            is_published=True,
        )
        db.add(course)
        await db.flush()
        created["courses"] += 1

        for unit_data in unit_seed:
            lesson_seed = unit_data.pop("lessons")
            unit = Unit(
                **unit_data,
                course_id=course.id,
                total_lessons=len(lesson_seed),
            )
            db.add(unit)
            await db.flush()
            created["units"] += 1

            for lesson_data in lesson_seed:
                exercises = lesson_data.pop("exercises", [])
                lesson = Lesson(
                    **lesson_data,
                    course_id=course.id,
                    unit_id=unit.id,
                    content={"exercises": exercises, "version": 1},
                    pass_threshold=70,
                    lesson_type="lesson",
                )
                db.add(lesson)
                created["lessons"] += 1
    
    await db.commit()
    
    return ApiResponse(
        success=True,
        message=(
            "Seed data created: "
            f"{created['achievements']} achievements, "
            f"{created['shop_items']} shop items, "
            f"{created['course_categories']} categories, "
            f"{created['courses']} courses, "
            f"{created['units']} units, "
            f"{created['lessons']} lessons"
        ),
        data=created
    )


# ============================================================================
# System Settings / Info
# ============================================================================

@router.get("/system-info", response_model=ApiResponse[dict])
async def get_system_info(
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """Get system configuration and stats. Admin only."""
    from app.core.config import settings as app_settings
    from app.models.user import User as UserModel

    # Count totals
    user_count = (await db.execute(select(func.count(UserModel.id)))).scalar() or 0
    course_count = (await db.execute(select(func.count(Course.id)))).scalar() or 0
    vocab_count = (await db.execute(select(func.count(VocabularyItem.id)))).scalar() or 0
    achievement_count = (await db.execute(select(func.count(Achievement.id)))).scalar() or 0

    return ApiResponse(
        success=True,
        message="System info",
        data={
            "app_name": app_settings.APP_NAME,
            "app_env": app_settings.APP_ENV,
            "debug": app_settings.DEBUG,
            "api_prefix": app_settings.API_V1_PREFIX,
            "log_level": app_settings.LOG_LEVEL,
            "token_expire_minutes": app_settings.ACCESS_TOKEN_EXPIRE_MINUTES,
            "refresh_token_days": app_settings.REFRESH_TOKEN_EXPIRE_DAYS,
            "cors_origins": app_settings.cors_origins,
            "ai_service_url": app_settings.AI_SERVICE_URL,
            "google_oauth": bool(app_settings.GOOGLE_CLIENT_ID),
            "firebase": bool(app_settings.FIREBASE_PROJECT_ID),
            "totals": {
                "users": user_count,
                "courses": course_count,
                "vocabulary": vocab_count,
                "achievements": achievement_count,
            }
        }
    )


from pydantic import BaseModel

class SystemInfoUpdate(BaseModel):
    app_name: Optional[str] = None
    debug: Optional[bool] = None
    log_level: Optional[str] = None
    token_expire_minutes: Optional[int] = None
    refresh_token_days: Optional[int] = None
    cors_origins: Optional[str] = None
    ai_service_url: Optional[str] = None

@router.put("/system-info", response_model=ApiResponse[dict])
async def update_system_info(
    payload: SystemInfoUpdate,
    admin_user: User = Depends(require_admin)
):
    """Update system configuration. Admin only."""
    from app.core.config import settings as app_settings
    from pathlib import Path

    updates = {}
    
    if payload.app_name is not None:
        app_settings.APP_NAME = payload.app_name
        updates["APP_NAME"] = payload.app_name
        
    if payload.debug is not None:
        app_settings.DEBUG = payload.debug
        updates["DEBUG"] = payload.debug
        
    if payload.log_level is not None:
        level = payload.log_level.upper()
        if level in ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]:
            app_settings.LOG_LEVEL = level
            updates["LOG_LEVEL"] = level
            
    if payload.token_expire_minutes is not None:
        app_settings.ACCESS_TOKEN_EXPIRE_MINUTES = payload.token_expire_minutes
        updates["ACCESS_TOKEN_EXPIRE_MINUTES"] = payload.token_expire_minutes
        
    if payload.refresh_token_days is not None:
        app_settings.REFRESH_TOKEN_EXPIRE_DAYS = payload.refresh_token_days
        updates["REFRESH_TOKEN_EXPIRE_DAYS"] = payload.refresh_token_days
        
    if payload.cors_origins is not None:
        app_settings.ALLOWED_ORIGINS = payload.cors_origins
        updates["ALLOWED_ORIGINS"] = payload.cors_origins
        
    if payload.ai_service_url is not None:
        app_settings.AI_SERVICE_URL = payload.ai_service_url
        updates["AI_SERVICE_URL"] = payload.ai_service_url

    if updates:
        project_root = Path(__file__).parent.parent.parent
        env_file = project_root / ".env"
        if app_settings.APP_ENV == "production":
            prod_env = project_root / ".env.production"
            if prod_env.exists():
                env_file = prod_env
        
        try:
            content = env_file.read_text() if env_file.exists() else ""
            lines = content.splitlines()
            new_lines = []
            updated_keys = set()
            
            for line in lines:
                stripped = line.strip()
                if not stripped or stripped.startswith("#"):
                    new_lines.append(line)
                    continue
                if "=" in stripped:
                    key, val = stripped.split("=", 1)
                    key = key.strip()
                    if key in updates:
                        new_val = updates[key]
                        if isinstance(new_val, bool):
                            new_val_str = "true" if new_val else "false"
                        else:
                            new_val_str = str(new_val)
                        new_lines.append(f"{key}={new_val_str}")
                        updated_keys.add(key)
                    else:
                        new_lines.append(line)
                else:
                    new_lines.append(line)
                    
            for key, val in updates.items():
                if key not in updated_keys:
                    if isinstance(val, bool):
                        val_str = "true" if val else "false"
                    else:
                        val_str = str(val)
                    new_lines.append(f"{key}={val_str}")
                    
            env_file.write_text("\n".join(new_lines) + "\n")
        except Exception as e:
            # Silently fallback if unable to write file in docker environment
            pass

    return ApiResponse(
        success=True,
        message="System configuration updated successfully",
        data={
            "app_name": app_settings.APP_NAME,
            "app_env": app_settings.APP_ENV,
            "debug": app_settings.DEBUG,
            "api_prefix": app_settings.API_V1_PREFIX,
            "log_level": app_settings.LOG_LEVEL,
            "token_expire_minutes": app_settings.ACCESS_TOKEN_EXPIRE_MINUTES,
            "refresh_token_days": app_settings.REFRESH_TOKEN_EXPIRE_DAYS,
            "cors_origins": app_settings.cors_origins,
            "ai_service_url": app_settings.AI_SERVICE_URL,
        }
    )


# ============================================================================
# User Admin (RBAC) - MOVED TO app/routes/user_management.py
# ============================================================================
# Legacy routes removed - use /api/v1/admin/users/* endpoints from user_management.py


# ============================================================================
# API Quota Monitoring (Phase 0 Infrastructure)
# ============================================================================

@router.get("/quota-usage", response_model=ApiResponse[dict])
async def get_quota_usage(
    api_name: Optional[str] = Query(None, description="Specific API to check"),
    admin_user: User = Depends(require_admin),
):
    """
    Get current API quota usage for all APIs or a specific one.
    
    Returns usage stats including threshold status, remaining budget,
    and time until daily reset.
    """
    from app.services.quota_manager import QuotaManager

    if api_name:
        if api_name not in QuotaManager.LIMITS:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Unknown API: {api_name}. "
                       f"Available: {list(QuotaManager.LIMITS.keys())}",
            )
        usage = await QuotaManager.get_usage(api_name)
        return ApiResponse(
            success=True,
            message=f"Quota usage for {api_name}",
            data=usage,
        )

    all_usage = await QuotaManager.get_all_usage()
    return ApiResponse(
        success=True,
        message=f"Quota usage for {len(all_usage)} APIs",
        data={
            "apis": all_usage,
            "reset_in": QuotaManager.get_reset_time(),
        },
    )


@router.post("/quota-reset/{api_name}", response_model=ApiResponse[dict])
async def reset_quota(
    api_name: str,
    admin_user: User = Depends(require_admin),
):
    """
    Manually reset quota counter for a specific API (emergency use).
    
    Use when: quota incorrectly tracked, or need to allow more requests
    after investigating an issue.
    """
    from app.services.quota_manager import QuotaManager

    if api_name not in QuotaManager.LIMITS:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Unknown API: {api_name}. "
                   f"Available: {list(QuotaManager.LIMITS.keys())}",
        )

    success = await QuotaManager.reset_quota(api_name)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Redis unavailable, cannot reset quota.",
        )

    return ApiResponse(
        success=True,
        message=f"Quota reset for {api_name}",
        data=await QuotaManager.get_usage(api_name),
    )
