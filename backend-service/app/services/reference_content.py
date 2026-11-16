"""Export/import of reference content: vocabulary_items and question_bank."""

import csv
import io
import json
import uuid
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from sqlalchemy import Table, insert, select, update
from sqlalchemy.ext.asyncio import AsyncConnection, AsyncSession

from app.models.content import GrammarItem, QuestionItem
from app.models.course import Course, Lesson
from app.models.vocabulary import DifficultyLevel, PartOfSpeech, VocabularyItem

FILE_FORMAT = 1
LEVELS = [level.value for level in DifficultyLevel]
UNLABELLED = "unlabelled"
CHUNK = 500

VOCAB_COLUMNS = [
    "id", "word", "definition", "translation", "pronunciation", "audio_url",
    "part_of_speech", "difficulty_level", "course_id", "lesson_id",
    "usage_frequency", "tags",
]
QUESTION_COLUMNS = [
    "id", "prompt", "question_type", "options", "answer", "explanation",
    "difficulty_level", "tags", "is_active", "grammar_id",
]
SEED_CSV_HEADER = ["word", "part_of_speech", "cefr_level", "definition", "example"]

VOCAB = VocabularyItem.__table__
QUESTIONS = QuestionItem.__table__
UUID_COLUMNS = {"id", "course_id", "lesson_id", "grammar_id"}
# Foreign keys to content that is exported separately (courses) or not at all (grammar).
LINKS = {
    "vocabulary_items": {"course_id": Course.__table__, "lesson_id": Lesson.__table__},
    "question_bank": {"grammar_id": GrammarItem.__table__},
}


class ReferenceContentError(ValueError):
    pass


def _plain(value: Any) -> Any:
    if isinstance(value, (PartOfSpeech, DifficultyLevel)):
        return value.value
    if isinstance(value, uuid.UUID):
        return str(value)
    return value


def _row(record: Any, columns: list[str]) -> dict[str, Any]:
    return {c: _plain(record[c]) for c in columns}


async def fetch_reference(conn: AsyncConnection) -> dict[str, list[dict[str, Any]]]:
    vocab = (await conn.execute(select(*[VOCAB.c[c] for c in VOCAB_COLUMNS]).order_by(VOCAB.c.id))).mappings().all()
    questions = (
        await conn.execute(select(*[QUESTIONS.c[c] for c in QUESTION_COLUMNS]).order_by(QUESTIONS.c.id))
    ).mappings().all()
    return {
        "vocabulary_items": [_row(r, VOCAB_COLUMNS) for r in vocab],
        "question_bank": [_row(r, QUESTION_COLUMNS) for r in questions],
    }


def _dump(document: dict[str, Any]) -> str:
    return json.dumps(document, ensure_ascii=False, sort_keys=True, indent=2) + "\n"


def _vocab_sort(row: dict[str, Any]) -> tuple[str, str, str]:
    return (row["word"].casefold(), row["part_of_speech"], row["id"])


def build_files(payload: dict[str, list[dict[str, Any]]]) -> dict[str, str]:
    """Relative path -> file text, deterministic for unchanged data."""
    by_level: dict[str, list[dict[str, Any]]] = {level: [] for level in LEVELS}
    for row in payload["vocabulary_items"]:
        level = row["difficulty_level"]
        by_level.setdefault(level if level in LEVELS else UNLABELLED, []).append(row)
    if not by_level.get(UNLABELLED):
        by_level.pop(UNLABELLED, None)

    files: dict[str, str] = {}
    manifest: dict[str, Any] = {"format": FILE_FORMAT, "counts": {}}
    for level, rows in by_level.items():
        rows.sort(key=_vocab_sort)
        manifest["counts"][level] = len(rows)
        files[f"vocabulary/vocabulary_items.{level}.json"] = _dump(
            {"format": FILE_FORMAT, "table": "vocabulary_items", "level": level, "items": rows}
        )
    manifest["counts"]["total"] = sum(len(r) for r in by_level.values())
    files["vocabulary/manifest.json"] = _dump(manifest)

    questions = sorted(
        payload["question_bank"],
        key=lambda q: (q["difficulty_level"], q["question_type"], q["id"]),
    )
    files["questions/question_bank.json"] = _dump(
        {"format": FILE_FORMAT, "table": "question_bank", "items": questions}
    )
    return files


def write_files(files: dict[str, str], root: Path) -> None:
    for rel, text in files.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")


