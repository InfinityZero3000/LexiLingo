"""enrich_topic_stories: nothing is written for a story until it passes the gate."""

import argparse
import copy
import json
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

import pytest

from scripts import enrich_topic_stories as ets

DATA = Path(__file__).resolve().parents[1] / "data" / "sample_stories.json"


def _stories() -> list[dict]:
    return json.loads(DATA.read_text(encoding="utf-8"))["stories"]


def _story(story_id: str = "story_dental_appointment") -> dict:
    return copy.deepcopy(next(s for s in _stories() if s["story_id"] == story_id))


def good_output(story: dict) -> dict:
    return {
        "vocabulary": [
            {
                "term": v["term"],
                "definition": f"what people mean by {v['term']} here",
                "example_in_story": f"I would like to ask about the {v['term']} today.",
                "part_of_speech": "noun",
                "collocations": [f"a new {v['term']}", f"check the {v['term']}"],
                "common_error": {
                    "wrong": f"WRONG sentence with {v['term']}",
                    "right": f"A right sentence with {v['term']}.",
                    "why": "a short rule",
                },
            }
            for v in story["vocabulary_list"]
        ],
        "suggested_prompts": [
            "I have a toothache.",
            "Can I book an appointment for tomorrow?",
            "How much does a cleaning cost?",
        ],
        "grammar_points": [
            {
                "grammar_structure": g["grammar_structure"],
                "explanation": f"Use this pattern when you talk about {i} things at the clinic.",
                "usage_in_story": "You use it when you describe your problem to the dentist.",
                "examples": [f"Example sentence number {i} at the clinic.", f"Another example {i} here."],
            }
            for i, g in enumerate(story.get("grammar_points") or [])
        ],
    }


class FakeLLM:
    def __init__(self, outputs):
        self.outputs = list(outputs)
        self.prompts: list[str] = []

    async def __call__(self, prompt):
        self.prompts.append(prompt)
        out = self.outputs.pop(0)
        if isinstance(out, Exception):
            raise out
        return out


async def clean_diagnose(text, level):
    # Flags only the deliberate "wrong" sentence of each common_error.
    return [{"span": "WRONG", "correction": "right"}] if "WRONG" in text else []


async def bad_diagnose(text, level):
    if "BAD" in text:
        return [{"span": "BAD", "correction": "good"}]
    return await clean_diagnose(text, level)


def _args(path: Path, **kw) -> argparse.Namespace:
    base = dict(sample_stories=path, write=False, dry_run=False, only=[], concurrency=1, delay=0.0, attempts=2, force=False)
    base.update(kw)
    return argparse.Namespace(**base)


# ── parsing and gate ───────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_a_good_answer_replaces_the_filler_and_keeps_everything_else():
    story = _story()

    new, problems = await ets.enrich_story(story, FakeLLM([good_output(story)]), clean_diagnose)

    assert problems == [] and new is not None
    assert new["suggested_prompts"][0] == "I have a toothache."
    assert not ets.is_placeholder_definition(new["vocabulary_list"][0]["definition"])
    assert not ets.is_template_vocab_example(new["vocabulary_list"][0]["example_in_story"])
    assert not ets.is_template_grammar_explanation(new["grammar_points"][0]["explanation"])
    for key in ("story_id", "title", "role_persona", "conversation_flow", "tags", "difficulty_level"):
        assert new[key] == story[key]
    assert [v["term"] for v in new["vocabulary_list"]] == [v["term"] for v in story["vocabulary_list"]]
    assert [g["grammar_structure"] for g in new["grammar_points"]] == [
        g["grammar_structure"] for g in story["grammar_points"]
    ]


@pytest.mark.asyncio
async def test_a_sentence_the_diagnosis_flags_blocks_the_story():
    story = _story()
    out = good_output(story)
    out["suggested_prompts"][1] = "BAD sentence about the appointment."

    new, problems = await ets.enrich_story(story, FakeLLM([out, out]), bad_diagnose)

    assert new is None
    assert any("diagnosis flags" in p and "BAD" in p for p in problems)


