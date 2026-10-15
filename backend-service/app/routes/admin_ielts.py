"""Admin CRUD for IELTS mock tests, with a publish gate that checks the paper
is actually sittable.

Nothing validates paper shape on write elsewhere, and the failure mode is the
expensive one: a missing answer key is only discovered by a learner who has
already spent an hour on the paper. `validate_test_content` is therefore run
before publish, not after.
"""

from __future__ import annotations

import logging
import os
import uuid as uuid_lib
from pathlib import Path
from typing import Any, Optional
from uuid import UUID

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from pydantic import BaseModel, Field
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_admin as require_admin
from app.models.ielts import IeltsAttempt, IeltsTest
from app.models.user import User
from app.schemas.response import ApiResponse
from app.services.ielts_service import (
    iter_productive_parts,
    iter_questions,
    iter_sections,
)

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/admin/ielts", tags=["Admin IELTS"])

_SKILLS = ("listening", "reading", "writing", "speaking")


class IeltsTestPayload(BaseModel):
    title: str
    description: Optional[str] = None
    test_type: str = "academic"
    skill_scope: str = "full"
    target_band: Optional[str] = None
    slug: Optional[str] = None
    content: Optional[dict] = None
    is_published: Optional[bool] = None


class IeltsTestDetail(BaseModel):
    id: str
    title: str
    description: Optional[str] = None
    test_type: str
    skill_scope: str
    target_band: Optional[str] = None
    slug: Optional[str] = None
    content: Optional[dict] = None
    is_published: bool
    question_count: int = 0
    attempt_count: int = 0
    created_at: Optional[str] = None
    updated_at: Optional[str] = None


_FULL_SECTION_QUESTIONS = 40
_MIN_BAND_QUESTIONS = 10


def validate_test_content(content: dict | None, skill_scope: str = "full") -> list[str]:
    """Blocking problems that would make the paper unsittable or ungradable."""
    problems: list[str] = []
    sections = list(iter_sections(content))
    if not sections:
        problems.append("Test has no sections")
        return problems

    present = {(s.get("skill") or "").strip().lower() for s in sections}
    if skill_scope == "full":
        missing = [s for s in _SKILLS if s not in present]
        if missing:
            problems.append(
                f"A full test needs all four skills; missing: {', '.join(missing)}"
            )
    elif skill_scope not in present:
        problems.append(f"skill_scope is '{skill_scope}' but no such section exists")

    for skill in ("listening", "reading"):
        questions = list(iter_questions(content, skill))
        if skill in present and not questions:
            problems.append(f"{skill.title()} section has no questions")
        elif skill in present:
            # The band tables are defined on 40 questions and a shorter paper is
            # scaled up to that equivalent, so 5/5 would report band 9. A paper
            # that claims to be a full IELTS test has to carry the real length;
            # a practice set may be shorter but not so short that scaling
            # invents a band.
            floor = (
                _FULL_SECTION_QUESTIONS if skill_scope == "full"
                else _MIN_BAND_QUESTIONS
            )
            if len(questions) < floor:
                problems.append(
                    f"{skill.title()} section has {len(questions)} questions; "
                    f"at least {floor} are needed for the band to mean anything"
                )
        for question in questions:
            key = question.get("key")
            if not key:
                problems.append(f"A {skill} question has no 'key'")
                continue
            accepted = question.get("accepted_answers") or question.get("correct_answer")
            if not accepted:
                problems.append(f"{skill.title()} question '{key}' has no answer key")

    keys = [str(q.get("key")) for q in iter_questions(content) if q.get("key")]
    duplicates = {k for k in keys if keys.count(k) > 1}
    if duplicates:
        problems.append(f"Duplicate question keys: {', '.join(sorted(duplicates))}")

    for skill, part in iter_productive_parts(content):
        part_key = part.get("part_key")
        if not part.get("prompt") and not part.get("cue_card"):
            problems.append(f"{skill.title()} part '{part_key}' has no prompt")

    for section in sections:
        if (section.get("skill") or "").lower() == "listening":
            for part in section.get("parts") or []:
                if isinstance(part, dict) and not part.get("audio_url"):
                    problems.append(
                        f"Listening part {part.get('order') or '?'} has no audio_url"
                    )
    return problems


def _detail(test: IeltsTest, attempt_count: int = 0) -> IeltsTestDetail:
    return IeltsTestDetail(
        id=str(test.id),
        title=test.title,
        description=test.description,
        test_type=test.test_type,
        skill_scope=test.skill_scope,
        target_band=test.target_band,
        slug=test.slug,
        content=test.content,
        is_published=test.is_published,
        question_count=len(list(iter_questions(test.content))),
        attempt_count=attempt_count,
        created_at=test.created_at.isoformat() if test.created_at else None,
        updated_at=test.updated_at.isoformat() if test.updated_at else None,
    )


@router.get("/tests", response_model=ApiResponse[list[IeltsTestDetail]])
async def admin_list_tests(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin),
):
    result = await db.execute(
        select(IeltsTest).order_by(IeltsTest.created_at.desc()).limit(limit).offset(offset)
    )
    tests = result.scalars().all()
    counts = dict(
        (
            await db.execute(
                select(IeltsAttempt.test_id, func.count(IeltsAttempt.id)).group_by(
                    IeltsAttempt.test_id
                )
            )
        ).all()
    )
    return ApiResponse(data=[_detail(t, counts.get(t.id, 0)) for t in tests])


