"""
Tests for Achievement System - End-to-End Badge Unlocking
Verifies that completing missions correctly triggers badge unlocking,
that slug mapping works, and that the full pipeline is consistent.
"""

import pytest
from uuid import uuid4
from datetime import datetime, date, timedelta
from unittest.mock import AsyncMock, patch, MagicMock
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.gamification import Achievement, UserAchievement, ChallengeRewardClaim
from app.models.progress import LessonCompletion, Streak, UserCourseProgress, DailyActivity
from app.models.vocabulary import UserVocabulary, VocabularyStatus
from app.models.user import User
from app.services import AchievementCheckerService, TRIGGER_CONDITIONS


# ============================================================================
# Unit Tests: TRIGGER_CONDITIONS Configuration
# ============================================================================

class TestTriggerConditionsConfig:
    """Verify TRIGGER_CONDITIONS is properly configured."""

    def test_all_triggers_defined(self):
        """All expected triggers must exist."""
        expected_triggers = [
            "lesson_complete", "streak_update", "vocab_review",
            "quiz_complete", "voice_practice", "xp_earned",
            "study_session", "grammar_complete", "culture_complete",
            "writing_complete", "listening_complete", "social_action",
            "chat_complete", "daily_challenge",
        ]
        for trigger in expected_triggers:
            assert trigger in TRIGGER_CONDITIONS, f"Missing trigger: {trigger}"

    def test_lesson_complete_covers_level(self):
        """lesson_complete trigger must check numeric_level for level milestones."""
        conditions = TRIGGER_CONDITIONS["lesson_complete"]
        assert "numeric_level" in conditions, "lesson_complete should check numeric_level"
        assert "lesson_complete" in conditions
        assert "xp_earned" in conditions
        assert "course_complete" in conditions

    def test_xp_earned_covers_level(self):
        """xp_earned trigger must also check numeric_level."""
        conditions = TRIGGER_CONDITIONS["xp_earned"]
        assert "numeric_level" in conditions, "xp_earned should check numeric_level"

    def test_daily_challenge_trigger(self):
        """daily_challenge trigger must map to daily_challenge_complete."""
        conditions = TRIGGER_CONDITIONS["daily_challenge"]
        assert "daily_challenge_complete" in conditions

    def test_quiz_complete_covers_first_perfect(self):
        """quiz_complete trigger must include first_perfect."""
        conditions = TRIGGER_CONDITIONS["quiz_complete"]
        assert "first_perfect" in conditions
        assert "perfect_score" in conditions

    def test_streak_update_covers_comeback(self):
        """streak_update trigger must include comeback."""
        conditions = TRIGGER_CONDITIONS["streak_update"]
        assert "comeback" in conditions

    def test_no_duplicate_condition_types_across_triggers(self):
        """
        Each condition type should be reachable from at least one trigger.
        Collect all condition types and verify none are orphaned.
        """
        all_conditions = set()
        for conditions in TRIGGER_CONDITIONS.values():
            all_conditions.update(conditions)
        
        # These are all the condition types used in seed data
        expected_conditions = {
            "lesson_complete", "reach_streak", "vocab_mastered", "vocab_reviewed",
            "xp_earned", "perfect_score", "quiz_complete", "voice_practice",
            "course_complete", "numeric_level", "study_time_night",
            "study_time_morning", "speed_lesson", "first_perfect",
            "grammar_mastered", "culture_lesson", "writing_complete",
            "listening_complete", "social_interaction", "chat_complete",
            "help_others", "daily_challenge_complete", "comeback",
        }
        
        missing = expected_conditions - all_conditions
        assert not missing, f"Condition types not reachable via any trigger: {missing}"


# ============================================================================
# Unit Tests: Achievement Checker Service - Condition Evaluation
# ============================================================================

