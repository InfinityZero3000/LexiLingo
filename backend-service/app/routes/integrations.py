"""Read-only API namespace for approved partner integrations."""

from uuid import UUID

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.partner_auth import require_partner_api_key
from app.core.database import get_db
from app.routes.books import (
    browse_books,
    get_book_quiz,
    get_recommended_books,
    search_books,
)
from app.routes.course_categories import (
    get_categories as get_course_categories,
    get_category,
    get_category_by_slug,
    get_courses_by_category,
)
from app.routes.courses import get_course, get_courses
from app.routes.games import get_game_categories
from app.routes.learning import get_lesson_content, get_lesson_context
from app.routes.news import get_article_quiz, get_categories as get_news_categories, get_news
from app.routes.podcasts import (
    get_curated_podcasts,
    get_podcast_episodes,
    search_podcasts,
)
from app.routes.vocabulary import (
    get_vocabulary_item,
    get_vocabulary_items,
    get_word_of_day,
)
from app.routes.youtube import (
    get_captions,
    get_channel_videos,
    get_curated_channels,
    search_videos,
)
from app.schemas.common import PaginatedResponse
from app.schemas.course import CourseListItem


router = APIRouter(dependencies=[Depends(require_partner_api_key)])
def _add(path: str, endpoint, *, methods: list[str] = ["GET"], **kwargs) -> None:
    router.add_api_route(path, endpoint, methods=methods, **kwargs)


async def _get_courses_for_partner(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    language: str | None = Query(None),
    level: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
):
    return await get_courses(
        page=page,
        page_size=page_size,
        language=language,
        level=level,
        db=db,
        current_user=None,
    )


async def _get_course_for_partner(
    course_id: UUID,
    db: AsyncSession = Depends(get_db),
):
    return await get_course(course_id=course_id, db=db, current_user=None)


_add(
    "/courses",
    _get_courses_for_partner,
    response_model=PaginatedResponse[CourseListItem],
    summary="List published courses for partner integrations",
)

# Course catalog and reference data.
_add("/courses/{course_id}", _get_course_for_partner)
_add("/categories", get_course_categories)
_add("/categories/{category_id}", get_category)
_add("/categories/slug/{slug}", get_category_by_slug)
_add("/categories/{category_id}/courses", get_courses_by_category)

# Public lesson content. The source handlers currently require a JWT even though
# these functions do not read user state; wrappers keep the legacy routes strict.
async def _get_lesson_content_for_partner(
    lesson_id: UUID,
    db: AsyncSession = Depends(get_db),
):
    return await get_lesson_content(lesson_id=lesson_id, db=db, current_user=None)  # type: ignore[arg-type]


async def _get_lesson_context_for_partner(
    lesson_id: UUID,
    db: AsyncSession = Depends(get_db),
):
    return await get_lesson_context(lesson_id=lesson_id, db=db, current_user=None)  # type: ignore[arg-type]


_add("/lessons/{lesson_id}/content", _get_lesson_content_for_partner)
_add("/lessons/{lesson_id}/context", _get_lesson_context_for_partner)

# Master vocabulary data; user collections, review, stats and decks are excluded.
_add("/vocabulary/word-of-day", get_word_of_day)
_add("/vocabulary/items", get_vocabulary_items)
_add("/vocabulary/items/{vocabulary_id}", get_vocabulary_item)

# Game metadata; generated game sessions remain user-authenticated.
async def _get_game_categories_for_partner(db: AsyncSession = Depends(get_db)):
    return await get_game_categories(db=db, current_user=None)  # type: ignore[arg-type]


_add("/games/categories", _get_game_categories_for_partner)

# Public content catalogs.
_add("/news", get_news)
_add("/news/categories", get_news_categories)
_add("/news/{article_id}/quiz", get_article_quiz)
_add("/podcasts/search", search_podcasts)
_add("/podcasts/curated", get_curated_podcasts)
_add("/podcasts/episodes", get_podcast_episodes)
_add("/books/recommended", get_recommended_books)
_add("/books/search", search_books)
_add("/books/browse", browse_books)
_add("/books/{book_id}/quiz", get_book_quiz)
_add("/youtube/channels", get_curated_channels)
_add("/youtube/search", search_videos)
_add("/youtube/captions/{video_id}", get_captions)
_add("/youtube/channels/{channel_id}/videos", get_channel_videos)
