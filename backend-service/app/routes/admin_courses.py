"""Admin routes — courses, units, lessons, vocabulary, grammar, questions, test exams."""
import csv
import io
import json
import os
from pathlib import Path
from typing import List, Optional
from uuid import UUID

import anyio
from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from pydantic import BaseModel, Field
from pypdf import PdfReader
from sqlalchemy import desc, func, insert, or_, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_admin
from app.crud.course import CourseCRUD, LessonCRUD, UnitCRUD
from app.models.content import GrammarItem, QuestionItem, TestExam
from app.models.course import Course, Lesson, Unit
from app.models.user import User
from app.models.vocabulary import VocabularyItem
from app.schemas.content import (
    GrammarCreate,
    GrammarResponse,
    GrammarUpdate,
    QuestionCreate,
    QuestionResponse,
    QuestionUpdate,
    TestExamCreate,
    TestExamResponse,
    TestExamUpdate,
)
from app.schemas.course import (
    CourseCreate,
    CourseResponse,
    CourseUpdate,
    LessonCreate,
    LessonDetailResponse,
    LessonResponse,
    LessonUpdate,
    UnitCreate,
    UnitResponse,
    UnitUpdate,
)
from app.schemas.response import ApiResponse

router = APIRouter(prefix="/admin", tags=["Admin"])

require_admin = get_current_admin

_MAX_IMPORT_BYTES = 10 * 1024 * 1024
_MAX_PDF_PAGES = 500
_MAX_PDF_TEXT_CHARS = 2_000_000
_MEDIA_DIR = Path("/app/data/media")


def _extract_pdf_text(content: bytes) -> str:
    pages = PdfReader(io.BytesIO(content)).pages
    if len(pages) > _MAX_PDF_PAGES:
        raise HTTPException(status_code=413, detail=f"PDF exceeds the {_MAX_PDF_PAGES}-page limit.")
    extracted: list[str] = []
    total_chars = 0
    for page in pages:
        text = page.extract_text() or ""
        total_chars += len(text)
        if total_chars > _MAX_PDF_TEXT_CHARS:
            raise HTTPException(status_code=413, detail="Extracted PDF text is too large.")
        extracted.append(text)
    return "\n".join(extracted)


async def _read_import_text(file: UploadFile, *, pdf_only: bool = False) -> str:
    suffix = Path(file.filename or "").suffix.lower()
    allowed = (".pdf",) if pdf_only else (".csv", ".pdf")
    if suffix not in allowed:
        detail = "Only PDF files are supported" if pdf_only else "Only CSV and PDF files are supported"
        raise HTTPException(status_code=400, detail=detail)

    content = await file.read(_MAX_IMPORT_BYTES + 1)
    if len(content) > _MAX_IMPORT_BYTES:
        raise HTTPException(status_code=413, detail="File too large. Maximum 10MB allowed.")
    if suffix == ".pdf":
        try:
            return await anyio.to_thread.run_sync(_extract_pdf_text, content)
        except HTTPException:
            raise
        except Exception as exc:
            raise HTTPException(status_code=400, detail="Invalid PDF file") from exc
    try:
        return content.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise HTTPException(status_code=400, detail="CSV file must be UTF-8 encoded") from exc


async def _bulk_insert_rows(
    db: AsyncSession,
    model,
    rows: list[dict],
    *,
    conflict_columns: tuple[str, ...] = (),
) -> int:
    if not rows:
        return 0
    dialect = db.bind.dialect.name if db.bind else "postgresql"
    if conflict_columns and dialect == "postgresql":
        statement = pg_insert(model).values(rows).on_conflict_do_nothing(
            index_elements=list(conflict_columns)
        )
    elif conflict_columns and dialect == "sqlite":
        statement = sqlite_insert(model).values(rows).on_conflict_do_nothing(
            index_elements=list(conflict_columns)
        )
    else:
        statement = insert(model).values(rows)
    result = await db.execute(statement)
    return result.rowcount if result.rowcount is not None and result.rowcount >= 0 else len(rows)


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
    course_id: Optional[UUID] = Query(None, description="Filter units by course"),
    search: Optional[str] = Query(None, description="Search units by title or description"),
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """List all units, optionally filtered by course or searched by title/description."""
    query = select(Unit)
    if course_id:
        query = query.where(Unit.course_id == course_id)
    if search:
        query = query.where(
            or_(
                Unit.title.ilike(f"%{search}%"),
                Unit.description.ilike(f"%{search}%")
            )
        )
    query = query.order_by(Unit.order_index)
    result = await db.execute(query)
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


class _LessonBulkImportItem(BaseModel):
    title: str
    description: Optional[str] = None
    lesson_type: str = "lesson"
    xp_reward: int = Field(default=10, ge=0)
    pass_threshold: int = Field(default=80, ge=0, le=100)