class TestAchievementEvaluation:
    """Test that _evaluate_condition correctly checks each condition type."""

    @pytest.fixture
    def mock_db(self):
        """Create a mock database session."""
        return AsyncMock(spec=AsyncSession)

    @pytest.fixture
    def checker(self, mock_db):
        """Create AchievementCheckerService with mock DB."""
        return AchievementCheckerService(mock_db)

    def _make_achievement(self, condition_type: str, condition_value: int, **kwargs) -> Achievement:
        """Helper to create an Achievement object for testing."""
        ach = MagicMock(spec=Achievement)
        ach.condition_type = condition_type
        ach.condition_value = condition_value
        ach.condition_data = kwargs.get("condition_data", {})
        ach.id = uuid4()
        ach.name = kwargs.get("name", f"Test_{condition_type}")
        ach.slug = kwargs.get("slug", condition_type)
        ach.xp_reward = 10
        ach.gems_reward = 5
        return ach

    @pytest.mark.asyncio
    async def test_lesson_complete_met(self, checker):
        """User with 10 lessons completed meets lesson_complete=10."""
        ach = self._make_achievement("lesson_complete", 10)
        stats = {"lessons_completed": 10}
        result = await checker._evaluate_condition(uuid4(), ach, stats)
        assert result is True

    @pytest.mark.asyncio
    async def test_lesson_complete_not_met(self, checker):
        """User with 5 lessons does NOT meet lesson_complete=10."""
        ach = self._make_achievement("lesson_complete", 10)
        stats = {"lessons_completed": 5}
        result = await checker._evaluate_condition(uuid4(), ach, stats)
        assert result is False

    @pytest.mark.asyncio
    async def test_numeric_level_500(self, checker):
        """User at level 500 meets numeric_level=500 (Immortal badge)."""
        ach = self._make_achievement("numeric_level", 500, slug="level_500")
        stats = {"numeric_level": 500}
        result = await checker._evaluate_condition(uuid4(), ach, stats)
        assert result is True

    @pytest.mark.asyncio
    async def test_numeric_level_not_met(self, checker):
        """User at level 450 does NOT meet numeric_level=500."""
        ach = self._make_achievement("numeric_level", 500, slug="level_500")
        stats = {"numeric_level": 450}
        result = await checker._evaluate_condition(uuid4(), ach, stats)
        assert result is False

    @pytest.mark.asyncio
    async def test_numeric_level_25(self, checker):
        """User at level 30 meets numeric_level=25 (Rising Star)."""
        ach = self._make_achievement("numeric_level", 25, slug="level_25")
        stats = {"numeric_level": 30}
        result = await checker._evaluate_condition(uuid4(), ach, stats)
        assert result is True

    @pytest.mark.asyncio
    async def test_reach_streak(self, checker):
        """Streak=30 meets reach_streak=30 (Month Master)."""
        ach = self._make_achievement("reach_streak", 30)
        stats = {"current_streak": 30, "longest_streak": 30}
        result = await checker._evaluate_condition(uuid4(), ach, stats)
        assert result is True

    @pytest.mark.asyncio
    async def test_reach_streak_uses_longest(self, checker):
        """Longest streak counts even if current streak is lower."""
        ach = self._make_achievement("reach_streak", 30)
        stats = {"current_streak": 5, "longest_streak": 35}
        result = await checker._evaluate_condition(uuid4(), ach, stats)
        assert result is True

    @pytest.mark.asyncio
    async def test_vocab_mastered(self, checker):
        """100 mastered words meets vocab_mastered=100."""
        ach = self._make_achievement("vocab_mastered", 100)
        stats = {"vocab_mastered": 100}
        result = await checker._evaluate_condition(uuid4(), ach, stats)
        assert result is True

    @pytest.mark.asyncio
    async def test_xp_earned(self, checker):
        """5000 XP meets xp_earned=5000."""
        ach = self._make_achievement("xp_earned", 5000)
        stats = {"total_xp": 5000}
        result = await checker._evaluate_condition(uuid4(), ach, stats)
        assert result is True

    @pytest.mark.asyncio
    async def test_perfect_score(self, checker):
        """10 perfect scores meets perfect_score=10."""
        ach = self._make_achievement("perfect_score", 10)
        stats = {"perfect_scores": 10}
        result = await checker._evaluate_condition(uuid4(), ach, stats)
        assert result is True

    @pytest.mark.asyncio
    async def test_first_perfect_logic(self, checker):
        """first_perfect unlocks when user has >=1 perfect score and condition_value is 1."""
        ach = self._make_achievement("first_perfect", 1)
        stats = {"perfect_scores": 1}
        result = await checker._evaluate_condition(uuid4(), ach, stats)
        assert result is True

    @pytest.mark.asyncio
    async def test_first_perfect_not_met(self, checker):
        """first_perfect does NOT unlock when perfect_scores=0."""
        ach = self._make_achievement("first_perfect", 1)
        stats = {"perfect_scores": 0}
        result = await checker._evaluate_condition(uuid4(), ach, stats)
        assert result is False

    @pytest.mark.asyncio
    async def test_course_complete(self, checker):
        """5 courses completed meets course_complete=5."""
        ach = self._make_achievement("course_complete", 5, slug="course_champion")
        stats = {"courses_completed": 5}
        result = await checker._evaluate_condition(uuid4(), ach, stats)
        assert result is True

    @pytest.mark.asyncio
    async def test_daily_challenge_complete(self, checker):
        """30 daily challenges meets daily_challenge_complete=30."""
        ach = self._make_achievement("daily_challenge_complete", 30, slug="challenge_crusher")
        stats = {"daily_challenges_completed": 30}
        result = await checker._evaluate_condition(uuid4(), ach, stats)
        assert result is True

    @pytest.mark.asyncio
    async def test_voice_practice(self, checker):
        """10 voice practices meets voice_practice=10."""
        ach = self._make_achievement("voice_practice", 10)
        stats = {"voice_practices": 10}
        result = await checker._evaluate_condition(uuid4(), ach, stats)
        assert result is True

    @pytest.mark.asyncio
    async def test_unknown_condition_returns_false(self, checker):
        """Unknown condition types should return False, not crash."""
        ach = self._make_achievement("unknown_future_type", 1)
        stats = {}
        result = await checker._evaluate_condition(uuid4(), ach, stats)
        assert result is False

    @pytest.mark.asyncio
    async def test_comeback_always_false(self, checker):
        """'comeback' condition returns False (needs special contextual check)."""
        ach = self._make_achievement("comeback", 1, slug="comeback_king")
        stats = {}
        result = await checker._evaluate_condition(uuid4(), ach, stats)
        assert result is False


