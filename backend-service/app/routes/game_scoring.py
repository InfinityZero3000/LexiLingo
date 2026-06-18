"""Game session completion — scoring, XP award, and achievement evaluation."""
import logging
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.cache import build_cache_key, delete_cached, invalidate_cache
from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.crud.games import get_game_session_for_update
from app.models.user import User
from app.schemas.games import GameSessionCompleteRequest, GameSessionCompleteResponse
from app.services import check_achievements_for_user
from app.services.game_scoring_service import GameScoringError, score_game
from app.services.streak_service import update_user_streak
from app.services.xp_service import award_xp_transaction, get_existing_xp_award

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/games", tags=["Games"])

GAME_SESSION_TTL_SECONDS = 2 * 60 * 60


@router.post(
    "/sessions/{session_id}/complete",
    response_model=GameSessionCompleteResponse,
)
async def complete_game_session(
    session_id: uuid.UUID,
    body: GameSessionCompleteRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    session = await get_game_session_for_update(db, session_id=session_id)
    if session is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Game session not found.")
    if session.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="This game session belongs to another user.")

    if session.completed_at is not None and session.xp_awarded:
        existing_award = await get_existing_xp_award(db=db, user=current_user, source="game", source_id=str(session.id))
        if existing_award is None:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Completed game session has no XP transaction.")
        score_result = (session.session_data or {}).get("score_result") or {}
        return GameSessionCompleteResponse(
            session_id=str(session.id),
            game_type=session.game_type,
            correct_count=session.correct_answers or 0,
            total_count=session.total_questions or 0,
            raw_xp=score_result.get("raw_xp", session.xp_earned or 0),
            penalties=score_result.get("penalties", 0),
            base_xp=score_result.get("base_xp", existing_award.base_xp),
            xp_awarded=existing_award.xp_awarded,
            award_status="already_awarded",
            duration_seconds=session.duration_seconds or 0,
            xp_result=existing_award.to_dict(),
        )

    if session.completed_at is not None or session.xp_awarded:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Game session is in an inconsistent completion state.")

    started_at = session.started_at or session.created_at
    if started_at.tzinfo is None:
        started_at = started_at.replace(tzinfo=timezone.utc)
    completed_at = datetime.now(timezone.utc)
    duration_seconds = max(0, int((completed_at - started_at).total_seconds()))

    if duration_seconds > GAME_SESSION_TTL_SECONDS:
        raise HTTPException(status_code=status.HTTP_410_GONE, detail="Game session has expired.")
    if duration_seconds < 5:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Game session completed too quickly.")

    session_data = session.session_data or {}
    expected_items = session_data.get("expected_items") or []
    hint_costs = session_data.get("hint_costs") or []
    hint_penalty = sum(hint_costs[:body.hints_used])

    try:
        score = score_game(
            game_type=session.game_type,
            expected_items=expected_items,
            submitted_answers=[answer.model_dump() for answer in body.answers],
            hint_penalty=hint_penalty,
        )
    except GameScoringError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    xp_result = await award_xp_transaction(
        db=db,
        user=current_user,
        source="game",
        base_xp=score.final_base_xp,
        source_id=str(session.id),
        source_detail=session.game_type,
        commit=False,
    )

    session.score = score.correct_count
    session.correct_answers = score.correct_count
    session.total_questions = score.total_count
    session.duration_seconds = duration_seconds
    session.xp_earned = xp_result.xp_awarded
    session.xp_awarded = True
    session.completed_at = completed_at
    session.session_data = {
        **session_data,
        "submitted_answers": [answer.model_dump() for answer in body.answers],
        "client_duration_seconds": body.client_duration_seconds,
        "hints_used": body.hints_used,
        "score_result": {
            "raw_xp": score.raw_xp,
            "penalties": score.penalties,
            "base_xp": score.final_base_xp,
        },
    }

    try:
        await update_user_streak(db, current_user.id)
    except Exception as e:
        logger.error("Error updating streak on game completion: %s", e, exc_info=True)

    await db.commit()
    await invalidate_cache("leaderboard")

    try:
        unlocked_achievements = await check_achievements_for_user(db, current_user.id, "game_complete")
        if unlocked_achievements:
            await db.commit()
            await delete_cached(build_cache_key("achievements_me", user_id=str(current_user.id)))
            await delete_cached(build_cache_key("wallet", user_id=str(current_user.id)))
    except Exception:
        logger.exception("Achievement evaluation failed after game session %s", session.id)
        await db.rollback()

    return GameSessionCompleteResponse(
        session_id=str(session.id),
        game_type=session.game_type,
        correct_count=score.correct_count,
        total_count=score.total_count,
        raw_xp=score.raw_xp,
        penalties=score.penalties,
        base_xp=score.final_base_xp,
        xp_awarded=xp_result.xp_awarded,
        award_status=("awarded" if xp_result.xp_awarded > 0 else "no_reward"),
        duration_seconds=duration_seconds,
        xp_result=xp_result.to_dict(),
    )
