import uuid
from types import SimpleNamespace

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.course import Course, Lesson, Unit
from app.models.progress import LessonCompletion
from app.models.user import User
from app.services.lesson_unlock import LOCKED_DETAIL, sequence_locked_ids


def _lessons(n: int) -> list[SimpleNamespace]:
    return [SimpleNamespace(id=uuid.uuid4()) for _ in range(n)]


def test_only_the_first_lesson_is_open_with_no_progress():
    ls = _lessons(4)
    assert sequence_locked_ids(ls, set()) == {l.id for l in ls[1:]}


def test_passing_a_lesson_opens_the_next_one_only():
    ls = _lessons(4)
    assert sequence_locked_ids(ls, {ls[0].id}) == {ls[2].id, ls[3].id}


def test_a_passed_lesson_never_locks_even_if_its_predecessor_is_unpassed():
    ls = _lessons(3)
    assert sequence_locked_ids(ls, {ls[2].id}) == {ls[1].id}


def test_empty_course_has_nothing_locked():
    assert sequence_locked_ids([], set()) == set()


async def _ordered(db: AsyncSession, course: Course) -> list[Lesson]:
    units = (
        await db.execute(
            select(Unit).where(Unit.course_id == course.id).order_by(Unit.order_index)
        )
    ).scalars().all()
    out: list[Lesson] = []
    for unit in units:
        out.extend(
            (
                await db.execute(
                    select(Lesson)
                    .where(Lesson.unit_id == unit.id)
                    .order_by(Lesson.order_index)
                )
            ).scalars().all()
        )
    return out


@pytest.mark.asyncio
class TestLockedEndpoints:
    async def test_start_and_content_refuse_a_locked_lesson(
        self,
        async_client: AsyncClient,
        db_session: AsyncSession,
        auth_headers: dict,
        test_course_with_units: Course,
    ):
        ls = await _ordered(db_session, test_course_with_units)
        for path in ("start",):
            r = await async_client.post(
                f"/api/v1/learning/lessons/{ls[1].id}/{path}", headers=auth_headers
            )
            assert r.status_code == 409
            assert LOCKED_DETAIL in r.text
        r = await async_client.get(
            f"/api/v1/learning/lessons/{ls[2].id}/content", headers=auth_headers
        )
        assert r.status_code == 409

    async def test_first_lesson_opens_and_passing_it_opens_the_next(
        self,
        async_client: AsyncClient,
        db_session: AsyncSession,
        auth_headers: dict,
        test_user: User,
        test_course_with_units: Course,
    ):
        ls = await _ordered(db_session, test_course_with_units)
        ok = await async_client.post(
            f"/api/v1/learning/lessons/{ls[0].id}/start", headers=auth_headers
        )
        assert ok.status_code == 200
        db_session.add(
            LessonCompletion(
                user_id=test_user.id, lesson_id=ls[0].id, is_passed=True, best_score=90
            )
        )
        await db_session.commit()
        nxt = await async_client.post(
            f"/api/v1/learning/lessons/{ls[1].id}/start", headers=auth_headers
        )
        assert nxt.status_code == 200
        still = await async_client.post(
            f"/api/v1/learning/lessons/{ls[2].id}/start", headers=auth_headers
        )
        assert still.status_code == 409

    async def test_course_detail_reports_the_same_locks_as_the_roadmap(
        self,
        async_client: AsyncClient,
        db_session: AsyncSession,
        auth_headers: dict,
        test_course_with_units: Course,
    ):
        test_course_with_units.level = "A1"
        await db_session.commit()
        detail = await async_client.get(
            f"/api/v1/courses/{test_course_with_units.id}", headers=auth_headers
        )
        road = await async_client.get(
            f"/api/v1/learning/courses/{test_course_with_units.id}/roadmap",
            headers=auth_headers,
        )
        assert detail.status_code == 200 and road.status_code == 200
        d = [
            l["is_locked"]
            for u in detail.json()["data"]["units"]
            for l in u["lessons"]
        ]
        r = [
            l["is_locked"]
            for u in road.json()["data"]["units"]
            for l in u["lessons"]
        ]
        assert d == r == [False, True, True, True, True, True]


@pytest.mark.asyncio
async def test_next_lesson_crosses_units_and_skips_unplayable(
    db_session: AsyncSession, test_course_with_units: Course
):
    from app.services.lesson_unlock import next_playable_lesson_id

    ls = await _ordered(db_session, test_course_with_units)
    assert await next_playable_lesson_id(db_session, ls[0]) == ls[1].id
    assert await next_playable_lesson_id(db_session, ls[1]) == ls[2].id
    ls[2].content = {"exercises": []}
    await db_session.commit()
    assert await next_playable_lesson_id(db_session, ls[1]) == ls[3].id
    assert await next_playable_lesson_id(db_session, ls[5]) is None