@pytest.mark.asyncio
async def test_a_flagged_vocabulary_example_also_blocks_the_story():
    story = _story()
    out = good_output(story)
    out["vocabulary"][0]["example_in_story"] = f"BAD I want the {out['vocabulary'][0]['term']} now."

    new, _ = await ets.enrich_story(story, FakeLLM([out, out]), bad_diagnose)

    assert new is None


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "mutate, fragment",
    [
        (lambda o: o["vocabulary"][0].update(definition="A useful expression or concept for handling 'x' in the y scenario"), "placeholder"),
        (lambda o: o["vocabulary"][0].update(definition="one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen"), "2-15 words"),
        (lambda o: o["vocabulary"][0].update(example_in_story="No term in here at all."), "containing the term"),
        (lambda o: o["suggested_prompts"].pop(), "exactly 3"),
        (lambda o: o["suggested_prompts"].__setitem__(2, o["suggested_prompts"][0]), "duplicate"),
        (lambda o: o["grammar_points"][0].update(explanation="Use x to keep the dental conversation clear and accurate."), "template filler"),
        (lambda o: o["grammar_points"][0].update(grammar_structure="Something else"), "changed or out of order"),
        (lambda o: o["grammar_points"].pop(), "grammar_points must have"),
        (lambda o: o["vocabulary"].pop(), "no entry for"),
    ],
)
async def test_bad_shapes_are_rejected_with_a_reason(mutate, fragment):
    story = _story()
    out = good_output(story)
    mutate(out)

    new, problems = await ets.enrich_story(story, FakeLLM([out, copy.deepcopy(out)]), clean_diagnose)

    assert new is None
    assert fragment in " ".join(problems)


@pytest.mark.asyncio
async def test_a_line_unchanged_from_the_old_template_is_rejected():
    story = _story()
    out = good_output(story)
    out["suggested_prompts"][0] = story["suggested_prompts"][1]

    new, problems = await ets.enrich_story(story, FakeLLM([out, out]), clean_diagnose)

    assert new is None
    assert any("unchanged from the old template" in p for p in problems)


@pytest.mark.asyncio
async def test_a_second_attempt_sees_why_the_first_was_rejected():
    story = _story()
    bad = good_output(story)
    bad["suggested_prompts"][1] = "BAD sentence about the appointment."
    llm = FakeLLM([bad, good_output(story)])

    new, problems = await ets.enrich_story(story, llm, bad_diagnose)

    assert new is not None and problems == []
    assert "rejected" not in llm.prompts[0]
    assert "diagnosis flags" in llm.prompts[1] and "BAD" in llm.prompts[1]


@pytest.mark.asyncio
async def test_a_failing_llm_fails_the_story_with_no_template_fallback():
    story = _story()

    new, problems = await ets.enrich_story(
        story, FakeLLM([ets.EnrichmentError("Groq returned 429")] * 2), clean_diagnose
    )

    assert new is None and problems == ["Groq returned 429"]
    assert story == _story()


def test_prompt_demands_articles_and_forbids_filler():
    prompt = ets.build_prompt(_story())

    assert "a useful expression" in prompt.lower()
    assert "I have a toothache" in prompt
    assert "CEFR B1" in prompt


# ── run / CLI ──────────────────────────────────────────────────────────────

def _copy_data(tmp_path: Path) -> Path:
    path = tmp_path / "stories.json"
    path.write_text(DATA.read_text(encoding="utf-8"), encoding="utf-8")
    return path


@pytest.mark.asyncio
async def test_dry_run_writes_nothing(tmp_path, capsys):
    path = _copy_data(tmp_path)
    before = path.read_bytes()
    story = _story()

    code = await ets.amain(
        _args(path, only=["story_dental_appointment"]), FakeLLM([good_output(story)]), clean_diagnose
    )

    assert code == 0
    assert path.read_bytes() == before
    assert "dry run: nothing written" in capsys.readouterr().out


@pytest.mark.asyncio
async def test_write_replaces_only_stories_that_passed(tmp_path):
    path = _copy_data(tmp_path)
    dental, hotel = _story("story_dental_appointment"), _story("story_hotel_check_in")
    bad = good_output(hotel)
    bad["suggested_prompts"][0] = "BAD prompt here."

    async def by_story(prompt):
        return good_output(dental) if dental["title"]["en"] in prompt else bad

    code = await ets.amain(
        _args(path, write=True, only=["story_dental_appointment", "story_hotel_check_in"], attempts=1),
        by_story,
        bad_diagnose,
    )

    written = {s["story_id"]: s for s in json.loads(path.read_text(encoding="utf-8"))["stories"]}
    original = {s["story_id"]: s for s in _stories()}
    assert code == 1
    assert written["story_dental_appointment"]["suggested_prompts"][0] == "I have a toothache."
    assert written["story_hotel_check_in"] == original["story_hotel_check_in"]
    untouched = set(original) - {"story_dental_appointment"}
    assert all(written[i] == original[i] for i in untouched)
    assert list(written) == list(original)


