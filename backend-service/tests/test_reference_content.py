import json
import os
import subprocess
import sys
import uuid
from pathlib import Path

import pytest
from sqlalchemy import delete, func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content import QuestionItem
from app.models.vocabulary import DifficultyLevel, PartOfSpeech, VocabularyItem
from app.services.content_agent_uploads import parse_content_upload
from app.services.reference_content import (
    ReferenceContentError,
    build_files,
    fetch_reference,
    import_reference,
    load_reference_dir,
    seed_csv,
    write_files,
)
from tests.conftest import TEST_DATABASE_URL

BACKEND_ROOT = Path(__file__).resolve().parents[1]


async def _seed(session: AsyncSession) -> None:
    session.add_all(
        [
            VocabularyItem(
                id=uuid.UUID("00000000-0000-0000-0000-00000000000b"),
                word="Zebra", definition="A striped animal", part_of_speech=PartOfSpeech.NOUN,
                difficulty_level=DifficultyLevel.A1, pronunciation="/ˈzɛbrə/", usage_frequency=3,
                translation={"vi": "ngựa vằn", "examples": ["The zebra runs, \"fast\"."]}, tags=["animal"],
            ),
            VocabularyItem(
                id=uuid.UUID("00000000-0000-0000-0000-00000000000a"),
                word="apple", definition="A fruit", part_of_speech=PartOfSpeech.NOUN,
                difficulty_level=DifficultyLevel.A1,
            ),
            VocabularyItem(
                id=uuid.UUID("00000000-0000-0000-0000-00000000000c"),
                word="ubiquitous", definition="Found everywhere", part_of_speech=PartOfSpeech.ADJECTIVE,
                difficulty_level=DifficultyLevel.C1,
            ),
            QuestionItem(
                id=uuid.UUID("00000000-0000-0000-0000-0000000000a1"),
                prompt="Pick one", question_type="mcq", options=["a", "b"], answer={"value": "a"},
                explanation="Because", difficulty_level="B1", tags=["t"], is_active=True,
            ),
        ]
    )
    await session.commit()


async def _fetch(engine):
    async with engine.connect() as conn:
        return await fetch_reference(conn)


async def _wipe(session: AsyncSession) -> None:
    await session.execute(delete(VocabularyItem))
    await session.execute(delete(QuestionItem))
    await session.commit()


async def _import(session: AsyncSession, root: Path, *, write: bool, overwrite: bool = False):
    report = await import_reference(session, load_reference_dir(root), overwrite=overwrite)
    if write:
        await session.commit()
    else:
        await session.rollback()
    return report


async def test_round_trip_is_identical_and_second_import_is_unchanged(db_engine, db_session, tmp_path):
    await _seed(db_session)
    before = await _fetch(db_engine)
    files = build_files(before)
    write_files(files, tmp_path)

    assert (tmp_path / "vocabulary" / "vocabulary_items.A1.json").is_file()
    assert json.loads((tmp_path / "vocabulary" / "manifest.json").read_text())["counts"]["A1"] == 2
    a1 = json.loads((tmp_path / "vocabulary" / "vocabulary_items.A1.json").read_text())["items"]
    assert [r["word"] for r in a1] == ["apple", "Zebra"]
    assert all(t.endswith("\n") for t in files.values())
    assert "ˈzɛbrə" in files["vocabulary/vocabulary_items.A1.json"]
    assert build_files(before) == files

    await _wipe(db_session)
    dry = await _import(db_session, tmp_path, write=False)
    assert dry.counts["vocabulary_items"]["inserted"] == 3
    assert (await db_session.execute(select(func.count()).select_from(VocabularyItem))).scalar() == 0

    done = await _import(db_session, tmp_path, write=True)
    assert done.counts["vocabulary_items"]["inserted"] == 3
    assert done.counts["question_bank"]["inserted"] == 1
    assert await _fetch(db_engine) == before

    again = await _import(db_session, tmp_path, write=True, overwrite=True)
    for counter in again.counts.values():
        assert counter["inserted"] == counter["updated"] == 0
    assert again.counts["vocabulary_items"]["unchanged"] == 3


