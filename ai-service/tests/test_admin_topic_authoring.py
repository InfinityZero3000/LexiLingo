"""Admin topic authoring: what the admin sees, what an edit keeps, the auto icon, the AI draft."""

import copy
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException

from api.models.story_schemas import AdminStoryCreateRequest, DifficultyLevel, LocalizedTitle, StoryListItem
from api.services import topic_draft_service as drafts
from api.services.story_service import StoryService
from api.services.topic_meta import ICON_KEYS, TOPIC_CATEGORIES, infer_topic_meta, resolve_icon_key


# ── icon and category from a title ────────────────────────────────────────

@pytest.mark.parametrize(
    "title, icon, category",
    [
        ("Dental Appointment Checkup", "doctor", "health"),
        ("Hotel Check-In Conversation", "hotel", "travel"),
        ("Asking for Directions Downtown", "directions", "travel"),
        ("Buying Train Tickets", "transport", "travel"),
        ("Ordering Coffee at a Cafe", "cafe", "food"),
        ("Talking about Hobbies", "leisure", "leisure"),
        ("Giving a Short News Interview", "media", "media"),
        ("Job Interview Success", "work", "work"),
        ("Opening a Bank Account", "finance", "finance"),
    ],
)
def test_the_icon_and_category_follow_the_title(title, icon, category):
    meta = infer_topic_meta(title)

    assert (meta["icon_key"], meta["category"]) == (icon, category)
    assert meta["matched"]


@pytest.mark.parametrize(
    "title, icon",
    [
        ("Mental Health Check-In", "health"),          # was a hotel: "check-in" alone is not a hotel
        ("Tax Appointment Questions", "finance"),      # was a doctor: "appointment" is generic
        ("Cooking Class Instructions", "food"),        # was education: "class" tied with "cook"
        ("Travel Emergency Help Desk", "emergency"),   # was travel
        ("Customer Support Call", "services"),
        ("Explaining Dietary Restrictions", "food"),
        ("Volunteering Event Sign-Up", "social"),
    ],
)
def test_titles_the_first_rules_got_wrong(title, icon):
    assert infer_topic_meta(title)["icon_key"] == icon


def test_a_tie_between_two_icons_is_reported_as_low_confidence():
    meta = infer_topic_meta("Planning a Dinner Party")  # food and social both fit

    assert meta["confidence"] == "low"
    assert infer_topic_meta("Hotel Reservation")["confidence"] == "high"


def test_most_bundled_topics_get_the_category_the_stories_already_have():
    stories = StoryService(_db(find_one=None))._load_sample_stories()
    agree = sum(infer_topic_meta(s.title.en)["category"] == s.category for s in stories)

    assert agree / len(stories) >= 0.75, f"{agree}/{len(stories)}"


def test_nothing_to_go_on_gives_the_generic_icon_and_says_so():
    meta = infer_topic_meta("Quantum widgets")

    assert meta == {"category": "daily_life", "icon_key": "chat", "confidence": "low", "matched": []}


def test_a_word_inside_another_word_does_not_match():
    assert infer_topic_meta("Updated plans")["matched"] == []  # not "date"


def test_every_rule_points_at_a_known_icon_and_category():
    from api.services.topic_meta import _RULES

    for icon, category, _ in _RULES:
        assert icon in ICON_KEYS and category in TOPIC_CATEGORIES, (icon, category)


def test_resolve_icon_key_falls_back_icon_then_category_then_generic():
    assert resolve_icon_key("Doctor", "x") == "doctor"
    assert resolve_icon_key("bogus", "Health") == "health"
    assert resolve_icon_key(None, "daily life") == "daily_life"
    assert resolve_icon_key(None, "astronomy") == "chat"


# ── list, get, save ───────────────────────────────────────────────────────

def _builtin(story_id="story_builtin_one"):
    return StoryListItem(
        story_id=story_id, title=LocalizedTitle(en="Built-in", vi="Có sẵn"),
        difficulty_level=DifficultyLevel.A2, category="health", estimated_minutes=12,
    )