@pytest.mark.asyncio
async def test_write_and_dry_run_are_exclusive(tmp_path):
    with pytest.raises(SystemExit):
        await ets.amain(_args(_copy_data(tmp_path), write=True, dry_run=True), FakeLLM([]), clean_diagnose)


def test_select_only_topic_expansion_stories():
    stories = _stories()
    chosen = ets.select_stories(stories, None)

    assert len(chosen) == 60
    assert all("topic_expansion" in s["tags"] for s in chosen)
    with pytest.raises(ets.EnrichmentError):
        ets.select_stories(stories, ["story_airport_checkin"])


# ── Groq plumbing (autospec'd) ─────────────────────────────────────────────

def _response(content, status=200):
    body = {"choices": [{"message": {"content": content}}], "usage": {"total_tokens": 10}}
    return SimpleNamespace(status_code=status, json=lambda: body)


@pytest.mark.asyncio
async def test_generation_keeps_reasoning_on_and_diagnosis_leaves_the_override_to_the_throttle(monkeypatch):
    monkeypatch.delenv("STORY_ENRICH_REASONING", raising=False)
    sent = []

    async def post(**kwargs):
        sent.append(kwargs["payload"])
        return _response(json.dumps({"errors": []}))

    with mock.patch("api.core.groq_key_pool.get_available_groq_key", autospec=True, return_value="k"), \
            mock.patch("api.core.groq_key_pool.record_groq_key_usage", autospec=True), \
            mock.patch("api.services.trace_cag.llm_client._throttled_post_json", autospec=True, side_effect=post):
        await ets.groq_llm("write it")
        assert await ets.groq_diagnose("I have a toothache.", "B1") == []

    generation, diagnosis = sent
    assert generation["reasoning_effort"] == "medium"
    assert generation["response_format"] == {"type": "json_object"}
    assert "reasoning_effort" not in diagnosis
    assert "TYPES: article_missing" in diagnosis["messages"][1]["content"]


@pytest.mark.asyncio
async def test_groq_failures_raise_instead_of_degrading():
    with mock.patch("api.core.groq_key_pool.get_available_groq_key", autospec=True, return_value=None):
        with pytest.raises(ets.EnrichmentError, match="no Groq key"):
            await ets.groq_llm("x")

    with mock.patch("api.core.groq_key_pool.get_available_groq_key", autospec=True, return_value="k"), \
            mock.patch("api.core.groq_key_pool.record_groq_key_usage", autospec=True), \
            mock.patch("api.services.trace_cag.llm_client._throttled_post_json", autospec=True, return_value=_response("{}", 429)):
        with pytest.raises(ets.EnrichmentError, match="429"):
            await ets.groq_llm("x")

    with mock.patch("api.core.groq_key_pool.get_available_groq_key", autospec=True, return_value="k"), \
            mock.patch("api.core.groq_key_pool.record_groq_key_usage", autospec=True), \
            mock.patch("api.services.trace_cag.llm_client._throttled_post_json", autospec=True, return_value=_response("<think>no")):
        with pytest.raises(ets.EnrichmentError, match="not valid JSON"):
            await ets.groq_llm("x")


@pytest.mark.asyncio
async def test_diagnosis_counts_only_grounded_errors():
    answer = {
        "errors": [
            {"span": "I has", "type": "subject_verb_agreement", "correction": "I have", "explanation": "x"},
            {"span": "not in the sentence", "type": "verb_tense", "correction": "y", "explanation": "x"},
        ]
    }

    with mock.patch("api.core.groq_key_pool.get_available_groq_key", autospec=True, return_value="k"), \
            mock.patch("api.core.groq_key_pool.record_groq_key_usage", autospec=True), \
            mock.patch("api.services.trace_cag.llm_client._throttled_post_json", autospec=True, return_value=_response(json.dumps(answer))):
        accepted = await ets.groq_diagnose("I has a toothache.", "B1")

    assert [e["span"] for e in accepted] == ["I has"]


