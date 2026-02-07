"""
Admin API Routes
Admin-only endpoints for content management (Courses, Units, Lessons, Vocabulary).
Requires admin or super_admin role via RBAC system.
"""

from typing import Optional, List
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, Query, status, UploadFile, File
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, or_, func, desc

from app.core.database import get_db
from app.core.dependencies import get_current_admin, get_current_super_admin
from app.models.user import User
from app.models.rbac import Role
from app.models.course import Course, Unit, Lesson
from app.models.vocabulary import VocabularyItem
from app.models.gamification import Achievement, ShopItem
from app.models.content import GrammarItem, QuestionItem, TestExam
from app.crud.course import CourseCRUD, UnitCRUD, LessonCRUD
from app.schemas.course import (
    CourseCreate, CourseUpdate, CourseResponse,
    UnitCreate, UnitUpdate, UnitResponse,
    LessonCreate, LessonUpdate, LessonResponse
)
from app.schemas.response import ApiResponse
from app.schemas.content import (
    GrammarCreate, GrammarUpdate, GrammarResponse,
    QuestionCreate, QuestionUpdate, QuestionResponse,
    TestExamCreate, TestExamUpdate, TestExamResponse
)
from app.schemas.user import AdminUserUpdate, AdminUserListItem

router = APIRouter(prefix="/admin", tags=["Admin"])


# ============================================================================
# RBAC: Admin guard — requires role.level >= 1 (admin or super_admin)
# Imported from app.core.dependencies.get_current_admin
# ============================================================================

# Alias for backward compatibility in this file
require_admin = get_current_admin


# ============================================================================
# Course Admin CRUD
# ============================================================================