def _db(find_one=None, docs=()):
    cursor = MagicMock()
    cursor.sort.return_value = cursor
    cursor.limit.return_value = cursor
    cursor.to_list = AsyncMock(return_value=[dict(d) for d in docs])
    stories = MagicMock()
    stories.find = MagicMock(return_value=cursor)
    stories.find_one = AsyncMock(return_value=find_one)
    stories.update_one = AsyncMock()
    return {"stories": stories}


@pytest.mark.asyncio
async def test_the_list_shows_builtin_topics_after_custom_ones_without_duplicates():
    from api.routes.admin import list_admin_topics

    custom = {"story_id": "story_mine", "title": {"en": "Mine", "vi": "Của tôi"}, "difficulty_level": "B1", "category": "work"}
    shadow = {**custom, "story_id": "story_builtin_one"}
    with patch.object(StoryService, "list_sample_story_items", return_value=[_builtin(), _builtin("story_builtin_two")]):
        out = await list_admin_topics(limit=50, _key="k", db=_db(docs=[custom, shadow]))

    rows = out["data"]["topics"]
    assert [(r["story_id"], r["source"]) for r in rows] == [
        ("story_mine", "custom"), ("story_builtin_one", "custom"), ("story_builtin_two", "builtin"),
    ]
    assert rows[2]["icon_key"] == "health"  # resolved from the category when none is stored


@pytest.mark.asyncio
async def test_a_builtin_topic_cannot_be_overwritten_by_a_new_save():
    from api.routes.admin import create_admin_topic

    payload = AdminStoryCreateRequest(
        story_id="story_builtin_one", title=LocalizedTitle(en="Built-in", vi="x"),
        difficulty_level=DifficultyLevel.A2, category="health",
    )
    db = _db(find_one=None)
    with patch.object(StoryService, "list_sample_story_items", return_value=[_builtin()]):
        with pytest.raises(HTTPException) as err:
            await create_admin_topic(payload, _key="k", db=db, redis_client=AsyncMock())

    assert err.value.status_code == 409 and "Clone" in err.value.detail
    db["stories"].update_one.assert_not_awaited()


@pytest.mark.asyncio
async def test_an_edit_keeps_the_vocabulary_and_grammar_the_form_did_not_send():
    from api.routes.admin import create_admin_topic

    stored = {
        "story_id": "story_mine", "created_at": "2026-01-01T00:00:00Z", "cover_image_url": "https://x/y.png",
        "vocabulary_list": [{"term": "boarding pass"}], "grammar_points": [{"grammar_structure": "Modals"}],
    }
    payload = AdminStoryCreateRequest(
        story_id="story_mine", title=LocalizedTitle(en="Mine", vi="x"),
        difficulty_level=DifficultyLevel.B1, category="work",
    )
    db = _db(find_one=stored)
    with patch.object(StoryService, "list_sample_story_items", return_value=[]):
        await create_admin_topic(payload, _key="k", db=db, redis_client=AsyncMock())

    doc = db["stories"].update_one.call_args[0][1]["$set"]
    assert doc["vocabulary_list"] == [{"term": "boarding pass"}]
    assert doc["grammar_points"] == [{"grammar_structure": "Modals"}]
    assert doc["cover_image_url"] == "https://x/y.png"


@pytest.mark.asyncio
async def test_sending_vocabulary_replaces_it_even_when_empty():
    from api.routes.admin import create_admin_topic

    payload = AdminStoryCreateRequest(
        story_id="story_mine", title=LocalizedTitle(en="Mine", vi="x"), difficulty_level=DifficultyLevel.B1,
        category="work", vocabulary_list=[], grammar_points=[{"grammar_structure": "New"}],
    )
    db = _db(find_one={"story_id": "story_mine", "vocabulary_list": [{"term": "old"}], "grammar_points": [{"grammar_structure": "Old"}]})
    with patch.object(StoryService, "list_sample_story_items", return_value=[]):
        await create_admin_topic(payload, _key="k", db=db, redis_client=AsyncMock())

    doc = db["stories"].update_one.call_args[0][1]["$set"]
    assert doc["vocabulary_list"] == [] and doc["grammar_points"] == [{"grammar_structure": "New"}]


