"""Synced mistake notebook API routes."""

import hashlib
import uuid
from datetime import UTC, datetime
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.mistake import MistakeNotebookEntry
from app.models.user import User
from app.schemas.common import ApiResponse, MessageResponse
from app.schemas.mistakes import (
    MistakeNotebookEntryCreate,
    MistakeNotebookEntryResponse,
)

router = APIRouter(prefix="/mistakes", tags=["Mistakes"])


@router.get("", response_model=ApiResponse[list[MistakeNotebookEntryResponse]])
async def list_mistakes(
    status_filter: Literal["open", "reviewed", "all"] = Query("open", alias="status"),
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List the current user's mistake notebook entries."""
    query = select(MistakeNotebookEntry).where(
        MistakeNotebookEntry.user_id == current_user.id
    )
    if status_filter != "all":
        query = query.where(MistakeNotebookEntry.status == status_filter)

    result = await db.execute(
        query.order_by(MistakeNotebookEntry.created_at.desc())
        .limit(limit)
        .offset(offset)
    )
    entries = result.scalars().all()
    return ApiResponse(data=[_to_response(entry) for entry in entries])


@router.post(
    "",
    response_model=ApiResponse[MistakeNotebookEntryResponse],
    status_code=status.HTTP_201_CREATED,
)
async def create_mistake(
    payload: MistakeNotebookEntryCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Create or refresh a mistake notebook entry for the current user."""
    now = datetime.now(UTC)
    existing = await _find_existing_entry(db, current_user.id, payload)

    if existing:
        _refresh_existing_entry(existing, payload, now)
        await db.commit()
        await db.refresh(existing)
        return ApiResponse(data=_to_response(existing))

    entry = MistakeNotebookEntry(
        user_id=current_user.id,
        client_id=payload.id or None,
        source_type=payload.source_type,
        source_id=payload.source_id,
        source_title=payload.source_title,
        question=payload.question,
        question_hash=_question_hash(payload.question),
        selected_answer=payload.selected_answer,
        correct_answer=payload.correct_answer,
        explanation=payload.explanation,
        skill=payload.skill or "general",
        status="open",
        review_count=0,
        attempt_count=1,
        extra_data=payload.metadata,
        created_at=now,
        updated_at=now,
        reviewed_at=None,
        last_seen_at=now,
    )
    db.add(entry)
    await db.commit()
    await db.refresh(entry)
    return ApiResponse(data=_to_response(entry))


@router.patch(
    "/{mistake_id}/review",
    response_model=ApiResponse[MistakeNotebookEntryResponse],
)
async def mark_mistake_reviewed(
    mistake_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Mark a mistake as reviewed and increment its review count."""
    entry = await _get_user_entry(db, current_user.id, mistake_id)
    now = datetime.now(UTC)
    entry.status = "reviewed"
    entry.reviewed_at = now
    entry.review_count += 1
    entry.updated_at = now
    await db.commit()
    await db.refresh(entry)
    return ApiResponse(data=_to_response(entry))


@router.patch(
    "/{mistake_id}/reopen",
    response_model=ApiResponse[MistakeNotebookEntryResponse],
)
async def reopen_mistake(
    mistake_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Move a reviewed mistake back into the active review queue."""
    entry = await _get_user_entry(db, current_user.id, mistake_id)
    entry.status = "open"
    entry.reviewed_at = None
    entry.updated_at = datetime.now(UTC)
    await db.commit()
    await db.refresh(entry)
    return ApiResponse(data=_to_response(entry))


@router.delete("/{mistake_id}", response_model=MessageResponse)
async def delete_mistake(
    mistake_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Delete a current user's mistake notebook entry."""
    entry = await _get_user_entry(db, current_user.id, mistake_id)
    await db.delete(entry)
    await db.commit()
    return MessageResponse(message="Mistake deleted")


async def _find_existing_entry(
    db: AsyncSession,
    user_id: uuid.UUID,
    payload: MistakeNotebookEntryCreate,
) -> MistakeNotebookEntry | None:
    if payload.id:
        result = await db.execute(
            select(MistakeNotebookEntry).where(
                MistakeNotebookEntry.user_id == user_id,
                MistakeNotebookEntry.client_id == payload.id,
            )
        )
        existing = result.scalar_one_or_none()
        if existing:
            return existing

    result = await db.execute(
        select(MistakeNotebookEntry).where(
            MistakeNotebookEntry.user_id == user_id,
            MistakeNotebookEntry.source_type == payload.source_type,
            MistakeNotebookEntry.source_id == payload.source_id,
            MistakeNotebookEntry.question_hash == _question_hash(payload.question),
        )
    )
    return result.scalar_one_or_none()


async def _get_user_entry(
    db: AsyncSession,
    user_id: uuid.UUID,
    mistake_id: str,
) -> MistakeNotebookEntry:
    conditions = [MistakeNotebookEntry.client_id == mistake_id]
    try:
        conditions.append(MistakeNotebookEntry.id == uuid.UUID(mistake_id))
    except ValueError:
        pass

    result = await db.execute(
        select(MistakeNotebookEntry).where(
            MistakeNotebookEntry.user_id == user_id,
            or_(*conditions),
        )
    )
    entry = result.scalar_one_or_none()
    if not entry:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Mistake not found",
        )
    return entry


def _refresh_existing_entry(
    entry: MistakeNotebookEntry,
    payload: MistakeNotebookEntryCreate,
    now: datetime,
) -> None:
    entry.client_id = payload.id or entry.client_id
    entry.source_type = payload.source_type
    entry.source_id = payload.source_id
    entry.source_title = payload.source_title
    entry.question = payload.question
    entry.question_hash = _question_hash(payload.question)
    entry.selected_answer = payload.selected_answer
    entry.correct_answer = payload.correct_answer
    entry.explanation = payload.explanation
    entry.skill = payload.skill or entry.skill
    entry.extra_data = payload.metadata if payload.metadata is not None else entry.extra_data
    entry.status = "open"
    entry.reviewed_at = None
    entry.attempt_count += 1
    entry.last_seen_at = now
    entry.updated_at = now


def _to_response(entry: MistakeNotebookEntry) -> MistakeNotebookEntryResponse:
    return MistakeNotebookEntryResponse(
        id=entry.client_id or str(entry.id),
        source_type=entry.source_type,
        source_id=entry.source_id,
        source_title=entry.source_title,
        question=entry.question,
        selected_answer=entry.selected_answer,
        correct_answer=entry.correct_answer,
        explanation=entry.explanation,
        skill=entry.skill,
        status=entry.status,
        created_at=entry.created_at,
        updated_at=entry.updated_at,
        reviewed_at=entry.reviewed_at,
        review_count=entry.review_count,
        attempt_count=entry.attempt_count,
        metadata=entry.extra_data,
    )


def _question_hash(question: str) -> str:
    normalized = " ".join(question.lower().split())
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()