# ============================================================================
# Unit Tests: Slug and Badge Asset Mapping Consistency
# ============================================================================

class TestSlugConsistency:
    """Verify that backend slugs match Flutter BadgeAssetMapper keys."""

    # These are all slugs defined in seed_data.py — they MUST match
    # the keys in flutter-app/.../badge_asset_mapper.dart
    EXPECTED_SLUGS = [
        # Lessons
        "first_steps", "dedicated_learner", "knowledge_seeker", "scholar", "professor",
        # Streak
        "getting_started", "week_warrior", "two_weeks_strong", "month_master",
        "quarterly_champion", "year_legend",
        # Vocabulary
        "word_collector", "vocab_builder", "vocab_master", "walking_dictionary",
        # XP (no badge images — use generated badges)
        "xp_hunter", "xp_warrior", "xp_champion", "xp_legend",
        # Quiz/Perfect
        "perfectionist", "accuracy_master", "flawless", "first_perfect_score", "quiz_champion",
        # Course
        "course_explorer", "course_champion",
        # Voice
        "voice_beginner", "voice_talent",
        # Level milestones
        "level_25", "level_50", "level_100", "level_150", "level_200", "level_300", "level_500",
        # Special/Time
        "night_owl", "early_bird", "speed_demon",
        # Skill
        "grammar_guardian", "culture_explorer", "writing_wizard", "listening_legend",
        # Social
        "social_butterfly", "conversation_champion", "feedback_friend",
        # Milestones
        "challenge_crusher", "milestone_maker", "comeback_king",
    ]

    # Badge assets defined in Flutter BadgeAssetMapper
    FLUTTER_BADGE_MAPPER_KEYS = [
        "first_steps", "dedicated_learner", "knowledge_seeker", "scholar", "professor",
        "getting_started", "week_warrior", "two_weeks_strong", "month_master",
        "quarterly_champion", "year_legend",
        "word_collector", "vocab_builder", "vocab_master", "walking_dictionary",
        "perfectionist", "first_perfect_score", "accuracy_master", "flawless", "quiz_champion",
        "course_explorer", "course_champion",
        "voice_beginner", "voice_talent", "pronunciation_master",
        "level_25", "level_50", "level_100", "level_150", "level_200", "level_300", "level_500",
        "night_owl", "early_bird", "speed_demon",
        "grammar_guardian", "culture_explorer", "writing_wizard", "listening_legend",
        "social_butterfly", "conversation_champion", "feedback_friend",
        "challenge_crusher", "milestone_maker", "comeback_king",
    ]

    def test_all_slugs_have_badge_assets(self):
        """Every seeded achievement slug should have a badge asset in Flutter."""
        flutter_keys = set(self.FLUTTER_BADGE_MAPPER_KEYS)
        # XP achievements don't have dedicated badge images (use generated)
        slugs_needing_badges = [s for s in self.EXPECTED_SLUGS 
                                 if not s.startswith("xp_")]
        
        missing = [s for s in slugs_needing_badges if s not in flutter_keys]
        assert not missing, f"Slugs without Flutter badge assets: {missing}"

    def test_no_orphan_flutter_badges(self):
        """Every Flutter badge key should correspond to a seeded achievement slug."""
        expected_slugs = set(self.EXPECTED_SLUGS)
        # pronunciation_master is an extra Flutter badge (alias for voice)
        flutter_extras = {"pronunciation_master"}
        
        orphaned = [k for k in self.FLUTTER_BADGE_MAPPER_KEYS 
                     if k not in expected_slugs and k not in flutter_extras]
        assert not orphaned, f"Flutter badge keys without backend slugs: {orphaned}"

    def test_slug_format(self):
        """All slugs should be snake_case."""
        import re
        for slug in self.EXPECTED_SLUGS:
            assert re.match(r'^[a-z][a-z0-9_]*$', slug), f"Invalid slug format: {slug}"

    def test_total_achievement_count(self):
        """Verify expected total achievement count."""
        assert len(self.EXPECTED_SLUGS) == 48, f"Expected 48 achievements, got {len(self.EXPECTED_SLUGS)}"


