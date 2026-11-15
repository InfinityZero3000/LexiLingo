"""Guard for scripts/translate_vocabulary.py: what counts as missing, what gets kept."""

import sys
from pathlib import Path

import pytest
from sqlalchemy import select

from app.models.vocabulary import VocabularyItem

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

import translate_vocabulary
from translate_vocabulary import (
    LOCALES,
    build_prompt,
    merge_result,
    missing_parts,
    real_definition,
    retry_after_seconds,
    save,
    script_done,
)

DEF = "to pull or move something with force"
FULL_GLOSS = {"vi": "kéo lê", "es": "arrastrar", "fr": "traîner", "ja": "引きずる", "ko": "끌다", "zh": "拖"}
FULL_DEFS = {
    "vi": "kéo hoặc di chuyển vật gì bằng sức",
    "es": "tirar o mover algo con fuerza",
    "fr": "tirer ou déplacer quelque chose avec force",
    "ja": "力を入れて何かを引く、動かす",
    "ko": "힘을 들여 무언가를 끌거나 옮기다",
    "zh": "用力拉或移动某物",
}


def _complete() -> dict:
    return {**FULL_GLOSS, "definitions": dict(FULL_DEFS), "examples": ["The dog dragged him."]}


def test_complete_word_needs_nothing():
    assert missing_parts(DEF, _complete()) == []


def test_copy_of_definition_and_latin_cjk_are_missing():
    tr = _complete()
    tr["vi"] = DEF.upper()
    tr["ja"] = "drag"
    gaps = missing_parts(DEF, tr)
    assert "gloss.vi" in gaps and "gloss.ja" in gaps
    assert "gloss.fr" not in gaps


def test_cognate_gloss_is_accepted():
    tr = _complete()
    tr["fr"] = "hôtel"
    assert "gloss.fr" not in missing_parts("a place to stay", tr)


def test_merge_fills_gaps_and_keeps_curated_values():
    existing = {"vi": "kéo (admin)", "examples": ["Keep me."]}
    result = {
        "gloss": {**FULL_GLOSS, "ja": "drag"},
        "definition_translation": FULL_DEFS,
        "example": "Replaced?",
    }
    definition, tr = merge_result(DEF, existing, result, overwrite=False)
    assert definition == DEF
    assert tr["vi"] == "kéo (admin)"
    assert tr["examples"] == ["Keep me."]
    assert "ja" not in tr  # a Latin-only answer is refused, left for a rerun
    assert tr["definitions"]["zh"] == FULL_DEFS["zh"]


def test_merge_overwrite_replaces_valid_values_only():
    definition, tr = merge_result(
        DEF, {"vi": "kéo (cũ)"}, {"gloss": {"vi": "kéo lê"}}, overwrite=True
    )
    assert tr["vi"] == "kéo lê"
    _, tr = merge_result(DEF, {"vi": "kéo (cũ)"}, {"gloss": {"vi": ""}}, overwrite=True)
    assert tr["vi"] == "kéo (cũ)"


def test_blank_definition_is_filled_from_the_model():
    definition, _ = merge_result("", {}, {"definition": "  to pull hard "}, overwrite=False)
    assert definition == "to pull hard"
    assert "definition" not in missing_parts(definition, _complete())


def test_garbage_result_changes_nothing():
    for junk in ({}, {"gloss": "kéo"}, {"definition_translation": None}):
        assert merge_result(DEF, {"vi": "kéo"}, junk, overwrite=False) == (DEF, {"vi": "kéo"})


def test_prompt_names_every_locale():
    prompt = build_prompt(
        [{"id": "1", "word": "drag", "part_of_speech": "verb", "definition": DEF, "translation": None}]
    )
    for loc in LOCALES:
        assert f'"{loc}"' in prompt


def test_crawler_placeholders_count_as_missing():
    assert real_definition("Seeded from crawled lesson context: Lesson 1: ...") == ""
    tr = _complete()
    tr["vi"] = "(auto)"
    assert "gloss.vi" in missing_parts(DEF, tr)


def test_brand_name_may_stay_latin_in_cjk():
    tr = _complete()
    tr["ja"] = "BMW"
    assert "gloss.ja" not in missing_parts("a German car maker", tr, word="BMW")
    assert "gloss.ja" in missing_parts("a German car maker", tr, word="drag")


def test_script_done_needs_every_definition_translation():
    assert script_done(DEF, _complete())
    partial = _complete()
    del partial["definitions"]["zh"]
    assert not script_done(DEF, partial)
    assert not script_done(DEF, {"vi": "kéo"})


def test_retry_after_is_parsed_from_groq_message():
    assert retry_after_seconds("Please try again in 5m24.5s. Need more") == 5 * 60 + 24.5
    assert retry_after_seconds("try again in 1h2m3s") == 3723
    assert retry_after_seconds("try again in 12s") == 12
    assert retry_after_seconds("no hint here") is None


def test_one_word_definition_may_share_a_word_with_es_fr_only():
    tr = _complete()
    tr["fr"] = "opposition"
    tr["vi"] = "opposition"
    gaps = missing_parts("opposition", tr)
    assert "gloss.fr" not in gaps
    assert "gloss.vi" in gaps
    tr["fr"] = DEF
    assert "gloss.fr" in missing_parts(DEF, tr)


def test_headword_punctuation_does_not_hide_a_brand_name():
    tr = _complete()
    tr["ja"] = "NextSTEP"
    assert "gloss.ja" not in missing_parts("an old operating system", tr, word="NextSTEP-")


def test_user_saved_placeholder_counts_as_no_definition():
    assert real_definition("A user-saved word: breathtaking") == ""
    assert "definition" in missing_parts(real_definition("A user-saved word: x"), _complete())


class _SameSession:
    def __init__(self, session):
        self.session = session

    async def __aenter__(self):
        return self.session

    async def __aexit__(self, *exc):
        return False


@pytest.mark.asyncio
async def test_save_merges_into_the_row_as_it_is_now(db_session, monkeypatch):
    monkeypatch.setattr(translate_vocabulary, "AsyncSessionLocal", lambda: _SameSession(db_session))
    item = VocabularyItem(
        word="drag",
        definition=DEF,
        translation={"vi": "kéo (admin sửa sau khi script đọc)"},
        part_of_speech="verb",
        difficulty_level="A1",
    )
    db_session.add(item)
    await db_session.commit()

    stale_row = {"id": str(item.id), "word": "drag", "overwrite": False}
    result = {"gloss": FULL_GLOSS, "definition_translation": FULL_DEFS, "example": "The dog dragged him."}
    await save([(stale_row, result)])

    saved = (await db_session.execute(select(VocabularyItem.translation).where(VocabularyItem.id == item.id))).scalar_one()
    assert saved["vi"] == "kéo (admin sửa sau khi script đọc)"
    assert saved["es"] == FULL_GLOSS["es"]
    assert saved["definitions"]["zh"] == FULL_DEFS["zh"]
    assert saved["examples"] == ["The dog dragged him."]