# ── KG material: collocations and a verified common error ───────────────────

@pytest.mark.asyncio
async def test_an_unflagged_common_error_is_dropped_not_fatal():
    story = _story()
    out = good_output(story)
    out["vocabulary"][0]["common_error"]["wrong"] = "This sentence is fine."

    new, problems = await ets.enrich_story(story, FakeLLM([out]), clean_diagnose)

    assert problems == []
    assert new["vocabulary_list"][0]["common_error"] is None
    assert new["vocabulary_list"][1]["common_error"]["right"].startswith("A right sentence")
    assert ets.is_enriched(new)


@pytest.mark.asyncio
async def test_too_few_verified_common_errors_blocks_the_story():
    story = _story()
    out = good_output(story)
    for v in out["vocabulary"][:4]:
        v["common_error"]["wrong"] = f"Fine sentence about {v['term']}."

    new, problems = await ets.enrich_story(story, FakeLLM([out, out, out]), clean_diagnose)

    assert new is None and any("common errors are real mistakes" in p for p in problems)


@pytest.mark.asyncio
async def test_a_flagged_corrected_sentence_blocks_the_story():
    story = _story()
    out = good_output(story)
    out["vocabulary"][0]["common_error"]["right"] = "BAD corrected sentence."

    new, _ = await ets.enrich_story(story, FakeLLM([out, out]), bad_diagnose)

    assert new is None


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "mutate",
    [
        lambda v: v.update(collocations=["one"]),
        lambda v: v.update(collocations=["no term here", "nor here"]),
    ],
)
async def test_bad_kg_material_is_rejected(mutate):
    story = _story()
    out = good_output(story)
    mutate(out["vocabulary"][0])

    new, _ = await ets.enrich_story(story, FakeLLM([out, out]), clean_diagnose)

    assert new is None


@pytest.mark.asyncio
async def test_enriched_stories_are_skipped_and_progress_is_saved_per_story():
    stories = [s for s in _stories() if "topic_expansion" in s["tags"]][:2]
    first, second = copy.deepcopy(stories[0]), copy.deepcopy(stories[1])
    done, _ = await ets.enrich_story(first, FakeLLM([good_output(first)]), clean_diagnose)
    assert ets.is_enriched(done) and not ets.is_enriched(second)

    saved = []
    llm = FakeLLM([good_output(second)])
    merged, failures = await ets.run([done, second], llm, clean_diagnose, delay=0, on_pass=saved.append, log=lambda _: None)

    assert failures == {} and len(llm.prompts) == 1  # the enriched story was not redone
    assert len(saved) == 1 and ets.is_enriched(saved[0][1])
    assert merged[0] is done


def test_kg_carries_the_enriched_content_on_the_same_ids():
    from scripts import generate_tracecag_topic_corpus as gen

    story = _story()
    import asyncio
    new, _ = asyncio.run(ets.enrich_story(story, FakeLLM([good_output(story)]), clean_diagnose))
    graph, quads, _ = gen.generate_tracecag_graph([new])
    titles = {c["id"]: c["title"] for c in graph["concepts"]}
    term = new["vocabulary_list"][0]["term"]
    slug = gen.slugify(f"{story['story_id']}_{term}")

    assert titles[f"collocation:{slug}_collocation"] == f"Collocations of '{term}': a new {term}; check the {term}"
    assert titles[f"errorpattern:{slug}_misuse"].startswith(f"Common mistake: 'WRONG sentence with {term}'")
    assert titles[f"phrase:{gen.slugify(story['story_id'])}_practice_phrase_1"] == "I have a toothache."
    assert not any("Learner may misuse" in str(q) for q in quads)


def test_all_stories_also_selects_the_hand_written_ones():
    stories = _stories()
    tagged = ets.select_stories(stories, None)
    everything = ets.select_stories(stories, None, all_stories=True)

    assert all("topic_expansion" in s["tags"] for s in tagged)
    assert {"story_airport_checkin", "story_weather_plans"} <= {s["story_id"] for s in everything}
    assert len(everything) > len(tagged)