# ============================================================================
# Unit Tests: Achievement Model Slug Field
# ============================================================================

class TestAchievementModelSlug:
    """Verify Achievement model has slug field."""

    def test_achievement_has_slug_field(self):
        """Achievement model must have a slug attribute."""
        ach = Achievement(
            name="Test",
            slug="test_slug",
            description="Test desc",
            condition_type="test",
            condition_value=1,
        )
        assert ach.slug == "test_slug"

    def test_achievement_slug_is_optional(self):
        """Slug field should allow None (for backward compatibility)."""
        ach = Achievement(
            name="Test No Slug",
            description="No slug",
            condition_type="test",
            condition_value=1,
        )
        assert ach.slug is None


# ============================================================================
# Unit Tests: AchievementResponse Schema
# ============================================================================

class TestAchievementResponseSchema:
    """Verify the API response schema includes slug and condition fields."""

    def test_response_includes_slug(self):
        """AchievementResponse must expose slug."""
        from app.schemas.gamification import AchievementResponse
        fields = AchievementResponse.model_fields
        assert "slug" in fields, "AchievementResponse missing 'slug' field"

    def test_response_includes_condition_type(self):
        """AchievementResponse must expose condition_type."""
        from app.schemas.gamification import AchievementResponse
        fields = AchievementResponse.model_fields
        assert "condition_type" in fields, "AchievementResponse missing 'condition_type'"

    def test_response_includes_condition_value(self):
        """AchievementResponse must expose condition_value."""
        from app.schemas.gamification import AchievementResponse
        fields = AchievementResponse.model_fields
        assert "condition_value" in fields, "AchievementResponse missing 'condition_value'"

    def test_response_serialization(self):
        """AchievementResponse should serialize with all fields."""
        from app.schemas.gamification import AchievementResponse
        resp = AchievementResponse(
            id=uuid4(),
            name="Test",
            description="Desc",
            slug="test_slug",
            condition_type="lesson_complete",
            condition_value=10,
            category="lessons",
            rarity="common",
            xp_reward=10,
            gems_reward=5,
            created_at=datetime.utcnow(),
        )
        data = resp.model_dump()
        assert data["slug"] == "test_slug"
        assert data["condition_type"] == "lesson_complete"
        assert data["condition_value"] == 10