@pytest.mark.asyncio
async def test_a_new_topic_without_an_icon_gets_one_from_its_title():
    from api.routes.admin import create_admin_topic

    payload = AdminStoryCreateRequest(
        title=LocalizedTitle(en="Dental Appointment Checkup", vi="x"), difficulty_level=DifficultyLevel.B1, category="",
    )
    db = _db(find_one=None)
    with patch.object(StoryService, "list_sample_story_items", return_value=[]):
        out = await create_admin_topic(payload, _key="k", db=db, redis_client=AsyncMock())

    doc = db["stories"].update_one.call_args[0][1]["$set"]
    assert (doc["icon_key"], doc["category"]) == ("doctor", "health")
    assert out["data"]["icon_key"] == "doctor"


@pytest.mark.asyncio
async def test_get_returns_a_builtin_story_marked_as_such_and_404s_an_unknown_one():
    from api.routes.admin import get_admin_topic

    with patch.object(StoryService, "_load_sample_stories", return_value=[]):
        with pytest.raises(HTTPException) as err:
            await get_admin_topic("nope", _key="k", db=_db(find_one=None))
    assert err.value.status_code == 404

    real = StoryService(_db(find_one=None))._load_sample_stories()[0]
    out = await get_admin_topic(real.story_id, _key="k", db=_db(find_one=None))
    assert out["data"]["source"] == "builtin" and out["data"]["story_id"] == real.story_id
    assert out["data"]["vocabulary_list"]


# ── AI draft ──────────────────────────────────────────────────────────────

def _raw_draft():
    return {
        "title_vi": "Đặt phòng khách sạn",
        "role_persona": {"name": "Anna", "role": "Receptionist", "personality": "Warm", "speaking_style": "Clear", "background": "Works at a small hotel."},
        "context_description": {"setting": "Hotel desk", "scenario": "You arrive late and need your room.", "objectives": ["Greet", "Confirm the booking", "Ask about breakfast"]},
        "opening_prompt": "Good evening! Do you have a reservation with us?",
        "suggested_prompts": ["I have a reservation under Nguyen.", "Is breakfast included?", "Could I have a quiet room?"],
        "vocabulary_list": [
            {"term": t, "definition": f"what {t} means here today", "example_in_story": f"I would like to ask about the {t} please.", "part_of_speech": "noun"}
            for t in ["reservation", "key card", "check-out", "receipt", "luggage", "wake-up call"]
        ],
        "grammar_points": [
            {"grammar_structure": "Polite requests with could", "explanation": "Use could plus a base verb to ask politely.", "usage_in_story": "At the desk.", "examples": ["Could I have a late check-out?", "Could you call a taxi?"]},
            {"grammar_structure": "Present perfect for arrivals", "explanation": "Use have plus a past participle for recent events.", "usage_in_story": "On arrival.", "examples": ["I have just arrived.", "We have booked two nights."]},
        ],
        "estimated_minutes": 14,
    }


class FakeLLM:
    def __init__(self, *outputs):
        self.outputs, self.prompts = list(outputs), []

    async def __call__(self, prompt):
        self.prompts.append(prompt)
        return self.outputs.pop(0)


@pytest.mark.asyncio
async def test_a_good_draft_comes_back_whole_with_category_and_icon():
    draft, warnings = await drafts.generate_topic_draft("Hotel Check-In", "B1", "travel", llm=FakeLLM(_raw_draft()))

    assert draft["role_persona"]["name"] == "Anna" and len(draft["vocabulary_list"]) == 6
    assert draft["suggested_prompts"] and draft["opening_prompt"].startswith("Good evening")
    assert (draft["category"], draft["icon_key"]) == ("travel", "hotel")
    assert draft["title_vi"] == "Đặt phòng khách sạn" and warnings == []


@pytest.mark.asyncio
async def test_the_persona_does_not_change_an_icon_the_title_already_decided():
    raw = _raw_draft()
    raw["role_persona"]["role"] = "Office colleague"
    raw["context_description"]["setting"] = "The office meeting room"

    draft, _ = await drafts.generate_topic_draft("Planning a Birthday Party", "B1", llm=FakeLLM(raw))

    assert draft["icon_key"] == "social"