class _UnitBulkImportItem(BaseModel):
    title: str
    description: Optional[str] = None
    background_color: Optional[str] = None
    icon_url: Optional[str] = None
    lessons: List[_LessonBulkImportItem] = Field(default_factory=list)


class _CourseBulkImportItem(BaseModel):
    title: str
    description: Optional[str] = None
    language: str = "en"
    level: str = "A1"
    tags: List[str] = Field(default_factory=list)
    thumbnail_url: Optional[str] = None
    is_published: bool = False
    units: List[_UnitBulkImportItem] = Field(default_factory=list)


class CourseBulkImportRequest(BaseModel):
    courses: List[_CourseBulkImportItem]


@router.post("/courses/bulk-import", response_model=ApiResponse[dict])
async def bulk_import_courses(
    payload: CourseBulkImportRequest,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
) -> ApiResponse[dict]:
    """
    Bulk import courses with nested units/lessons — one DB round trip per
    course instead of the old N+1 client-side loop (createCourse then
    createUnit then createLesson per item). Each course is wrapped in its
    own savepoint so one bad course doesn't roll back the others already
    imported in the same request.
    """
    created_courses = 0
    created_units = 0
    created_lessons = 0
    errors: list[str] = []

    for course_data in payload.courses:
        try:
            async with db.begin_nested():
                course = Course(
                    title=course_data.title,
                    description=course_data.description,
                    language=course_data.language,
                    level=course_data.level,
                    tags=course_data.tags,
                    thumbnail_url=course_data.thumbnail_url,
                    is_published=course_data.is_published,
                )
                db.add(course)
                await db.flush()

                course_total_xp = 0
                course_total_lessons = 0

                for unit_index, unit_data in enumerate(course_data.units):
                    unit = Unit(
                        course_id=course.id,
                        title=unit_data.title,
                        description=unit_data.description,
                        order_index=unit_index,
                        background_color=unit_data.background_color,
                        icon_url=unit_data.icon_url,
                        total_lessons=len(unit_data.lessons),
                    )
                    db.add(unit)
                    await db.flush()

                    for lesson_index, lesson_data in enumerate(unit_data.lessons):
                        db.add(Lesson(
                            course_id=course.id,
                            unit_id=unit.id,
                            title=lesson_data.title,
                            description=lesson_data.description,
                            order_index=lesson_index,
                            lesson_type=lesson_data.lesson_type,
                            xp_reward=lesson_data.xp_reward,
                            pass_threshold=lesson_data.pass_threshold,
                        ))
                        course_total_xp += lesson_data.xp_reward
                        course_total_lessons += 1

                    created_units += 1
                    created_lessons += len(unit_data.lessons)

                course.total_lessons = course_total_lessons
                course.total_xp = course_total_xp
            created_courses += 1
        except Exception as e:
            errors.append(f'Course "{course_data.title}": {str(e)}')

    await db.commit()

    return ApiResponse(
        success=True,
        message=f"Imported {created_courses} courses, {created_units} units, {created_lessons} lessons",
        data={
            "courses": created_courses,
            "units": created_units,
            "lessons": created_lessons,
            "errors": errors[:10],
        }
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


@router.get("/lessons/{lesson_id}", response_model=ApiResponse[dict])
async def get_lesson_detail(
    lesson_id: UUID,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """Get a single lesson with full content/exercises (admin only)."""
    lesson = await LessonCRUD.get_lesson(db, lesson_id)
    if not lesson:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Lesson not found")

    data = LessonDetailResponse.model_validate(lesson).model_dump()
    return ApiResponse(success=True, message="Lesson retrieved", data=data)


class LessonContentUpdate(LessonUpdate):
    """Dedicated schema for updating lesson exercises content."""
    pass


@router.put("/lessons/{lesson_id}/content", response_model=ApiResponse[dict])
async def update_lesson_content(
    lesson_id: UUID,
    payload: LessonContentUpdate,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """Update lesson exercises and estimated_minutes (admin only)."""
    lesson = await LessonCRUD.get_lesson(db, lesson_id)
    if not lesson:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Lesson not found")

    update_data = payload.model_dump(exclude_unset=True)

    # Derive total_exercises from exercises array inside content
    if "content" in update_data and update_data["content"]:
        exercises = update_data["content"].get("exercises", [])
        update_data["total_exercises"] = len(exercises)

    for field, value in update_data.items():
        setattr(lesson, field, value)

    await db.commit()
    await db.refresh(lesson)

    data = LessonDetailResponse.model_validate(lesson).model_dump()
    return ApiResponse(success=True, message="Lesson content updated", data=data)


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
) -> ApiResponse[dict]:
    """
    Bulk import vocabulary from CSV or PDF containing CSV-formatted text.
    
    CSV format: word,definition,translation,part_of_speech,pronunciation,difficulty_level
    First row must be headers.
    """
    text = await _read_import_text(file)
    reader = csv.DictReader(io.StringIO(text))
    
    skipped = 0
    errors = []
    pending: dict[tuple[str, str], dict] = {}

    for row_num, row in enumerate(reader, start=2):
        word = row.get("word", "").strip()
        definition = row.get("definition", "").strip()
        translation = row.get("translation", "").strip()

        if not word:
            skipped += 1
            continue
        part_of_speech = row.get("part_of_speech", "noun").strip() or "noun"
        key = (word, part_of_speech)
        if key in pending:
            skipped += 1
            continue

        pending[key] = {
            "word": word,
            "definition": definition or word,
            "translation": {"vi": translation} if translation else {},
            "part_of_speech": part_of_speech,
            "pronunciation": row.get("pronunciation", "").strip() or None,
            "difficulty_level": row.get("difficulty_level", "A1").strip() or "A1",
        }

    if pending:
        existing = set(
            (
                await db.execute(
                    select(VocabularyItem.word, VocabularyItem.part_of_speech).where(
                        VocabularyItem.word.in_({key[0] for key in pending}),
                        VocabularyItem.part_of_speech.in_({key[1] for key in pending}),
                    )
                )
            ).tuples().all()
        )
        skipped += len(existing & pending.keys())
        rows = [value for key, value in pending.items() if key not in existing]
    else:
        rows = []
    created = await _bulk_insert_rows(
        db,
        VocabularyItem,
        rows,
        conflict_columns=("word", "part_of_speech"),
    )
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


@router.post("/import/extract-pdf-text", response_model=ApiResponse[dict])
async def extract_pdf_text(
    file: UploadFile = File(...),
    admin_user: User = Depends(require_admin),
) -> ApiResponse[dict]:
    """Extract text from a PDF for the existing course text parser."""
    text = await _read_import_text(file, pdf_only=True)

    return ApiResponse(success=True, message="PDF text extracted", data={"text": text})


# ============================================================================
# Badge Image Upload
# ============================================================================

@router.post("/upload/badge", response_model=ApiResponse[dict])
async def upload_badge_image(
    file: UploadFile = File(...),
    admin_user: User = Depends(require_admin)
):
    """
    Upload a badge image. Returns the URL path to the uploaded file.
    Accepts PNG, JPG, WEBP images up to 2MB.
    """
    # Validate file type — SVG excluded to prevent XSS
    allowed_types = ["image/png", "image/jpeg", "image/webp"]
    if file.content_type not in allowed_types:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid file type: {file.content_type}. Allowed: {', '.join(allowed_types)}"
        )

    # Read file and check size (2MB limit)
    contents = await file.read()
    if len(contents) > 2 * 1024 * 1024:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="File too large. Maximum 2MB allowed."
        )

    if os.path.isdir(_MEDIA_DIR):
        target_dir = _MEDIA_DIR / "badges"
        url_prefix = "/media/badges"
    else:
        target_dir = Path(__file__).resolve().parent.parent.parent / "static" / "badges"
        url_prefix = "/static/badges"
    target_dir.mkdir(parents=True, exist_ok=True)

    # Generate UUID-based filename to prevent path traversal and name collisions
    import uuid
    allowed_extensions = {".png", ".jpg", ".jpeg", ".webp"}
    original_ext = Path(file.filename or "badge.png").suffix.lower()
    if original_ext not in allowed_extensions:
        original_ext = ".png"
    safe_name = f"{uuid.uuid4().hex}{original_ext}"
    filepath = target_dir / safe_name

    with open(filepath, "wb") as f:
        f.write(contents)

    badge_url = f"{url_prefix}/{filepath.name}"

    return ApiResponse(
        success=True,
        message="Badge image uploaded successfully",
        data={
            "url": badge_url,
            "filename": filepath.name,
        }
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


@router.post("/grammar/bulk-import", response_model=ApiResponse[dict])
async def bulk_import_grammar(
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
) -> ApiResponse[dict]:
    """
    Bulk import grammar rules from CSV or PDF containing CSV-formatted text.

    CSV format: title,level,topic,summary,content,tags
    tags is a ';'-separated list. First row must be headers.
    """
    text = await _read_import_text(file)
    reader = csv.DictReader(io.StringIO(text))

    skipped = 0
    errors = []
    pending: dict[str, dict] = {}

    for row_num, row in enumerate(reader, start=2):
        title = (row.get("title") or "").strip()
        content_text = (row.get("content") or "").strip()

        if not title or not content_text:
            skipped += 1
            continue

        if title in pending:
            skipped += 1
            continue

        try:
            tags = [t.strip() for t in (row.get("tags") or "").split(";") if t.strip()]
            pending[title] = {
                "title": title,
                "level": (row.get("level") or "A1").strip() or "A1",
                "topic": (row.get("topic") or "").strip() or None,
                "summary": (row.get("summary") or "").strip() or None,
                "content": content_text,
                "tags": tags or None,
            }
        except Exception as e:
            errors.append(f"Row {row_num}: {str(e)}")

    existing = set(
        await db.scalars(select(GrammarItem.title).where(GrammarItem.title.in_(pending)))
    ) if pending else set()
    skipped += len(existing)
    created = await _bulk_insert_rows(
        db,
        GrammarItem,
        [value for key, value in pending.items() if key not in existing],
    )
    await db.commit()

    return ApiResponse(
        success=True,
        message=f"Imported {created} grammar rules, skipped {skipped} duplicates/blank rows",
        data={"created": created, "skipped": skipped, "errors": errors[:10]}
    )


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


@router.post("/questions/bulk-import", response_model=ApiResponse[dict])
async def bulk_import_questions(
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
) -> ApiResponse[dict]:
    """
    Bulk import questions from CSV or PDF containing CSV-formatted text.

    CSV format: prompt,question_type,difficulty_level,options,answer,explanation,tags
    options/answer are JSON (quote the cell, e.g. "[""A"",""B""]"). tags is ';'-separated.
    First row must be headers.
    """
    text = await _read_import_text(file)
    reader = csv.DictReader(io.StringIO(text))

    skipped = 0
    errors = []
    rows: list[dict] = []
    seen_rows: set[str] = set()

    for row_num, row in enumerate(reader, start=2):
        prompt = (row.get("prompt") or "").strip()
        if not prompt:
            skipped += 1
            continue

        try:
            options_raw = (row.get("options") or "").strip()
            answer_raw = (row.get("answer") or "").strip()
            tags = [t.strip() for t in (row.get("tags") or "").split(";") if t.strip()]
            parsed_row = {
                "prompt": prompt,
                "question_type": (row.get("question_type") or "mcq").strip() or "mcq",
                "difficulty_level": (row.get("difficulty_level") or "A1").strip() or "A1",
                "options": json.loads(options_raw) if options_raw else None,
                "answer": json.loads(answer_raw) if answer_raw else None,
                "explanation": (row.get("explanation") or "").strip() or None,
                "tags": tags or None,
            }
            signature = json.dumps(parsed_row, sort_keys=True)
            if signature in seen_rows:
                skipped += 1
                continue
            seen_rows.add(signature)
            rows.append(parsed_row)
        except Exception as e:
            errors.append(f"Row {row_num}: {str(e)}")

    created = await _bulk_insert_rows(db, QuestionItem, rows)
    await db.commit()

    return ApiResponse(
        success=True,
        message=f"Imported {created} questions, skipped {skipped} blank rows",
        data={"created": created, "skipped": skipped, "errors": errors[:10]}
    )


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


@router.post("/test-exams/bulk-import", response_model=ApiResponse[dict])
async def bulk_import_test_exams(
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
) -> ApiResponse[dict]:
    """
    Bulk import test exams from CSV or PDF containing CSV-formatted text.

    CSV format: title,description,level,duration_minutes,passing_score,question_ids,is_published
    question_ids is a ';'-separated list of question UUIDs. First row must be headers.
    """
    text = await _read_import_text(file)
    reader = csv.DictReader(io.StringIO(text))

    skipped = 0
    errors = []
    pending: dict[str, dict] = {}

    for row_num, row in enumerate(reader, start=2):
        title = (row.get("title") or "").strip()
        if not title:
            skipped += 1
            continue

        if title in pending:
            skipped += 1
            continue

        try:
            question_ids = [q.strip() for q in (row.get("question_ids") or "").split(";") if q.strip()]
            published_raw = (row.get("is_published") or "").strip().lower()
            pending[title] = {
                "title": title,
                "description": (row.get("description") or "").strip() or None,
                "level": (row.get("level") or "A1").strip() or "A1",
                "duration_minutes": int(row.get("duration_minutes") or 20),
                "passing_score": int(row.get("passing_score") or 70),
                "question_ids": question_ids or None,
                "is_published": published_raw in ("true", "1", "yes", "có"),
            }
        except Exception as e:
            errors.append(f"Row {row_num}: {str(e)}")

    existing = set(
        await db.scalars(select(TestExam.title).where(TestExam.title.in_(pending)))
    ) if pending else set()
    skipped += len(existing)
    created = await _bulk_insert_rows(
        db,
        TestExam,
        [value for key, value in pending.items() if key not in existing],
    )
    await db.commit()

    return ApiResponse(
        success=True,
        message=f"Imported {created} test exams, skipped {skipped} duplicates/blank rows",
        data={"created": created, "skipped": skipped, "errors": errors[:10]}
    )