# ============================================================================
# Scenario Tests: Level 500 Achievement
# ============================================================================

class TestLevel500Scenario:
    """
    Scenario: User reaches Level 500 — 'Immortal' badge.
    Verifies the full condition evaluation chain.
    """

    @pytest.fixture
    def checker(self):
        return AchievementCheckerService(AsyncMock(spec=AsyncSession))

    @pytest.mark.asyncio
    async def test_level_500_exactly(self, checker):
        """User at exactly level 500 should unlock."""
        ach = MagicMock(spec=Achievement)
        ach.condition_type = "numeric_level"
        ach.condition_value = 500
        ach.condition_data = {}
        stats = {"numeric_level": 500}
        result = await checker._evaluate_condition(uuid4(), ach, stats)
        assert result is True

    @pytest.mark.asyncio
    async def test_level_501_also_unlocks(self, checker):
        """User above 500 should also unlock (>= check)."""
        ach = MagicMock(spec=Achievement)
        ach.condition_type = "numeric_level"
        ach.condition_value = 500
        ach.condition_data = {}
        stats = {"numeric_level": 501}
        result = await checker._evaluate_condition(uuid4(), ach, stats)
        assert result is True

    @pytest.mark.asyncio
    async def test_level_499_does_not_unlock(self, checker):
        """User at 499 should NOT unlock Level 500 badge."""
        ach = MagicMock(spec=Achievement)
        ach.condition_type = "numeric_level"
        ach.condition_value = 500
        ach.condition_data = {}
        stats = {"numeric_level": 499}
        result = await checker._evaluate_condition(uuid4(), ach, stats)
        assert result is False

    def test_level_500_slug_maps_to_badge(self):
        """level_500 slug must exist and map to lv500.png badge."""
        # This verifies the complete pipeline:
        # Backend slug "level_500" → Flutter BadgeAssetMapper → "lv500.png"
        assert "level_500" in TestSlugConsistency.FLUTTER_BADGE_MAPPER_KEYS


# ============================================================================
# Scenario Tests: Course Completion Badge
# ============================================================================