@router.get("/courses", response_model=ApiResponse[dict])
async def list_courses_admin(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    search: Optional[str] = Query(None),
    level: Optional[str] = Query(None),
    is_published: Optional[bool] = Query(None),
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """List all courses (including unpublished) for admin management."""
    query = select(Course)
    filters = []
    if search:
        pattern = f"%{search}%"
        filters.append(or_(Course.title.ilike(pattern), Course.description.ilike(pattern)))
    if level:
        filters.append(Course.level == level)
    if is_published is not None:
        filters.append(Course.is_published == is_published)
    if filters:
        from sqlalchemy import and_
        query = query.where(and_(*filters))
    
    count_q = select(func.count()).select_from(query.subquery())
    total = await db.scalar(count_q) or 0
    
    query = query.order_by(desc(Course.updated_at))
    offset = (page - 1) * page_size
    result = await db.execute(query.offset(offset).limit(page_size))
    courses = result.scalars().all()
    
    return ApiResponse(
        success=True,
        message=f"Retrieved {len(courses)} courses",
        data={
            "courses": [CourseResponse.model_validate(c).model_dump() for c in courses],
            "total": total,
            "page": page,
            "page_size": page_size,
            "total_pages": (total + page_size - 1) // page_size,
        }
    )


@router.get("/units", response_model=ApiResponse[List[dict]])
async def list_units_admin(
    course_id: UUID = Query(..., description="Filter units by course"),
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """List all units for a course."""
    result = await db.execute(
        select(Unit).where(Unit.course_id == course_id).order_by(Unit.order_index)
    )
    units = result.scalars().all()
    return ApiResponse(
        success=True,
        message=f"Retrieved {len(units)} units",
        data=[UnitResponse.model_validate(u).model_dump() for u in units]
    )


@router.get("/lessons", response_model=ApiResponse[List[dict]])
async def list_lessons_admin(
    unit_id: Optional[UUID] = Query(None, description="Filter by unit"),
    course_id: Optional[UUID] = Query(None, description="Filter by course"),
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """List lessons filtered by unit or course."""
    query = select(Lesson)
    if unit_id:
        query = query.where(Lesson.unit_id == unit_id)
    elif course_id:
        query = query.where(Lesson.course_id == course_id)
    query = query.order_by(Lesson.order_index)
    result = await db.execute(query)
    lessons = result.scalars().all()
    return ApiResponse(
        success=True,
        message=f"Retrieved {len(lessons)} lessons",
        data=[LessonResponse.model_validate(l).model_dump() for l in lessons]
    )


@router.post("/courses", response_model=ApiResponse[CourseResponse])
async def create_course(
    course: CourseCreate,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    Create a new course.
    
    Admin only endpoint.
    """
    new_course = await CourseCRUD.create_course(db, course)
    
    return ApiResponse(
        success=True,
        message="Course created successfully",
        data=CourseResponse.model_validate(new_course)
    )


@router.put("/courses/{course_id}", response_model=ApiResponse[CourseResponse])
async def update_course(
    course_id: UUID,
    course_update: CourseUpdate,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    Update an existing course.
    
    Admin only endpoint.
    """
    updated_course = await CourseCRUD.update_course(db, course_id, course_update)
    
    if not updated_course:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Course not found"
        )
    
    return ApiResponse(
        success=True,
        message="Course updated successfully",
        data=CourseResponse.model_validate(updated_course)
    )


@router.delete("/courses/{course_id}", response_model=ApiResponse[dict])
async def delete_course(
    course_id: UUID,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    Delete a course (soft delete - unpublish).
    
    Admin only endpoint.
    """
    success = await CourseCRUD.delete_course(db, course_id)
    
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Course not found"
        )
    
    return ApiResponse(
        success=True,
        message="Course deleted successfully",
        data={"deleted": True, "course_id": str(course_id)}
    )


# ============================================================================
# Unit Admin CRUD
# ============================================================================

@router.post("/units", response_model=ApiResponse[UnitResponse])
async def create_unit(
    unit: UnitCreate,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    Create a new unit within a course.
    
    Admin only endpoint.
    """
    # Verify course exists
    course = await CourseCRUD.get_course(db, unit.course_id)
    if not course:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Course not found"
        )
    
    new_unit = await UnitCRUD.create_unit(db, unit)
    
    return ApiResponse(
        success=True,
        message="Unit created successfully",
        data=UnitResponse.model_validate(new_unit)
    )


@router.put("/units/{unit_id}", response_model=ApiResponse[UnitResponse])
async def update_unit(
    unit_id: UUID,
    unit_update: UnitUpdate,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    Update an existing unit.
    
    Admin only endpoint.
    """
    updated_unit = await UnitCRUD.update_unit(db, unit_id, unit_update)
    
    if not updated_unit:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Unit not found"
        )
    
    return ApiResponse(
        success=True,
        message="Unit updated successfully",
        data=UnitResponse.model_validate(updated_unit)
    )


@router.delete("/units/{unit_id}", response_model=ApiResponse[dict])
async def delete_unit(
    unit_id: UUID,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    Delete a unit (cascade deletes lessons).
    
    Admin only endpoint.
    """
    success = await UnitCRUD.delete_unit(db, unit_id)
    
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Unit not found"
        )
    
    return ApiResponse(
        success=True,
        message="Unit deleted successfully",
        data={"deleted": True, "unit_id": str(unit_id)}
    )


# ============================================================================
# Lesson Admin CRUD
# ============================================================================

@router.post("/lessons", response_model=ApiResponse[LessonResponse])
async def create_lesson(
    lesson: LessonCreate,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    Create a new lesson within a unit.
    
    Admin only endpoint.
    """
    # Verify unit exists
    unit = await UnitCRUD.get_unit(db, lesson.unit_id)
    if not unit:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Unit not found"
        )
    
    new_lesson = await LessonCRUD.create_lesson(db, lesson)
    
    return ApiResponse(
        success=True,
        message="Lesson created successfully",
        data=LessonResponse.model_validate(new_lesson)
    )


@router.put("/lessons/{lesson_id}", response_model=ApiResponse[LessonResponse])
async def update_lesson(
    lesson_id: UUID,
    lesson_update: LessonUpdate,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    Update an existing lesson.
    
    Admin only endpoint.
    """
    updated_lesson = await LessonCRUD.update_lesson(db, lesson_id, lesson_update)
    
    if not updated_lesson:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Lesson not found"
        )
    
    return ApiResponse(
        success=True,
        message="Lesson updated successfully",
        data=LessonResponse.model_validate(updated_lesson)
    )


@router.delete("/lessons/{lesson_id}", response_model=ApiResponse[dict])
async def delete_lesson(
    lesson_id: UUID,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    Delete a lesson.
    
    Admin only endpoint.
    """
    success = await LessonCRUD.delete_lesson(db, lesson_id)
    
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Lesson not found"
        )
    
    return ApiResponse(
        success=True,
        message="Lesson deleted successfully",
        data={"deleted": True, "lesson_id": str(lesson_id)}
    )


# ============================================================================
# Vocabulary Admin CRUD
# ============================================================================

@router.get("/vocabulary", response_model=ApiResponse[List[dict]])
async def list_vocabulary(
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    List all vocabulary items.
    
    Admin only endpoint.
    """
    result = await db.execute(
        select(VocabularyItem)
        .order_by(VocabularyItem.word)
        .limit(limit)
        .offset(offset)
    )
    items = result.scalars().all()
    
    return ApiResponse(
        success=True,
        message=f"Retrieved {len(items)} vocabulary items",
        data=[{
            "id": str(item.id),
            "word": item.word,
            "definition": getattr(item, "definition", None),
            "translation": item.translation,
            "part_of_speech": item.part_of_speech,
            "pronunciation": getattr(item, "pronunciation", None),
            "difficulty_level": item.difficulty_level,
        } for item in items]
    )


@router.post("/vocabulary", response_model=ApiResponse[dict])
async def create_vocabulary(
    word: str,
    definition: str,
    translation: str,
    part_of_speech: str = "noun",
    pronunciation: Optional[str] = None,
    difficulty_level: str = "A1",
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    Create a new vocabulary item.
    
    Args:
        word: The vocabulary word
        definition: English definition
        translation: Vietnamese translation
        part_of_speech: Part of speech (noun, verb, adjective, etc.)
        pronunciation: IPA pronunciation
        difficulty_level: CEFR level (A1, A2, B1, B2, C1, C2)
    
    Admin only endpoint.
    """
    vocab = VocabularyItem(
        word=word,
        definition=definition,
        translation={"vi": translation},  # JSON format as per model
        part_of_speech=part_of_speech,
        pronunciation=pronunciation,
        difficulty_level=difficulty_level
    )
    db.add(vocab)
    await db.commit()
    await db.refresh(vocab)
    
    return ApiResponse(
        success=True,
        message="Vocabulary created successfully",
        data={
            "id": str(vocab.id),
            "word": vocab.word,
            "definition": vocab.definition,
            "translation": vocab.translation
        }
    )


@router.delete("/vocabulary/{vocab_id}", response_model=ApiResponse[dict])
async def delete_vocabulary(
    vocab_id: UUID,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    Delete a vocabulary item.
    
    Admin only endpoint.
    """
    result = await db.execute(
        select(VocabularyItem).where(VocabularyItem.id == vocab_id)
    )
    vocab = result.scalar_one_or_none()
    
    if not vocab:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Vocabulary not found"
        )
    
    await db.delete(vocab)
    await db.commit()
    
    return ApiResponse(
        success=True,
        message="Vocabulary deleted successfully",
        data={"deleted": True, "vocab_id": str(vocab_id)}
    )


@router.put("/vocabulary/{vocab_id}", response_model=ApiResponse[dict])
async def update_vocabulary(
    vocab_id: UUID,
    word: Optional[str] = None,
    definition: Optional[str] = None,
    translation: Optional[str] = None,
    part_of_speech: Optional[str] = None,
    pronunciation: Optional[str] = None,
    difficulty_level: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """Update a vocabulary item."""
    result = await db.execute(
        select(VocabularyItem).where(VocabularyItem.id == vocab_id)
    )
    vocab = result.scalar_one_or_none()
    if not vocab:
        raise HTTPException(status_code=404, detail="Vocabulary not found")
    
    if word is not None: vocab.word = word
    if definition is not None: vocab.definition = definition
    if translation is not None: vocab.translation = {"vi": translation}
    if part_of_speech is not None: vocab.part_of_speech = part_of_speech
    if pronunciation is not None: vocab.pronunciation = pronunciation
    if difficulty_level is not None: vocab.difficulty_level = difficulty_level
    
    await db.commit()
    await db.refresh(vocab)
    
    return ApiResponse(
        success=True,
        message="Vocabulary updated successfully",
        data={
            "id": str(vocab.id),
            "word": vocab.word,
            "definition": vocab.definition,
            "translation": vocab.translation,
            "part_of_speech": vocab.part_of_speech,
            "difficulty_level": vocab.difficulty_level,
        }
    )


@router.post("/vocabulary/bulk-import", response_model=ApiResponse[dict])
async def bulk_import_vocabulary(
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    Bulk import vocabulary from CSV file.
    
    CSV format: word,definition,translation,part_of_speech,pronunciation,difficulty_level
    First row must be headers.
    """
    import csv
    import io
    
    if not file.filename or not file.filename.endswith(".csv"):
        raise HTTPException(status_code=400, detail="Only CSV files are supported")
    
    content = await file.read()
    text = content.decode("utf-8-sig")  # Handle BOM
    reader = csv.DictReader(io.StringIO(text))
    
    created = 0
    skipped = 0
    errors = []
    
    for row_num, row in enumerate(reader, start=2):
        word = row.get("word", "").strip()
        definition = row.get("definition", "").strip()
        translation = row.get("translation", "").strip()
        
        if not word:
            skipped += 1
            continue
        
        # Check duplicate
        existing = await db.scalar(
            select(func.count()).where(VocabularyItem.word == word)
        )
        if existing:
            skipped += 1
            continue
        
        try:
            vocab = VocabularyItem(
                word=word,
                definition=definition or word,
                translation={"vi": translation} if translation else {},
                part_of_speech=row.get("part_of_speech", "noun").strip() or "noun",
                pronunciation=row.get("pronunciation", "").strip() or None,
                difficulty_level=row.get("difficulty_level", "A1").strip() or "A1",
            )
            db.add(vocab)
            created += 1
        except Exception as e:
            errors.append(f"Row {row_num}: {str(e)}")
    
    await db.commit()
    
    return ApiResponse(
        success=True,
        message=f"Imported {created} words, skipped {skipped} duplicates",
        data={
            "created": created,
            "skipped": skipped,
            "errors": errors[:10],  # Limit error list
        }
    )


# ============================================================================
# Achievement Admin CRUD
# ============================================================================

@router.get("/achievements", response_model=ApiResponse[List[dict]])
async def list_achievements_admin(
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    List all achievements (admin view).
    
    Admin only endpoint.
    """
    result = await db.execute(
        select(Achievement).order_by(Achievement.category, Achievement.name)
    )
    achievements = result.scalars().all()
    
    return ApiResponse(
        success=True,
        message=f"Retrieved {len(achievements)} achievements",
        data=[{
            "id": str(a.id),
            "name": a.name,
            "description": a.description,
            "category": a.category,
            "rarity": a.rarity,
            "xp_reward": a.xp_reward,
            "gems_reward": a.gems_reward,
            "is_hidden": a.is_hidden
        } for a in achievements]
    )


@router.post("/achievements", response_model=ApiResponse[dict])
async def create_achievement(
    name: str,
    description: str,
    condition_type: str,
    condition_value: int = 1,
    category: str = "special",
    rarity: str = "common",
    xp_reward: int = 0,
    gems_reward: int = 0,
    is_hidden: bool = False,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    Create a new achievement.
    
    Admin only endpoint.
    """
    achievement = Achievement(
        name=name,
        description=description,
        condition_type=condition_type,
        condition_value=condition_value,
        category=category,
        rarity=rarity,
        xp_reward=xp_reward,
        gems_reward=gems_reward,
        is_hidden=is_hidden
    )
    db.add(achievement)
    await db.commit()
    await db.refresh(achievement)
    
    return ApiResponse(
        success=True,
        message="Achievement created successfully",
        data={
            "id": str(achievement.id),
            "name": achievement.name,
            "category": achievement.category
        }
    )


@router.put("/achievements/{achievement_id}", response_model=ApiResponse[dict])
async def update_achievement(
    achievement_id: UUID,
    name: Optional[str] = None,
    description: Optional[str] = None,
    condition_type: Optional[str] = None,
    condition_value: Optional[int] = None,
    category: Optional[str] = None,
    rarity: Optional[str] = None,
    xp_reward: Optional[int] = None,
    gems_reward: Optional[int] = None,
    is_hidden: Optional[bool] = None,
    badge_icon: Optional[str] = None,
    badge_color: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """Update an achievement. Admin only."""
    result = await db.execute(
        select(Achievement).where(Achievement.id == achievement_id)
    )
    achievement = result.scalar_one_or_none()
    if not achievement:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Achievement not found")

    for field, value in {
        "name": name, "description": description, "condition_type": condition_type,
        "condition_value": condition_value, "category": category, "rarity": rarity,
        "xp_reward": xp_reward, "gems_reward": gems_reward, "is_hidden": is_hidden,
        "badge_icon": badge_icon, "badge_color": badge_color,
    }.items():
        if value is not None:
            setattr(achievement, field, value)

    await db.commit()
    await db.refresh(achievement)

    return ApiResponse(
        success=True,
        message="Achievement updated successfully",
        data={
            "id": str(achievement.id),
            "name": achievement.name,
            "category": achievement.category,
            "rarity": achievement.rarity,
        }
    )


@router.delete("/achievements/{achievement_id}", response_model=ApiResponse[dict])
async def delete_achievement(
    achievement_id: UUID,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    Delete an achievement.
    
    Admin only endpoint.
    """
    result = await db.execute(
        select(Achievement).where(Achievement.id == achievement_id)
    )
    achievement = result.scalar_one_or_none()
    
    if not achievement:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Achievement not found"
        )
    
    await db.delete(achievement)
    await db.commit()
    
    return ApiResponse(
        success=True,
        message="Achievement deleted successfully",
        data={"deleted": True, "achievement_id": str(achievement_id)}
    )


# ============================================================================
# Shop Admin CRUD
# ============================================================================

@router.get("/shop", response_model=ApiResponse[List[dict]])
async def list_shop_items_admin(
    include_unavailable: bool = Query(False),
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    List all shop items (admin view).
    
    Admin only endpoint.
    """
    query = select(ShopItem).order_by(ShopItem.item_type, ShopItem.price_gems)
    if not include_unavailable:
        query = query.where(ShopItem.is_available == True)
    
    result = await db.execute(query)
    items = result.scalars().all()
    
    return ApiResponse(
        success=True,
        message=f"Retrieved {len(items)} shop items",
        data=[{
            "id": str(item.id),
            "name": item.name,
            "description": item.description,
            "item_type": item.item_type,
            "price_gems": item.price_gems,
            "is_available": item.is_available,
            "stock_quantity": item.stock_quantity
        } for item in items]
    )


@router.post("/shop", response_model=ApiResponse[dict])
async def create_shop_item(
    name: str,
    description: str,
    item_type: str,
    price_gems: int,
    is_available: bool = True,
    stock_quantity: Optional[int] = None,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    Create a new shop item.
    
    Admin only endpoint.
    """
    item = ShopItem(
        name=name,
        description=description,
        item_type=item_type,
        price_gems=price_gems,
        is_available=is_available,
        stock_quantity=stock_quantity
    )
    db.add(item)
    await db.commit()
    await db.refresh(item)
    
    return ApiResponse(
        success=True,
        message="Shop item created successfully",
        data={
            "id": str(item.id),
            "name": item.name,
            "price_gems": item.price_gems
        }
    )


@router.put("/shop/{item_id}", response_model=ApiResponse[dict])
async def update_shop_item(
    item_id: UUID,
    name: Optional[str] = None,
    description: Optional[str] = None,
    price_gems: Optional[int] = None,
    is_available: Optional[bool] = None,
    stock_quantity: Optional[int] = None,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    Update a shop item.
    
    Admin only endpoint.
    """
    result = await db.execute(
        select(ShopItem).where(ShopItem.id == item_id)
    )
    item = result.scalar_one_or_none()
    
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Shop item not found"
        )
    
    if name is not None:
        item.name = name
    if description is not None:
        item.description = description
    if price_gems is not None:
        item.price_gems = price_gems
    if is_available is not None:
        item.is_available = is_available
    if stock_quantity is not None:
        item.stock_quantity = stock_quantity
    
    await db.commit()
    await db.refresh(item)
    
    return ApiResponse(
        success=True,
        message="Shop item updated successfully",
        data={
            "id": str(item.id),
            "name": item.name,
            "price_gems": item.price_gems,
            "is_available": item.is_available
        }
    )


@router.delete("/shop/{item_id}", response_model=ApiResponse[dict])
async def delete_shop_item(
    item_id: UUID,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    Delete a shop item.
    
    Admin only endpoint.
    """
    result = await db.execute(
        select(ShopItem).where(ShopItem.id == item_id)
    )
    item = result.scalar_one_or_none()
    
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Shop item not found"
        )
    
    await db.delete(item)
    await db.commit()
    
    return ApiResponse(
        success=True,
        message="Shop item deleted successfully",
        data={"deleted": True, "item_id": str(item_id)}
    )


# ============================================================================
# Grammar Admin CRUD
# ============================================================================

@router.get("/grammar", response_model=ApiResponse[List[GrammarResponse]])
async def list_grammar_admin(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    result = await db.execute(
        select(GrammarItem).order_by(GrammarItem.created_at.desc()).limit(limit).offset(offset)
    )
    items = result.scalars().all()
    return ApiResponse(
        success=True,
        message=f"Retrieved {len(items)} grammar items",
        data=[GrammarResponse.model_validate(item) for item in items]
    )


@router.post("/grammar", response_model=ApiResponse[GrammarResponse])
async def create_grammar_admin(
    payload: GrammarCreate,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    item = GrammarItem(
        title=payload.title,
        level=payload.level,
        topic=payload.topic,
        summary=payload.summary,
        content=payload.content,
        examples=payload.examples,
        tags=payload.tags,
        is_active=payload.is_active,
    )
    db.add(item)
    await db.commit()
    await db.refresh(item)
    return ApiResponse(success=True, message="Grammar created", data=GrammarResponse.model_validate(item))


@router.put("/grammar/{grammar_id}", response_model=ApiResponse[GrammarResponse])
async def update_grammar_admin(
    grammar_id: UUID,
    payload: GrammarUpdate,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    result = await db.execute(select(GrammarItem).where(GrammarItem.id == grammar_id))
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Grammar item not found")

    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(item, field, value)

    await db.commit()
    await db.refresh(item)
    return ApiResponse(success=True, message="Grammar updated", data=GrammarResponse.model_validate(item))


@router.delete("/grammar/{grammar_id}", response_model=ApiResponse[dict])
async def delete_grammar_admin(
    grammar_id: UUID,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    result = await db.execute(select(GrammarItem).where(GrammarItem.id == grammar_id))
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Grammar item not found")
    await db.delete(item)
    await db.commit()
    return ApiResponse(success=True, message="Grammar deleted", data={"deleted": True, "grammar_id": str(grammar_id)})


# ============================================================================
# Question Bank Admin CRUD
# ============================================================================

@router.get("/questions", response_model=ApiResponse[List[QuestionResponse]])
async def list_questions_admin(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    result = await db.execute(
        select(QuestionItem).order_by(QuestionItem.created_at.desc()).limit(limit).offset(offset)
    )
    items = result.scalars().all()
    return ApiResponse(
        success=True,
        message=f"Retrieved {len(items)} questions",
        data=[QuestionResponse.model_validate(item) for item in items]
    )


@router.post("/questions", response_model=ApiResponse[QuestionResponse])
async def create_question_admin(
    payload: QuestionCreate,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    item = QuestionItem(
        prompt=payload.prompt,
        question_type=payload.question_type,
        options=payload.options,
        answer=payload.answer,
        explanation=payload.explanation,
        difficulty_level=payload.difficulty_level,
        tags=payload.tags,
        grammar_id=payload.grammar_id,
        is_active=payload.is_active,
    )
    db.add(item)
    await db.commit()
    await db.refresh(item)
    return ApiResponse(success=True, message="Question created", data=QuestionResponse.model_validate(item))


@router.put("/questions/{question_id}", response_model=ApiResponse[QuestionResponse])
async def update_question_admin(
    question_id: UUID,
    payload: QuestionUpdate,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    result = await db.execute(select(QuestionItem).where(QuestionItem.id == question_id))
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Question not found")

    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(item, field, value)

    await db.commit()
    await db.refresh(item)
    return ApiResponse(success=True, message="Question updated", data=QuestionResponse.model_validate(item))


@router.delete("/questions/{question_id}", response_model=ApiResponse[dict])
async def delete_question_admin(
    question_id: UUID,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    result = await db.execute(select(QuestionItem).where(QuestionItem.id == question_id))
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Question not found")
    await db.delete(item)
    await db.commit()
    return ApiResponse(success=True, message="Question deleted", data={"deleted": True, "question_id": str(question_id)})


# ============================================================================
# Test Exam Admin CRUD
# ============================================================================

@router.get("/test-exams", response_model=ApiResponse[List[TestExamResponse]])
async def list_test_exams_admin(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    result = await db.execute(
        select(TestExam).order_by(TestExam.created_at.desc()).limit(limit).offset(offset)
    )
    items = result.scalars().all()
    return ApiResponse(
        success=True,
        message=f"Retrieved {len(items)} test exams",
        data=[TestExamResponse.model_validate(item) for item in items]
    )


@router.post("/test-exams", response_model=ApiResponse[TestExamResponse])
async def create_test_exam_admin(
    payload: TestExamCreate,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    item = TestExam(
        title=payload.title,
        description=payload.description,
        level=payload.level,
        duration_minutes=payload.duration_minutes,
        passing_score=payload.passing_score,
        question_ids=[str(q) for q in payload.question_ids] if payload.question_ids else None,
        is_published=payload.is_published,
    )
    db.add(item)
    await db.commit()
    await db.refresh(item)
    return ApiResponse(success=True, message="Test exam created", data=TestExamResponse.model_validate(item))


@router.put("/test-exams/{test_exam_id}", response_model=ApiResponse[TestExamResponse])
async def update_test_exam_admin(
    test_exam_id: UUID,
    payload: TestExamUpdate,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    result = await db.execute(select(TestExam).where(TestExam.id == test_exam_id))
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Test exam not found")

    update_data = payload.model_dump(exclude_unset=True)
    if "question_ids" in update_data and update_data["question_ids"] is not None:
        update_data["question_ids"] = [str(q) for q in update_data["question_ids"]]
    for field, value in update_data.items():
        setattr(item, field, value)

    await db.commit()
    await db.refresh(item)
    return ApiResponse(success=True, message="Test exam updated", data=TestExamResponse.model_validate(item))


@router.delete("/test-exams/{test_exam_id}", response_model=ApiResponse[dict])
async def delete_test_exam_admin(
    test_exam_id: UUID,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    result = await db.execute(select(TestExam).where(TestExam.id == test_exam_id))
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Test exam not found")
    await db.delete(item)
    await db.commit()
    return ApiResponse(success=True, message="Test exam deleted", data={"deleted": True, "test_exam_id": str(test_exam_id)})


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
    
    Creates sample achievements and shop items.
    Admin only endpoint.
    """
    created = {"achievements": 0, "shop_items": 0}
    
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
    sample_shop_items = [
        {"name": "Streak Freeze", "description": "Protect your streak for one day", 
         "item_type": "streak_freeze", "price_gems": 200},
        {"name": "Double XP (1 hour)", "description": "Earn double XP for 1 hour", 
         "item_type": "double_xp", "price_gems": 150},
        {"name": "Hint Pack (5)", "description": "5 additional hints for lessons", 
         "item_type": "hint_pack", "price_gems": 100},
        {"name": "Heart Refill", "description": "Refill all hearts instantly", 
         "item_type": "heart_refill", "price_gems": 350},
    ]
    
    for item_data in sample_shop_items:
        # Check if exists
        result = await db.execute(
            select(ShopItem).where(ShopItem.name == item_data["name"])
        )
        if not result.scalar_one_or_none():
            item = ShopItem(**item_data)
            db.add(item)
            created["shop_items"] += 1
    
    await db.commit()
    
    return ApiResponse(
        success=True,
        message=f"Seed data created: {created['achievements']} achievements, {created['shop_items']} shop items",
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


# ============================================================================
# User Admin (RBAC) - MOVED TO app/routes/user_management.py
# ============================================================================
# Legacy routes removed - use /api/v1/admin/users/* endpoints from user_management.py