def seed_csv(vocab_rows: list[dict[str, Any]]) -> str:
    """CSV the content-agent admin_upload parser (content_agent_uploads.py) accepts."""
    out = io.StringIO()
    writer = csv.writer(out, lineterminator="\n")
    writer.writerow(SEED_CSV_HEADER)
    for row in sorted(vocab_rows, key=_vocab_sort):
        translation = row.get("translation")
        examples = translation.get("examples") if isinstance(translation, dict) else None
        example = examples[0] if isinstance(examples, list) and examples else ""
        writer.writerow(
            [row["word"], row["part_of_speech"], row["difficulty_level"], row["definition"], example]
        )
    return out.getvalue()


def load_reference_dir(root: Path) -> dict[str, list[dict[str, Any]]]:
    payload: dict[str, list[dict[str, Any]]] = {"vocabulary_items": [], "question_bank": []}
    sources = [
        ("vocabulary_items", sorted((root / "vocabulary").glob("vocabulary_items.*.json"))),
        ("question_bank", [root / "questions" / "question_bank.json"]),
    ]
    for table, paths in sources:
        for path in paths:
            if not path.is_file():
                continue
            try:
                document = json.loads(path.read_text(encoding="utf-8"))
            except json.JSONDecodeError as exc:
                raise ReferenceContentError(f"{path.name}: invalid JSON ({exc})") from exc
            if document.get("format") != FILE_FORMAT or document.get("table") != table:
                raise ReferenceContentError(f"{path.name}: not a {table} file of format {FILE_FORMAT}")
            payload[table].extend(document.get("items") or [])
    return payload


def validate(payload: dict[str, list[dict[str, Any]]]) -> list[str]:
    """Every problem in the payload; an empty list means it is safe to write."""
    problems: list[str] = []
    seen: dict[str, set[str]] = {"vocabulary_items": set(), "question_bank": set()}
    pairs: set[tuple[str, str]] = set()

    def check_id(table: str, label: str, row: dict[str, Any]) -> None:
        for column in UUID_COLUMNS & row.keys():
            if row[column] is None and column != "id":
                continue
            try:
                uuid.UUID(str(row[column]))
            except ValueError:
                problems.append(f"{table} {label}: {column} {row[column]!r} is not a UUID")
        if row.get("id") in seen[table]:
            problems.append(f"{table} {label}: duplicate id")
        seen[table].add(row.get("id"))

    for row in payload["vocabulary_items"]:
        label = f"{row.get('word')!r} ({row.get('id')})"
        missing = [c for c in ("id", "word", "definition", "part_of_speech", "difficulty_level") if not row.get(c)]
        if missing:
            problems.append(f"vocabulary_items {label}: missing {missing}")
            continue
        if row["part_of_speech"] not in {p.value for p in PartOfSpeech}:
            problems.append(
                f"vocabulary_items {label}: part_of_speech {row['part_of_speech']!r} "
                f"must be one of {[p.value for p in PartOfSpeech]} (lowercase)"
            )
        if row["difficulty_level"] not in LEVELS:
            problems.append(
                f"vocabulary_items {label}: difficulty_level {row['difficulty_level']!r} "
                f"must be one of {LEVELS} (uppercase)"
            )
        check_id("vocabulary_items", label, row)
        pair = (row["word"], row["part_of_speech"])
        if pair in pairs:
            problems.append(f"vocabulary_items {label}: duplicate (word, part_of_speech)")
        pairs.add(pair)

    for row in payload["question_bank"]:
        label = f"{str(row.get('prompt'))[:40]!r} ({row.get('id')})"
        missing = [c for c in ("id", "prompt", "question_type", "difficulty_level") if not row.get(c)]
        if missing:
            problems.append(f"question_bank {label}: missing {missing}")
            continue
        if row["difficulty_level"] not in LEVELS:
            problems.append(
                f"question_bank {label}: difficulty_level {row['difficulty_level']!r} must be one of {LEVELS}"
            )
        check_id("question_bank", label, row)
    return problems