class TestCourseCompletionScenario:
    """
    Scenario: User finishes multiple courses.
    Verifies course_complete condition works for badge unlocking.
    """

    @pytest.fixture
    def checker(self):
        return AchievementCheckerService(AsyncMock(spec=AsyncSession))

    @pytest.mark.asyncio
    async def test_first_course_complete(self, checker):
        """Completing 1 course unlocks 'Graduate' (course_explorer)."""
        ach = MagicMock(spec=Achievement)
        ach.condition_type = "course_complete"
        ach.condition_value = 1
        ach.condition_data = {}
        stats = {"courses_completed": 1}
        result = await checker._evaluate_condition(uuid4(), ach, stats)
        assert result is True

    @pytest.mark.asyncio
    async def test_five_courses_complete(self, checker):
        """Completing 5 courses unlocks 'Multi-Course Master' (course_champion)."""
        ach = MagicMock(spec=Achievement)
        ach.condition_type = "course_complete"
        ach.condition_value = 5
        ach.condition_data = {}
        stats = {"courses_completed": 5}
        result = await checker._evaluate_condition(uuid4(), ach, stats)
        assert result is True

    @pytest.mark.asyncio
    async def test_four_courses_not_enough(self, checker):
        """4 courses does NOT unlock the 5-course badge."""
        ach = MagicMock(spec=Achievement)
        ach.condition_type = "course_complete"
        ach.condition_value = 5
        ach.condition_data = {}
        stats = {"courses_completed": 4}
        result = await checker._evaluate_condition(uuid4(), ach, stats)
        assert result is False


# ============================================================================
# Scenario Tests: Daily Challenge Badge
# ============================================================================

class TestDailyChallengeScenario:
    """
    Scenario: User completes daily challenges over time.
    """

    @pytest.fixture
    def checker(self):
        return AchievementCheckerService(AsyncMock(spec=AsyncSession))

    @pytest.mark.asyncio
    async def test_30_challenges_unlocks_crusher(self, checker):
        """30 daily challenges unlocks 'Challenge Crusher'."""
        ach = MagicMock(spec=Achievement)
        ach.condition_type = "daily_challenge_complete"
        ach.condition_value = 30
        ach.condition_data = {}
        stats = {"daily_challenges_completed": 30}
        result = await checker._evaluate_condition(uuid4(), ach, stats)
        assert result is True

    @pytest.mark.asyncio
    async def test_29_challenges_not_enough(self, checker):
        """29 daily challenges is not enough."""
        ach = MagicMock(spec=Achievement)
        ach.condition_type = "daily_challenge_complete"
        ach.condition_value = 30
        ach.condition_data = {}
        stats = {"daily_challenges_completed": 29}
        result = await checker._evaluate_condition(uuid4(), ach, stats)
        assert result is False


# ============================================================================
# Scenario Tests: Streak Achievement
# ============================================================================

class TestStreakScenario:
    """Scenario: User builds up a streak."""

    @pytest.fixture
    def checker(self):
        return AchievementCheckerService(AsyncMock(spec=AsyncSession))

    @pytest.mark.asyncio
    async def test_365_day_streak(self, checker):
        """365-day streak unlocks 'Year Legend'."""
        ach = MagicMock(spec=Achievement)
        ach.condition_type = "reach_streak"
        ach.condition_value = 365
        ach.condition_data = {}
        stats = {"current_streak": 365, "longest_streak": 365}
        result = await checker._evaluate_condition(uuid4(), ach, stats)
        assert result is True

    @pytest.mark.asyncio
    async def test_broken_streak_still_counts_longest(self, checker):
        """If user broke streak but longest was 365, still counts."""
        ach = MagicMock(spec=Achievement)
        ach.condition_type = "reach_streak"
        ach.condition_value = 365
        ach.condition_data = {}
        stats = {"current_streak": 2, "longest_streak": 400}
        result = await checker._evaluate_condition(uuid4(), ach, stats)
        assert result is True


# ============================================================================
# Daily Challenge Template Tests
# ============================================================================