@pytest.mark.asyncio
async def test_a_story_without_grammar_points_can_be_enriched():
    story = next(copy.deepcopy(s) for s in _stories() if s["story_id"] == "story_weather_plans")
    out = good_output(story)
    out["suggested_prompts"] = ["Will it rain this afternoon?", "Should I take an umbrella today?", "What will the weather be like tomorrow?"]

    out["grammar_points"] = [
        {"grammar_structure": "Future with will", "explanation": "Use will plus a base verb to predict the weather.",
         "usage_in_story": "You use it to talk about tomorrow's weather.",
         "examples": ["It will rain tomorrow.", "Will it be sunny on Saturday?"]},
        {"grammar_structure": "Modal verbs for advice", "explanation": "Use should plus a base verb to give advice.",
         "usage_in_story": "You use it to suggest what to bring.",
         "examples": ["You should take an umbrella.", "Should I wear a coat?"]},
    ]

    new, problems = await ets.enrich_story(story, FakeLLM([out]), clean_diagnose)

    assert problems == [] and ets.is_enriched(new)
    assert [g["grammar_structure"] for g in new["grammar_points"]] == ["Future with will", "Modal verbs for advice"]
    assert "none yet" in ets.build_prompt(story)


@pytest.mark.asyncio
async def test_a_story_without_grammar_points_must_get_two():
    story = next(copy.deepcopy(s) for s in _stories() if s["story_id"] == "story_weather_plans")
    out = good_output(story)
    out["suggested_prompts"] = ["Will it rain this afternoon?", "Should I take an umbrella today?", "What will the weather be like tomorrow?"]

    new, problems = await ets.enrich_story(story, FakeLLM([out, out]), clean_diagnose)

    assert new is None and any("propose 2" in p for p in problems)


@pytest.mark.asyncio
async def test_a_malformed_common_error_is_dropped_and_the_kg_says_how_the_word_is_used():
    from scripts import generate_tracecag_topic_corpus as gen

    story = _story()
    out = good_output(story)
    out["vocabulary"][0]["common_error"].update(right=out["vocabulary"][0]["common_error"]["wrong"])

    new, problems = await ets.enrich_story(story, FakeLLM([out]), clean_diagnose)
    graph, _, _ = gen.generate_tracecag_graph([new])
    term = new["vocabulary_list"][0]["term"]
    title = {c["id"]: c["title"] for c in graph["concepts"]}[
        f"errorpattern:{gen.slugify(story['story_id'] + '_' + term)}_misuse"
    ]

    assert problems == [] and new["vocabulary_list"][0]["common_error"] is None
    assert title.startswith(f"Using '{term}' correctly: what people mean by {term} here")


@pytest.mark.asyncio
async def test_a_small_story_needs_floor_of_seventy_percent_verified():
    story = next(copy.deepcopy(s) for s in _stories() if s["story_id"] == "story_apartment_renting")
    out = good_output(story)
    out["suggested_prompts"] = ["Is the apartment still available?", "How much is the rent each month?", "Can I see the kitchen first?"]
    out["grammar_points"] = [
        {"grammar_structure": "Modal verbs for requests", "explanation": "Use can or could plus a base verb to ask politely.",
         "usage_in_story": "You use it to ask the landlord for things.", "examples": ["Could I see the bedroom?", "Can I pay by card?"]},
        {"grammar_structure": "Present simple for facts", "explanation": "Use the present simple for things that are generally true.",
         "usage_in_story": "You use it to describe the flat.", "examples": ["The flat has two bedrooms.", "The rent includes water."]},
    ]
    out["vocabulary"][0]["common_error"]["wrong"] = "A fine sentence here."  # 2 of 3 verified

    new, problems = await ets.enrich_story(story, FakeLLM([out]), clean_diagnose)

    assert problems == [] and new is not None


@pytest.mark.asyncio
async def test_a_hand_written_story_may_keep_its_own_sentences():
    story = next(copy.deepcopy(s) for s in _stories() if s["story_id"] == "story_airport_checkin")
    out = good_output(story)
    out["suggested_prompts"] = ["Can I check in for my flight here?", "Is my bag too heavy?", "Which gate do I go to?"]
    kept = story["vocabulary_list"][0]["example_in_story"]
    out["vocabulary"][0]["example_in_story"] = kept
    out["grammar_points"] = [
        {**g, "examples": [f"Grammar example {i} one.", f"Grammar example {i} two."]}
        for i, g in enumerate(out["grammar_points"])
    ]

    new, problems = await ets.enrich_story(story, FakeLLM([out]), clean_diagnose)

    assert problems == [] and new["vocabulary_list"][0]["example_in_story"] == kept
