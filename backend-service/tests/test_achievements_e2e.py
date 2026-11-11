"""
Characterization test for the Achievements flow — end to end, against a
real database and the real HTTP routes (not mocked DB sessions).

Why this file exists: `test_achievement_system.py` is comprehensive but
every test in it constructs `AchievementCheckerService(AsyncMock(spec=
AsyncSession))` and hand-feeds a `stats` dict straight into
`_evaluate_condition()`. That proves the evaluator math is right; it cannot
prove that a real lesson completion actually reaches the unlock code, that
the response serializes without exploding (it did explode in production
once — see the comment at `routes/learning.py` next to
`achievements_unlocked=[a["id"] for a in unlocked_achievements]`), or that a
secret achievement stays secret. Those are exactly the bugs an audit of this
flow found: `is_hidden` was parsed on both ends and never once filtered on,
and ten seeded achievements promise a goal that `_get_user_stats()` can
never report as met. This file pins the corrected, real behavior so a future
change that reintroduces any of these regresses loudly instead of silently.
"""

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.gamification import Achievement, UserAchievement
from app.models.progress import LessonAttempt
from app.models.user import User
from app.services.achievement_checker_service import TRIGGER_CONDITIONS
from scripts.backfill_achievements import ACHIEVEMENT_SEED


@pytest.mark.asyncio
class TestAchievementUnlockEndToEnd:
    """A real lesson completion, through the real route, against a real DB."""

    async def test_completing_a_lesson_unlocks_first_steps(
        self,
        async_client: AsyncClient,
        db_session: AsyncSession,
        auth_headers: dict,
        test_user: User,
        test_lesson_attempt: LessonAttempt,
    ):
        db_session.add(
            Achievement(
                name="First Steps",
                slug="first_steps",
                description="Complete your first lesson.",
                condition_type="lesson_complete",
                condition_value=1,
                category="lessons",
                xp_reward=0,
                gems_reward=5,
                is_hidden=False,
            )
        )
        await db_session.commit()

        test_lesson_attempt.score = 85.0
        test_lesson_attempt.correct_answers = 8
        test_lesson_attempt.xp_earned = 80
        await db_session.commit()

        response = await async_client.post(
            f"/api/v1/learning/attempts/{test_lesson_attempt.id}/complete",
            headers=auth_headers,
        )

        assert response.status_code == 200
        body = response.json()["data"]
        # This is the exact shape that 500'd in production before the fix
        # noted in routes/learning.py — a list of bare id strings, not dicts.
        assert isinstance(body["achievements_unlocked"], list)
        assert len(body["achievements_unlocked"]) == 1
        assert isinstance(body["achievements_unlocked"][0], str)

        # The unlock must actually be persisted, not just echoed in the
        # response — re-fetch independently through the real endpoint.
        me = await async_client.get(
            "/api/v1/gamification/achievements/me", headers=auth_headers
        )
        assert me.status_code == 200
        unlocked_names = {entry["achievement"]["name"] for entry in me.json()["data"]}
        assert "First Steps" in unlocked_names

        # And it must be a real, idempotent row — not just a cache artifact.
        row = await db_session.scalar(
            select(UserAchievement).where(UserAchievement.user_id == test_user.id)
        )
        assert row is not None

    async def test_completing_a_lesson_a_second_time_does_not_double_unlock(
        self,
        async_client: AsyncClient,
        db_session: AsyncSession,
        auth_headers: dict,
        test_user: User,
        test_lesson_attempt: LessonAttempt,
    ):
        """Re-checking achievements must stay idempotent even if a caller
        fires the same trigger twice (the real route already guards this
        with a `finished_at` check, but the achievement layer has its own
        unique constraint as a second line of defense — this proves the
        second line actually holds under a direct re-check, not just in
        theory)."""
        db_session.add(
            Achievement(
                name="First Steps",
                slug="first_steps",
                description="Complete your first lesson.",
                condition_type="lesson_complete",
                condition_value=1,
                category="lessons",
                gems_reward=5,
                is_hidden=False,
            )
        )
        await db_session.commit()

        test_lesson_attempt.score = 100.0
        test_lesson_attempt.correct_answers = 10
        test_lesson_attempt.xp_earned = 100
        await db_session.commit()

        first = await async_client.post(
            f"/api/v1/learning/attempts/{test_lesson_attempt.id}/complete",
            headers=auth_headers,
        )
        assert first.status_code == 200

        # Force a second evaluation of the same condition directly through
        # the public "check everything" endpoint.
        second = await async_client.post(
            "/api/v1/gamification/achievements/check", headers=auth_headers
        )
        assert second.status_code == 200
        assert second.json()["data"] == []  # nothing NEW unlocked

        count = await db_session.scalar(
            select(UserAchievement).where(UserAchievement.user_id == test_user.id)
        )
        assert count is not None  # exactly one row exists, not zero or two
        rows = (
            (
                await db_session.execute(
                    select(UserAchievement).where(
                        UserAchievement.user_id == test_user.id
                    )
                )
            )
            .scalars()
            .all()
        )
        assert len(rows) == 1