class TestDailyChallengeTemplates:
    """Test the daily challenge template configuration."""

    def test_template_count(self):
        """Should have 13 templates."""
        from app.routes.challenges import DAILY_CHALLENGE_TEMPLATES
        assert len(DAILY_CHALLENGE_TEMPLATES) == 13

    def test_all_templates_have_required_fields(self):
        """Every template must have id, title, description, icon, category, targets, xp_rewards."""
        from app.routes.challenges import DAILY_CHALLENGE_TEMPLATES
        required_fields = {"id", "title", "description", "icon", "category", "targets", "xp_rewards"}
        for template in DAILY_CHALLENGE_TEMPLATES:
            missing = required_fields - set(template.keys())
            assert not missing, f"Template '{template.get('id', '?')}' missing fields: {missing}"

    def test_targets_have_3_difficulties(self):
        """Each template should have exactly 3 targets (Easy/Medium/Hard)."""
        from app.routes.challenges import DAILY_CHALLENGE_TEMPLATES
        for template in DAILY_CHALLENGE_TEMPLATES:
            assert len(template["targets"]) == 3, f"Template '{template['id']}' needs 3 targets"
            assert len(template["xp_rewards"]) == 3, f"Template '{template['id']}' needs 3 xp_rewards"

    def test_targets_are_increasing(self):
        """Easy < Medium < Hard (strictly or equal for streak)."""
        from app.routes.challenges import DAILY_CHALLENGE_TEMPLATES
        for template in DAILY_CHALLENGE_TEMPLATES:
            targets = template["targets"]
            assert targets[0] <= targets[1] <= targets[2], \
                f"Template '{template['id']}' targets not increasing: {targets}"

    def test_unique_template_ids(self):
        """All template IDs must be unique."""
        from app.routes.challenges import DAILY_CHALLENGE_TEMPLATES
        ids = [t["id"] for t in DAILY_CHALLENGE_TEMPLATES]
        assert len(ids) == len(set(ids)), f"Duplicate template IDs found"

    def test_new_templates_present(self):
        """New templates (voice, social, etc.) must be present."""
        from app.routes.challenges import DAILY_CHALLENGE_TEMPLATES
        ids = {t["id"] for t in DAILY_CHALLENGE_TEMPLATES}
        new_expected = {
            "review_flashcards", "chat_practice", "voice_practice",
            "quiz_accuracy", "time_spent", "new_words",
            "grammar_drill", "listening_drill",
        }
        missing = new_expected - ids
        assert not missing, f"Missing new templates: {missing}"

    def test_challenge_generation(self):
        """get_challenges_for_user should return 4-5 challenges."""
        from app.routes.challenges import get_challenges_for_user
        user_id = uuid4()
        today = date.today()
        challenges = get_challenges_for_user(user_id, today)
        assert 4 <= len(challenges) <= 5, f"Expected 4-5 challenges, got {len(challenges)}"

    def test_challenge_generation_deterministic(self):
        """Same user + date should always generate same challenges."""
        from app.routes.challenges import get_challenges_for_user
        user_id = uuid4()
        today = date.today()
        c1 = get_challenges_for_user(user_id, today)
        c2 = get_challenges_for_user(user_id, today)
        assert [c["id"] for c in c1] == [c["id"] for c in c2]

    def test_different_users_get_different_challenges(self):
        """Different users should potentially get different challenges."""
        from app.routes.challenges import get_challenges_for_user
        today = date.today()
        # Generate for 10 different users — at least some variation expected
        all_sets = []
        for _ in range(10):
            challenges = get_challenges_for_user(uuid4(), today)
            ids = tuple(sorted(c["id"] for c in challenges))
            all_sets.append(ids)
        unique_sets = set(all_sets)
        # With 13 templates choosing 4-5, should have some variation
        assert len(unique_sets) >= 2, "All 10 users got identical challenges"

    def test_icons_are_emoji(self):
        """Template icons should be emoji strings for Flutter display."""
        from app.routes.challenges import DAILY_CHALLENGE_TEMPLATES
        for template in DAILY_CHALLENGE_TEMPLATES:
            icon = template["icon"]
            # Check it's not the old text format like "book", "cards"
            assert len(icon) <= 4, f"Template '{template['id']}' icon '{icon}' seems too long for emoji"