@pytest.mark.asyncio
async def test_a_title_with_no_clue_falls_back_to_the_setting_then_warns_if_still_unsure():
    raw = _raw_draft()
    raw["context_description"]["setting"] = "A busy airport check-in desk"

    draft, warnings = await drafts.generate_topic_draft("Quantum widgets", "B1", llm=FakeLLM(raw))

    assert draft["icon_key"] == "travel" and warnings == []


@pytest.mark.asyncio
async def test_a_verb_term_may_be_written_with_to_and_inflected_in_its_example():
    raw = _raw_draft()
    raw["vocabulary_list"][0] = {
        "term": "to pull off", "definition": "to succeed in doing something difficult",
        "example_in_story": "We pulled off the surprise without anyone noticing.", "part_of_speech": "phrasal verb",
    }

    draft, _ = await drafts.generate_topic_draft("Surprise Party", "B1", llm=FakeLLM(raw))

    assert draft["vocabulary_list"][0]["term"] == "pull off"


@pytest.mark.asyncio
async def test_an_example_that_does_not_use_the_term_is_still_rejected():
    raw = _raw_draft()
    raw["vocabulary_list"][0]["example_in_story"] = "Something else entirely happened here."

    with pytest.raises(drafts.DraftError, match="containing the term"):
        await drafts.generate_topic_draft("Hotel Check-In", "B1", llm=FakeLLM(raw, raw))


@pytest.mark.asyncio
async def test_a_rejected_draft_is_retried_with_the_reasons_and_then_accepted():
    bad = _raw_draft()
    bad["suggested_prompts"] = bad["suggested_prompts"][:2]
    bad["vocabulary_list"][0]["definition"] = "A useful expression or concept for handling 'x' in the y scenario"
    llm = FakeLLM(bad, _raw_draft())

    draft, _ = await drafts.generate_topic_draft("Hotel Check-In", "B1", llm=llm)

    assert draft["suggested_prompts"] and len(llm.prompts) == 2
    assert "suggested_prompts must be exactly 3" in llm.prompts[1] and "real definition" in llm.prompts[1]


@pytest.mark.asyncio
async def test_a_draft_that_keeps_failing_is_an_error_not_filler():
    bad = _raw_draft()
    bad["vocabulary_list"] = []

    with pytest.raises(drafts.DraftError, match="vocabulary_list needs at least 6"):
        await drafts.generate_topic_draft("Hotel Check-In", "B1", llm=FakeLLM(bad, bad))


@pytest.mark.asyncio
async def test_a_title_too_short_is_refused_before_any_model_call():
    llm = FakeLLM()

    with pytest.raises(drafts.DraftError, match="title"):
        await drafts.generate_topic_draft(" a ", "B1", llm=llm)
    assert llm.prompts == []


@pytest.mark.asyncio
async def test_the_draft_route_maps_a_failure_to_502_and_saves_nothing():
    from api.models.story_schemas import TopicDraftRequest
    from api.routes.admin import draft_admin_topic

    req = TopicDraftRequest(title_en="Hotel Check-In", difficulty_level=DifficultyLevel.B1)
    with patch("api.routes.admin.generate_topic_draft", autospec=True, side_effect=drafts.DraftError("busy")):
        with pytest.raises(HTTPException) as err:
            await draft_admin_topic(req, _key="k")
    assert err.value.status_code == 502 and err.value.detail == "busy"


@pytest.mark.asyncio
async def test_groq_busy_is_reported_not_swallowed():
    response = SimpleNamespace(status_code=429)
    with patch("api.core.groq_key_pool.get_available_groq_key", autospec=True, return_value="k"), \
            patch("api.services.trace_cag.llm_client._throttled_post_json", autospec=True, return_value=response):
        with pytest.raises(drafts.DraftError, match="busy"):
            await drafts.groq_json("x")
    with patch("api.core.groq_key_pool.get_available_groq_key", autospec=True, return_value=None):
        with pytest.raises(drafts.DraftError, match="no Groq key"):
            await drafts.groq_json("x")


@pytest.mark.asyncio
async def test_suggest_meta_route():
    from api.models.story_schemas import TopicMetaRequest
    from api.routes.admin import suggest_topic_meta

    out = await suggest_topic_meta(TopicMetaRequest(title="Hotel Check-In"), _key="k")

    assert out["data"]["icon_key"] == "hotel"