async def test_update_flag_controls_overwrite(db_engine, db_session, tmp_path):
    await _seed(db_session)
    write_files(build_files(await _fetch(db_engine)), tmp_path)
    await db_session.execute(text("UPDATE vocabulary_items SET definition = 'edited' WHERE word = 'apple'"))
    await db_session.commit()

    insert_only = await _import(db_session, tmp_path, write=True)
    assert insert_only.counts["vocabulary_items"]["updated"] == 0
    row = (await _fetch(db_engine))["vocabulary_items"]
    assert "edited" in [r["definition"] for r in row]

    updated = await _import(db_session, tmp_path, write=True, overwrite=True)
    assert updated.counts["vocabulary_items"]["updated"] == 1
    assert "edited" not in [r["definition"] for r in (await _fetch(db_engine))["vocabulary_items"]]


@pytest.mark.parametrize(
    ("column", "value", "fragment"),
    [
        ("part_of_speech", "NOUN", "lowercase"),
        ("part_of_speech", "gerund", "part_of_speech"),
        ("difficulty_level", "a1", "uppercase"),
        ("difficulty_level", "D9", "difficulty_level"),
    ],
)
async def test_invalid_enum_refuses_the_whole_file(db_engine, db_session, tmp_path, column, value, fragment):
    await _seed(db_session)
    write_files(build_files(await _fetch(db_engine)), tmp_path)
    await _wipe(db_session)
    path = tmp_path / "vocabulary" / "vocabulary_items.A1.json"
    document = json.loads(path.read_text())
    document["items"][1][column] = value
    path.write_text(json.dumps(document))

    with pytest.raises(ReferenceContentError, match=fragment):
        await _import(db_session, tmp_path, write=True)
    assert (await db_session.execute(select(func.count()).select_from(VocabularyItem))).scalar() == 0
    assert (await db_session.execute(select(func.count()).select_from(QuestionItem))).scalar() == 0


async def test_absent_course_link_is_left_empty_not_fatal(db_engine, db_session, tmp_path):
    await _seed(db_session)
    payload = await _fetch(db_engine)
    payload["vocabulary_items"][0]["course_id"] = str(uuid.uuid4())
    write_files(build_files(payload), tmp_path)
    await _wipe(db_session)
    report = await _import(db_session, tmp_path, write=True)
    assert report.counts["vocabulary_items"]["links_cleared"] == 1
    assert report.counts["vocabulary_items"]["inserted"] == 3


async def test_seed_csv_is_accepted_by_the_admin_upload_parser(db_engine, db_session):
    await _seed(db_session)
    text_csv = seed_csv((await _fetch(db_engine))["vocabulary_items"])
    assert text_csv.splitlines()[0] == "word,part_of_speech,cefr_level,definition,example"

    parsed = parse_content_upload("seed.csv", text_csv.encode("utf-8"), rights_confirmed=True)
    assert parsed.errors == []
    assert len(parsed.records) == 3
    by_word = {r["word"]: r for r in parsed.records}
    assert by_word["Zebra"]["declared_cefr"] == "A1"
    assert by_word["Zebra"]["example"] == 'The zebra runs, "fast".'
    assert by_word["ubiquitous"]["part_of_speech"] == "adjective"


async def test_export_script_writes_files_and_never_writes_the_db(db_engine, db_session, tmp_path):
    await _seed(db_session)
    before = await _fetch(db_engine)
    env = {**os.environ, "DATABASE_URL": TEST_DATABASE_URL.replace("+asyncpg", "")}
    csv_path = tmp_path / "seed.csv"
    out = tmp_path / "out"
    proc = subprocess.run(
        [sys.executable, str(BACKEND_ROOT / "scripts" / "export_reference_content.py"),
         "--out-dir", str(out), "--seed-csv", str(csv_path)],
        env=env, capture_output=True, text=True, cwd=BACKEND_ROOT,
    )
    assert proc.returncode == 0, proc.stderr
    assert {p.name for p in (out / "vocabulary").iterdir()} >= {"manifest.json", "vocabulary_items.A1.json"}
    assert build_files(before) == {
        rel: (out / rel).read_text(encoding="utf-8") for rel in build_files(before)
    }
    assert csv_path.read_text(encoding="utf-8") == seed_csv(before["vocabulary_items"])
    assert await _fetch(db_engine) == before
