"""Course cards show progress, so both list endpoints must send it."""

from httpx import AsyncClient

from app.models.course_category import CourseCategory
from app.models.progress import UserCourseProgress


async def test_course_lists_carry_the_learners_progress(
    async_client: AsyncClient, auth_headers: dict, test_user, test_course, db_session
):
    category = CourseCategory(name="Travel", slug="travel-progress")
    db_session.add(category)
    await db_session.flush()
    test_course.category_id = category.id
    db_session.add(
        UserCourseProgress(
            user_id=test_user.id, course_id=test_course.id, progress_percentage=50.0
        )
    )
    await db_session.commit()
    course_id, category_id = str(test_course.id), category.id

    for url in ("/api/v1/courses", f"/api/v1/categories/{category_id}/courses"):
        response = await async_client.get(url, headers=auth_headers)

        assert response.status_code == 200, response.text
        item = next(c for c in response.json()["data"] if c["id"] == course_id)
        assert (item["is_enrolled"], item["user_progress"]) == (True, 50.0), url
