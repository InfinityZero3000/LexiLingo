"""The admin activity timeline must render a learner who has finished a lesson."""

from app.models.progress import LessonCompletion


async def test_activity_timeline_includes_lesson_completions(
    async_client, db_session, admin_headers, test_user, test_lesson
):
    db_session.add(
        LessonCompletion(user_id=test_user.id, lesson_id=test_lesson.id, is_passed=True, best_score=85)
    )
    await db_session.commit()

    response = await async_client.get(
        f"/api/v1/admin/users/{test_user.id}/activity", headers=admin_headers
    )

    assert response.status_code == 200, response.text
    [entry] = response.json()["data"]
    assert entry["activity_type"] == "lesson_completed"
    assert "85%" in entry["description"]


async def test_user_role_filter_includes_accounts_that_have_no_role_row(
    async_client, admin_headers, test_user
):
    # They are listed as "User" (role_level 0), so filtering by "User" must keep them.
    assert test_user.role_id is None

    response = await async_client.get("/api/v1/admin/users?role=0", headers=admin_headers)

    assert [u["email"] for u in response.json()["data"]["users"]] == [test_user.email]