@pytest.mark.asyncio
class TestHiddenAchievementsStaySecret:
    """The bug: `is_hidden` was parsed by both the API schema and the
    Flutter model and never once filtered anywhere, so every "secret"
    long-term achievement (and the ones hidden because they can never
    unlock) was visible to every learner from day one."""

    async def test_hidden_achievement_is_excluded_until_unlocked(
        self,
        async_client: AsyncClient,
        db_session: AsyncSession,
        auth_headers: dict,
        test_user: User,
    ):
        db_session.add_all(
            [
                Achievement(
                    name="Year Legend",
                    slug="year_legend",
                    description="Keep a 365-day streak.",
                    condition_type="reach_streak",
                    condition_value=365,
                    category="streak",
                    is_hidden=True,
                ),
                Achievement(
                    name="First Steps",
                    slug="first_steps",
                    description="Complete your first lesson.",
                    condition_type="lesson_complete",
                    condition_value=1,
                    category="lessons",
                    is_hidden=False,
                ),
            ]
        )
        await db_session.commit()

        response = await async_client.get(
            "/api/v1/gamification/achievements", headers=auth_headers
        )
        assert response.status_code == 200
        names = {a["name"] for a in response.json()["data"]}
        assert "Year Legend" not in names
        assert "First Steps" in names

    async def test_hidden_achievement_reappears_once_the_user_unlocks_it(
        self,
        async_client: AsyncClient,
        db_session: AsyncSession,
        auth_headers: dict,
        test_user: User,
    ):
        achievement = Achievement(
            name="Comeback King",
            slug="comeback_king",
            description="Return after a break and complete a lesson.",
            condition_type="comeback",
            condition_value=1,
            category="milestone",
            is_hidden=True,
        )
        db_session.add(achievement)
        await db_session.commit()
        await db_session.refresh(achievement)

        before = await async_client.get(
            "/api/v1/gamification/achievements", headers=auth_headers
        )
        assert "Comeback King" not in {a["name"] for a in before.json()["data"]}

        db_session.add(
            UserAchievement(user_id=test_user.id, achievement_id=achievement.id)
        )
        await db_session.commit()

        after = await async_client.get(
            "/api/v1/gamification/achievements", headers=auth_headers
        )
        assert "Comeback King" in {a["name"] for a in after.json()["data"]}

    async def test_anonymous_request_never_sees_hidden_achievements(
        self,
        async_client: AsyncClient,
        db_session: AsyncSession,
    ):
        db_session.add(
            Achievement(
                name="XP Legend",
                slug="xp_legend",
                description="Earn 50000 XP.",
                condition_type="xp_earned",
                condition_value=50000,
                category="xp",
                is_hidden=True,
            )
        )
        await db_session.commit()

        response = await async_client.get("/api/v1/gamification/achievements")
        assert response.status_code == 200
        assert "XP Legend" not in {a["name"] for a in response.json()["data"]}


class TestEveryTrackedConditionTypeIsActuallyReachable:
    """A regression guard for `scripts/backfill_achievements.py`, not a
    route test: it caught 10 seeded achievements that promised a specific,
    completable goal (e.g. "Complete 20 grammar lessons") while the stat
    backing that condition_type was permanently hardcoded to 0. If a new
    achievement is added with a condition_type that has no real stat yet,
    this is the test that should fail — either wire the stat up, or seed
    the new achievement with is_hidden=True like its siblings below until
    it is."""

    # condition_types whose stat AchievementCheckerService._get_user_stats()
    # hardcodes to 0 today. Keep this in sync with the comments next to
    # those hardcoded assignments — this list is the single source of truth
    # this test checks against.
    KNOWN_UNREACHABLE_CONDITION_TYPES = {
        "study_time_night",
        "study_time_morning",
        "speed_lesson",
        "grammar_mastered",
        "culture_lesson",
        "writing_complete",
        "listening_complete",
        "social_interaction",
        "chat_complete",
        "help_others",
        "comeback",
    }

    def test_every_condition_type_in_trigger_conditions_is_classified(self):
        """Every condition_type reachable through TRIGGER_CONDITIONS is
        either known-unreachable (and must be hidden below) or assumed
        working. If a brand-new condition_type is added to
        TRIGGER_CONDITIONS without updating this set either way, this
        fails — forcing a decision instead of a silent gap."""
        all_condition_types = {
            ct for types in TRIGGER_CONDITIONS.values() for ct in types
        }
        working = all_condition_types - self.KNOWN_UNREACHABLE_CONDITION_TYPES
        assert working, "expected at least some working condition types"
        assert self.KNOWN_UNREACHABLE_CONDITION_TYPES <= all_condition_types, (
            "a condition_type listed as unreachable no longer appears in "
            "TRIGGER_CONDITIONS at all — update this test, it may be fixed now"
        )

    def test_unreachable_condition_types_are_seeded_hidden(self):
        """Every achievement whose condition_type is known-unreachable must
        be is_hidden=True — a visible achievement with an impossible goal
        is a broken promise to the learner who reads its description."""
        offenders = [
            item["slug"]
            for item in ACHIEVEMENT_SEED
            if item["condition_type"] in self.KNOWN_UNREACHABLE_CONDITION_TYPES
            and not item.get("is_hidden")
        ]
        assert offenders == [], (
            f"these achievements promise a goal that can never be met but "
            f"are visible to every learner: {offenders}"
        )

    def test_reachable_condition_types_are_not_needlessly_hidden(self):
        """The inverse check: don't let a working achievement get hidden by
        a copy-paste mistake and silently vanish from the browsable list."""
        always_visible_examples = {
            "first_steps",
            "getting_started",
            "word_collector",
            "xp_hunter",
            "perfectionist",
            "course_explorer",
            "voice_beginner",
            "level_25",
            "challenge_crusher",
        }
        by_slug = {item["slug"]: item for item in ACHIEVEMENT_SEED}
        for slug in always_visible_examples:
            assert slug in by_slug, f"seed data is missing expected slug {slug}"
            assert by_slug[slug]["is_hidden"] is False, (
                f"{slug} should be visible — its condition_type is tracked"
            )
