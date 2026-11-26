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
