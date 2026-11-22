import importlib.util
import json
from pathlib import Path

import pytest

from app.models.course import base_type_for, count_exercises, exercise_shape_problems

BACKEND_ROOT = Path(__file__).resolve().parents[1]
COURSES_DIR = BACKEND_ROOT / "content" / "courses"

COURSE_FIELDS = {"id", "title", "language", "level", "is_published", "total_lessons"}
UNIT_FIELDS = {"id", "course_id", "title", "order_index"}
LESSON_FIELDS = {"id", "course_id", "unit_id", "title", "order_index", "content", "total_exercises"}

# Lessons allowed to fail the shape check. Empty on purpose: fix the content, do not list it here.
SHAPE_ALLOWLIST: set[str] = set()

FILES = sorted(COURSES_DIR.glob("*.json"))


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _export_module():
    spec = importlib.util.spec_from_file_location(
        "export_course_content", BACKEND_ROOT / "scripts" / "export_course_content.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_courses_are_committed() -> None:
    assert FILES, f"no course files under {COURSES_DIR}"


@pytest.mark.parametrize("path", FILES, ids=lambda p: p.name)
def test_course_file_is_well_formed(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    doc = json.loads(text)
    assert text.endswith("\n") and not text.endswith("\n\n")
    assert text == json.dumps(doc, ensure_ascii=False, sort_keys=True, indent=2) + "\n"

    course, units, lessons = doc["course"], doc["units"], doc["lessons"]
    assert COURSE_FIELDS <= course.keys()
    assert course["is_published"] is True
    assert units and lessons
    assert course["total_lessons"] == len(lessons)

    unit_ids = {u["id"] for u in units}
    assert len(unit_ids) == len(units)
    for unit in units:
        assert UNIT_FIELDS <= unit.keys()
        assert unit["course_id"] == course["id"]
    for lesson in lessons:
        assert LESSON_FIELDS <= lesson.keys()
        assert lesson["course_id"] == course["id"]
        assert lesson["unit_id"] in unit_ids

    category = doc["category"]
    if course.get("category_id"):
        assert category and category["id"] == course["category_id"]


@pytest.mark.parametrize("path", FILES, ids=lambda p: p.name)
def test_every_lesson_is_playable_and_well_shaped(path: Path) -> None:
    failures: list[str] = []
    for lesson in _load(path)["lessons"]:
        exercises = (lesson["content"] or {}).get("exercises") or []
        if count_exercises(lesson["content"]) < 1:
            failures.append(f"{lesson['id']} {lesson['title']!r}: no exercises")
        if lesson["total_exercises"] != len(exercises):
            failures.append(f"{lesson['id']}: total_exercises drifted from content")
        if lesson["id"] in SHAPE_ALLOWLIST:
            continue
        for index, exercise in enumerate(exercises):
            for problem in exercise_shape_problems(exercise):
                failures.append(f"{lesson['id']} exercise {index}: {problem}")
            if exercise.get("type") != base_type_for(exercise.get("ui_type")):
                failures.append(f"{lesson['id']} exercise {index}: type disagrees with ui_type")
    assert not failures, "\n".join(failures)


def test_ids_are_unique_across_files() -> None:
    seen: dict[str, dict[str, str]] = {"course": {}, "unit": {}, "lesson": {}}
    duplicates: list[str] = []
    for path in FILES:
        doc = _load(path)
        rows = [("course", [doc["course"]]), ("unit", doc["units"]), ("lesson", doc["lessons"])]
        for kind, items in rows:
            for item in items:
                if item["id"] in seen[kind]:
                    duplicates.append(f"{kind} {item['id']}: {seen[kind][item['id']]} and {path.name}")
                seen[kind][item["id"]] = path.name
    assert not duplicates, "\n".join(duplicates)


def test_shared_categories_agree_between_files() -> None:
    by_id: dict[str, dict] = {}
    for path in FILES:
        category = _load(path)["category"]
        if category:
            assert by_id.setdefault(category["id"], category) == category, path.name


def _payload(titles: list[str]) -> dict:
    payload: dict = {"course_categories": [], "courses": [], "units": [], "lessons": []}
    for n, title in enumerate(titles):
        cid = f"c{n}-0000-0000"
        payload["courses"].append({"id": cid, "title": title, "category_id": None, "tags": '["a"]'})
        for u in (2, 1):
            uid = f"u{n}{u}"
            payload["units"].append({"id": uid, "course_id": cid, "order_index": u})
            for order in (2, 1):
                payload["lessons"].append(
                    {"id": f"l{n}{u}{order}", "course_id": cid, "unit_id": uid, "order_index": order,
                     "content": '{"exercises": [1]}'}
                )
    return payload


def test_split_orders_lessons_by_unit_then_position() -> None:
    export = _export_module()
    docs = export.split_payload(_payload(["Alpha Course"]))
    assert list(docs) == ["alpha-course.json"]
    doc = docs["alpha-course.json"]
    assert [u["order_index"] for u in doc["units"]] == [1, 2]
    assert [l["id"] for l in doc["lessons"]] == ["l011", "l012", "l021", "l022"]
    assert doc["course"]["tags"] == ["a"]
    assert doc["lessons"][0]["content"] == {"exercises": [1]}


def test_split_gives_same_titles_distinct_files(tmp_path: Path) -> None:
    export = _export_module()
    docs = export.split_payload(_payload(["Same Title", "Same Title"]))
    assert len(docs) == 2 and all(name.startswith("same-title-") for name in docs)

    stale = tmp_path / "gone.json"
    stale.write_text("{}\n")
    leftovers = export.write_split(docs, tmp_path)
    assert leftovers == [stale] and stale.exists()
    first = {p.name: p.read_bytes() for p in tmp_path.glob("same-title-*.json")}
    export.write_split(export.split_payload(_payload(["Same Title", "Same Title"])), tmp_path)
    assert first == {p.name: p.read_bytes() for p in tmp_path.glob("same-title-*.json")}