@router.get("/tests/{test_id}", response_model=ApiResponse[IeltsTestDetail])
async def admin_get_test(
    test_id: UUID,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin),
):
    test = await db.get(IeltsTest, test_id)
    if not test:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Test not found")
    return ApiResponse(data=_detail(test))


@router.post("/tests", response_model=ApiResponse[IeltsTestDetail])
async def admin_create_test(
    payload: IeltsTestPayload,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin),
):
    test = IeltsTest(
        title=payload.title,
        description=payload.description,
        test_type=payload.test_type,
        skill_scope=payload.skill_scope,
        target_band=payload.target_band,
        slug=payload.slug,
        content=payload.content or {"sections": []},
        is_published=False,
        created_by=admin_user.id,
    )
    db.add(test)
    await db.commit()
    await db.refresh(test)
    return ApiResponse(message="Created", data=_detail(test))


@router.put("/tests/{test_id}", response_model=ApiResponse[IeltsTestDetail])
async def admin_update_test(
    test_id: UUID,
    payload: IeltsTestPayload,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin),
):
    test = await db.get(IeltsTest, test_id)
    if not test:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Test not found")

    for field in ("title", "description", "test_type", "skill_scope", "target_band", "slug"):
        value = getattr(payload, field)
        if value is not None:
            setattr(test, field, value)
    if payload.content is not None:
        test.content = payload.content

    # Publishing is the gate — an unpublished paper may be half-written.
    if payload.is_published is not None:
        if payload.is_published and not test.is_published:
            problems = validate_test_content(test.content, test.skill_scope)
            if problems:
                raise HTTPException(
                    status.HTTP_400_BAD_REQUEST,
                    {"message": "Test cannot be published", "problems": problems},
                )
        test.is_published = payload.is_published

    await db.commit()
    await db.refresh(test)
    return ApiResponse(message="Updated", data=_detail(test))


@router.post("/tests/{test_id}/validate", response_model=ApiResponse[dict])
async def admin_validate_test(
    test_id: UUID,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin),
):
    test = await db.get(IeltsTest, test_id)
    if not test:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Test not found")
    problems = validate_test_content(test.content, test.skill_scope)
    counts = {
        skill: len(list(iter_questions(test.content, skill)))
        for skill in ("listening", "reading")
    }
    counts["productive_parts"] = len(list(iter_productive_parts(test.content)))
    return ApiResponse(
        data={"publishable": not problems, "problems": problems, "counts": counts}
    )


@router.delete("/tests/{test_id}", response_model=ApiResponse[dict])
async def admin_delete_test(
    test_id: UUID,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin),
):
    test = await db.get(IeltsTest, test_id)
    if not test:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Test not found")
    await db.delete(test)
    await db.commit()
    return ApiResponse(message="Deleted", data={"id": str(test_id)})


@router.get("/attempts", response_model=ApiResponse[list[dict]])
async def admin_list_attempts(
    test_id: Optional[UUID] = Query(None),
    limit: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin),
):
    query = select(IeltsAttempt).order_by(IeltsAttempt.started_at.desc()).limit(limit)
    if test_id:
        query = query.where(IeltsAttempt.test_id == test_id)
    result = await db.execute(query)
    return ApiResponse(
        data=[
            {
                "attempt_id": str(a.id),
                "user_id": str(a.user_id),
                "test_id": str(a.test_id),
                "status": a.status,
                "overall_band": float(a.overall_band) if a.overall_band is not None else None,
                "started_at": a.started_at.isoformat() if a.started_at else None,
                "submitted_at": a.submitted_at.isoformat() if a.submitted_at else None,
            }
            for a in result.scalars().all()
        ]
    )


_MEDIA_DIR = Path("/app/data/media")
_AUDIO_TYPES = {"audio/mpeg", "audio/mp3", "audio/wav", "audio/x-wav", "audio/mp4", "audio/aac"}
_AUDIO_EXTENSIONS = {".mp3", ".wav", ".m4a", ".aac"}
_MAX_AUDIO_BYTES = 20 * 1024 * 1024


@router.post("/upload-audio", response_model=ApiResponse[dict])
async def admin_upload_listening_audio(
    file: UploadFile = File(...),
    admin_user: User = Depends(require_admin),
):
    """Store a Listening recording and return the URL to put in `audio_url`.

    A full Listening section is four recordings and IELTS plays each once, so
    this is the one asset an IELTS paper cannot be authored without.
    """
    if file.content_type not in _AUDIO_TYPES:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            f"Invalid audio type: {file.content_type}. Allowed: {', '.join(sorted(_AUDIO_TYPES))}",
        )
    contents = await file.read()
    if len(contents) > _MAX_AUDIO_BYTES:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, "Audio too large. Maximum 20MB allowed."
        )

    if os.path.isdir(_MEDIA_DIR):
        target_dir = _MEDIA_DIR / "ielts"
        url_prefix = "/media/ielts"
    else:
        target_dir = Path(__file__).resolve().parent.parent.parent / "static" / "ielts"
        url_prefix = "/static/ielts"
    target_dir.mkdir(parents=True, exist_ok=True)

    extension = Path(file.filename or "audio.mp3").suffix.lower()
    if extension not in _AUDIO_EXTENSIONS:
        extension = ".mp3"
    safe_name = f"{uuid_lib.uuid4().hex}{extension}"
    (target_dir / safe_name).write_bytes(contents)

    return ApiResponse(
        message="Audio uploaded",
        data={"url": f"{url_prefix}/{safe_name}", "size_bytes": len(contents)},
    )