@dataclass
class ReferenceReport:
    counts: dict[str, Counter] = field(
        default_factory=lambda: {"vocabulary_items": Counter(), "question_bank": Counter()}
    )

    def lines(self, *, write: bool) -> list[str]:
        ins, upd = ("inserted", "updated") if write else ("would insert", "would update")
        out = []
        for table, c in self.counts.items():
            line = f"  {table}: {c['inserted']} {ins}, {c['updated']} {upd}, {c['unchanged']} unchanged"
            if c["conflict"]:
                line += f", {c['conflict']} skipped (word+part_of_speech already used by another id)"
            if c["links_cleared"]:
                line += f", {c['links_cleared']} link(s) to absent course/lesson/grammar rows left empty"
            out.append(line)
        return out


def _db_value(column: str, value: Any) -> Any:
    if value is None:
        return None
    if column == "part_of_speech":
        return PartOfSpeech(value)
    if column == "difficulty_level" and value in LEVELS:
        return DifficultyLevel(value)
    if column in UUID_COLUMNS:
        return uuid.UUID(str(value))
    return value


async def _existing_ids(session: AsyncSession, table: Table, ids: set[str]) -> set[str]:
    found: set[str] = set()
    wanted = [uuid.UUID(i) for i in ids]
    for i in range(0, len(wanted), CHUNK):
        rows = await session.execute(select(table.c.id).where(table.c.id.in_(wanted[i : i + CHUNK])))
        found.update(str(r[0]) for r in rows)
    return found


async def _upsert(
    session: AsyncSession,
    table_name: str,
    table: Table,
    columns: list[str],
    rows: list[dict[str, Any]],
    *,
    overwrite: bool,
    report: ReferenceReport,
) -> None:
    counts = report.counts[table_name]
    link_ids: dict[str, set[str]] = {}
    for column, target in LINKS[table_name].items():
        wanted = {r[column] for r in rows if r.get(column)}
        link_ids[column] = await _existing_ids(session, target, wanted) if wanted else set()

    existing: dict[str, dict[str, Any]] = {}
    ids = [uuid.UUID(r["id"]) for r in rows]
    for i in range(0, len(ids), CHUNK):
        found = await session.execute(
            select(*[table.c[c] for c in columns]).where(table.c.id.in_(ids[i : i + CHUNK]))
        )
        for record in found.mappings():
            existing[str(record["id"])] = _row(record, columns)

    taken: dict[tuple[str, str], str] = {}
    if table_name == "vocabulary_items":
        pairs = await session.execute(select(VOCAB.c.word, VOCAB.c.part_of_speech, VOCAB.c.id))
        taken = {(w, _plain(p)): str(i) for w, p, i in pairs}

    to_insert: list[dict[str, Any]] = []
    for row in rows:
        clean = {c: row.get(c) for c in columns}
        for column, present in link_ids.items():
            if clean[column] and clean[column] not in present:
                clean[column] = None
                counts["links_cleared"] += 1
        current = existing.get(row["id"])
        if current is None:
            if table_name == "vocabulary_items":
                owner = taken.get((clean["word"], clean["part_of_speech"]))
                if owner and owner != row["id"]:
                    counts["conflict"] += 1
                    continue
                taken[(clean["word"], clean["part_of_speech"])] = row["id"]
            counts["inserted"] += 1
            to_insert.append({c: _db_value(c, clean[c]) for c in columns})
        elif current == clean:
            counts["unchanged"] += 1
        elif overwrite:
            counts["updated"] += 1
            values = {c: _db_value(c, clean[c]) for c in columns if c != "id"}
            await session.execute(update(table).where(table.c.id == uuid.UUID(row["id"])).values(**values))
        else:
            counts["unchanged"] += 1

    for i in range(0, len(to_insert), CHUNK):
        await session.execute(insert(table), to_insert[i : i + CHUNK])


async def import_reference(
    session: AsyncSession,
    payload: dict[str, list[dict[str, Any]]],
    *,
    overwrite: bool = False,
) -> ReferenceReport:
    """Validate everything, then upsert by id. Never commits and never deletes."""
    problems = validate(payload)
    if problems:
        shown = "\n".join(f"  - {p}" for p in problems[:25])
        more = f"\n  ... and {len(problems) - 25} more" if len(problems) > 25 else ""
        raise ReferenceContentError(f"{len(problems)} invalid row(s), nothing written:\n{shown}{more}")
    report = ReferenceReport()
    await _upsert(session, "vocabulary_items", VOCAB, VOCAB_COLUMNS, payload["vocabulary_items"],
                  overwrite=overwrite, report=report)
    await _upsert(session, "question_bank", QUESTIONS, QUESTION_COLUMNS, payload["question_bank"],
                  overwrite=overwrite, report=report)
    return report
