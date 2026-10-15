"""
Rewrite IELTS course exercises into the exam's own task types
=============================================================
`audit_ielts_realism.py` measured the gap: 213 tasks containing Vietnamese, 155
two-way True/False items where the exam uses TRUE/FALSE/NOT GIVEN, 55 questions
about a recording that is not attached to anything. None of that is fixable by
editing a field — the questions have to be written again, against the task
types the exam actually uses.

A replacement is only saved once it passes **both** gates: `sanitize_exercises`
(will the app render it) and `exercise_problems` from the audit (is it
IELTS-shaped). So the rules that condemned the old content are the rules the
new content is held to, and a failed generation leaves the lesson untouched.

The previous content of every lesson it rewrites is written to a backup file
first. There is no other copy — the large courses exist only in the database.

    cd backend-service
    venv/bin/python3 scripts/regenerate_ielts_exercises.py --dry-run --limit 3
    venv/bin/python3 scripts/regenerate_ielts_exercises.py --course "IELTS Academic"
    venv/bin/python3 scripts/regenerate_ielts_exercises.py --concurrency 2 --delay 6
"""

import argparse
import asyncio
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.core.database import AsyncSessionLocal
from app.models.course import Course, Unit

from audit_ielts_realism import exercise_problems, skill_from_title
from generate_exercises_ai import (
    GROQ_MODEL,
    GROQ_URL,
    exercises_from_payload,
    next_groq_key,
    sanitize_exercises,
)

# The app templates that can carry an IELTS task, per skill. Kept in step with
# _ACCEPTABLE_UI in the audit — that is what judges the result.
# Listening is restricted to the two templates that speak their own text. A
# listening multiple-choice or note-completion item needs a recording, and no
# lesson in the catalogue has one — that is how 55 questions ended up asking
# about a lecture that does not exist.
SKILL_TEMPLATES = {
    "listening": ("dictation", "listen_and_choose"),
    "reading": ("reading_comprehension", "multiple_choice", "fill_in_the_blank"),
    "writing": ("short_writing_answer", "grammar_correction"),
    "speaking": ("speaking_repeat", "pronunciation_practice", "short_writing_answer"),
}

SKILL_BRIEF = {
    "listening": (
        "In this app only two templates play anything, and both speak their own "
        "`correct_answer`. Nothing else is available, so every exercise must be one "
        "of these:\n"
        "  - `dictation`: the learner hears `correct_answer` and types it. Make it a "
        "single natural utterance of 4-10 words in exam register (an announcement, a "
        "tutor's remark, a line from a campus conversation). `question` must contain "
        "{blank}. Because the whole utterance is typed back, keep it to 3 words when "
        "it is a note-completion answer.\n"
        "  - `listen_and_choose`: the learner hears `correct_answer` spoken, sees "
        "`question` as a written instruction, and picks the matching option. The "
        "distractors must be near-misses of the kind the exam uses: a similar-sounding "
        "phrase, a paraphrase with the wrong number, a plausible but unsaid detail.\n"
        "NEVER write 'the lecture', 'the recording', 'the passage you hear' or 'the "
        "speaker said' — there is no separate recording, only the line this exercise "
        "speaks, and a question about anything else cannot be answered."
    ),
    "reading": (
        "IELTS Reading tasks: TRUE/FALSE/NOT GIVEN, YES/NO/NOT GIVEN, matching "
        "headings, sentence and summary completion, short answer.\n"
        "  - Prefer `reading_comprehension`: put two to four sentences of academic "
        "prose first, then the question as the LAST sentence. The `question` field "
        "MUST end with a question mark and nothing after it — the app splits on that "
        "final question mark and shows the prose before it as the passage, so a "
        "question that ends any other way renders as one wall of text.\n"
        "  - Never repeat the answer options inside `question`; they are rendered "
        "from `options` and listing them twice is how the passage ends up buried.\n"
        "  - Do not letter the options ('A) ...'). Write the option text alone.\n"
        "  - For TRUE/FALSE/NOT GIVEN, phrase it as a question — 'Does the passage "
        "state that ...?' — with options exactly [\"TRUE\", \"FALSE\", \"NOT "
        "GIVEN\"]. Two-way True/False is not an IELTS task, and NOT GIVEN is the "
        "option candidates most often miss, so use it as the answer sometimes.\n"
        "  - Every reading question MUST carry the text it is about. A question about "
        "a passage the learner cannot see is unanswerable.\n"
        "  - `fill_in_the_blank` answers are at most THREE words, taken verbatim from "
        "the text you wrote."
    ),
    "writing": (
        "IELTS Writing: Task 1 describes visual data (Academic) or writes a letter "
        "(General Training); Task 2 is an argumentative essay.\n"
        "  - `short_writing_answer`: give a focused writing instruction — one sentence "
        "or a two-sentence paragraph practising the lesson's skill (an overview "
        "sentence, a comparison, a concession clause). `correct_answer` is ONE model "
        "answer in English, nothing else.\n"
        "  - `grammar_correction`: a sentence with a real Task-1/Task-2 error, using "
        "{blank} for the correction."
    ),
    "speaking": (
        "IELTS Speaking: Part 1 short personal answers, Part 2 a two-minute long turn "
        "from a cue card, Part 3 abstract discussion.\n"
        "  - `speaking_repeat`: `question` is the model answer, spoken aloud by the "
        "app and repeated by the learner — a full, natural sentence a band 7 "
        "candidate would say.\n"
        "  - `pronunciation_practice`: `question` is the phrase being drilled, chosen "
        "for its stress, linking or weak forms.\n"
        "  - `short_writing_answer`: plan an answer in note form (this is the app's "
        "only free-response template)."
    ),
}


def build_prompt(course_title: str, level: str, lesson_title: str, skill: str,
                 lesson_id: str) -> str:
    templates = SKILL_TEMPLATES[skill]
    return f"""You are an IELTS materials writer. Write exactly 5 exercises for one
lesson of an IELTS preparation course.

Course: {course_title}
CEFR level: {level}
Lesson: {lesson_title}
Skill: {skill.upper()}

{SKILL_BRIEF[skill]}

Return JSON: {{"exercises": [ ... 5 objects ... ]}}. Each object:
{{
  "id": "ex_{lesson_id}_1",
  "type": "multiple_choice" | "true_false" | "fill_blank" | "translate" | "matching",
  "ui_type": one of {list(templates)},
  "question": "...",
  "options": [...],
  "correct_answer": "...",
  "explanation": "why that answer is right, in the examiner's terms"
}}

Hard rules — an exercise breaking any of these is discarded:
1. ENGLISH ONLY. No Vietnamese, no translation, no glossing. IELTS is a
   monolingual exam and a translation task cannot appear in it.
2. Use at least 2 different ui_type values from the list above, and no ui_type
   outside it.
3. `fill_in_the_blank` and `dictation` questions MUST contain the exact string
   {{blank}} where the gap is, and their `correct_answer` is at most 3 words.
4. `multiple_choice` needs 3 or 4 options and `correct_answer` must be one of
   them, character for character.
5. Never mention audio, a recording, a lecture or a passage that is not written
   into the exercise itself.
6. Write about {lesson_title} specifically. A question that would fit any lesson
   in the catalogue is a failed question.
7. Content should be exam-realistic: academic topics, band 6-8 register, the
   kind of distractor the exam uses (a paraphrase that is close but wrong, a
   number that was corrected, a claim the text never makes).
"""


def ielts_problems(exercises: list, skill: str) -> list[str]:
    problems: list[str] = []
    for index, exercise in enumerate(exercises, start=1):
        problems.extend(exercise_problems(exercise, skill, f"Q{index}"))
    if len({e.get("ui_type") for e in exercises}) < 2:
        problems.append("all five exercises use the same template")
    return problems


async def generate(client: httpx.AsyncClient, prompt: str, label: str,
                   skill: str, attempts: int) -> tuple[list, str]:
    # Content generation normally leaves qwen's reasoning on, but not here: the
    # free tier reserves max_tokens against the per-minute budget, so a request
    # large enough to think in gets 413, and one small enough to pass gets a 400
    # json_validate_failed when the thinking truncates the JSON. Measured on
    # production, `reasoning_effort: "none"` answers this prompt in ~900
    # completion tokens with valid JSON, which fits comfortably.
    max_tokens = 3000
    payload = {
        "model": GROQ_MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "response_format": {"type": "json_object"},
        "temperature": 0.7,
    }
    # Only qwen accepts "none"; gpt-oss rejects the request outright with
    # "`reasoning_effort` must be one of low, medium, or high". Same rule as
    # _qwen_reasoning_overrides in ai-service.
    if "qwen" in GROQ_MODEL.lower():
        payload["reasoning_effort"] = "none"
    last = "no attempt made"
    for attempt in range(attempts):
        try:
            headers = {"Authorization": f"Bearer {await next_groq_key()}"}
            response = await client.post(
                GROQ_URL, json={**payload, "max_tokens": max_tokens},
                headers=headers, timeout=90.0,
            )
            if response.status_code != 200:
                last = f"HTTP {response.status_code}: {response.text[:160]}"
                if response.status_code in (401, 403):
                    raise SystemExit(f"Aborting: the API rejected the key — {last}")
                if response.status_code == 413:
                    max_tokens = max(1800, int(max_tokens * 0.7))
                    print(f"    [413] {label}: retrying with max_tokens={max_tokens}")
                await asyncio.sleep(2 if response.status_code in (413, 429) else 5)
                continue
            data = json.loads(response.json()["choices"][0]["message"]["content"])
            exercises = sanitize_exercises(exercises_from_payload(data))
            if not exercises:
                last = "rejected by sanitize_exercises"
                await asyncio.sleep(1)
                continue
            problems = ielts_problems(exercises, skill)
            if problems:
                last = "; ".join(problems[:3])
                continue
            return exercises, "ok"
        except SystemExit:
            raise
        except Exception as exc:  # noqa: BLE001 - report and retry
            last = f"{type(exc).__name__}: {exc}"
            await asyncio.sleep(2)
    print(f"    [give up] {label}: {last}")
    return [], last


async def run(args) -> int:
    async with AsyncSessionLocal() as db:
        query = select(Course).options(selectinload(Course.units).selectinload(Unit.lessons))
        courses = [
            course
            for course in (await db.execute(query)).scalars().all()
            if "ielts" in (course.title or "").lower()
            and (not args.course or args.course.lower() in (course.title or "").lower())
        ]
        targets = []
        skipped_no_skill = 0
        for course in courses:
            for unit in course.units:
                for lesson in unit.lessons:
                    skill = lesson.skill or skill_from_title(lesson.title)
                    if skill not in SKILL_TEMPLATES:
                        skipped_no_skill += 1
                        continue
                    content = lesson.content if isinstance(lesson.content, dict) else {}
                    exercises = content.get("exercises") or []
                    problems = ielts_problems(
                        [e for e in exercises if isinstance(e, dict)], skill
                    )
                    if not problems:
                        continue
                    targets.append((course, lesson, skill, len(problems)))

        targets.sort(key=lambda row: -row[3])
        if args.limit:
            targets = targets[: args.limit]

        print(
            f"{len(courses)} IELTS course(s); {len(targets)} lesson(s) to rewrite, "
            f"{skipped_no_skill} skipped for having no skill label"
        )
        if not targets:
            return 0

        backup_path = Path(args.backup or
                           f"backups/ielts_content_{datetime.now(timezone.utc):%Y%m%d_%H%M%S}.json")
        if not args.dry_run:
            backup_path.parent.mkdir(parents=True, exist_ok=True)
            backup_path.write_text(json.dumps(
                [{"lesson_id": str(lesson.id), "title": lesson.title,
                  "content": lesson.content} for _, lesson, _, _ in targets],
                indent=2, ensure_ascii=False,
            ))
            print(f"backed up {len(targets)} lesson(s) to {backup_path}")

        semaphore = asyncio.Semaphore(args.concurrency)
        rewritten = failed = 0

        async with httpx.AsyncClient() as client:
            async def worker(index, course, lesson, skill):
                nonlocal rewritten, failed
                async with semaphore:
                    label = f"{lesson.title} [{skill}]"
                    print(f"-> [{index}/{len(targets)}] {label}", flush=True)
                    exercises, status = await generate(
                        client,
                        build_prompt(course.title, course.level or "B2",
                                     lesson.title, skill, str(lesson.id)),
                        label, skill, args.attempts,
                    )
                    await asyncio.sleep(args.delay)
                    if not exercises:
                        failed += 1
                        return
                    if args.dry_run:
                        print(f"    [dry run] {len(exercises)} exercise(s): "
                              f"{[e['ui_type'] for e in exercises]}")
                        print(f"      e.g. {exercises[0]['question'][:120]}")
                        rewritten += 1
                        return
                    lesson.content = {"version": 1, "exercises": exercises}
                    if not lesson.skill:
                        lesson.skill = skill
                    # Commit per lesson. A run over 136 lessons takes the best
                    # part of an hour on Groq's free tier, and a single commit
                    # at the end means anything that interrupts it throws away
                    # every generation the run has paid for.
                    await db.commit()
                    rewritten += 1

            await asyncio.gather(
                *(worker(i, c, l, s) for i, (c, l, s, _) in enumerate(targets, 1))
            )

    print(f"\nrewritten: {rewritten}, failed: {failed}")
    if not args.dry_run:
        print("Re-run scripts/audit_ielts_realism.py to confirm the findings are gone.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--course", help="only courses whose title contains this")
    parser.add_argument("--limit", type=int, help="rewrite at most this many lessons")
    parser.add_argument("--dry-run", action="store_true", help="generate but do not save")
    # One at a time: the workers share a session, and Groq's free tier limits
    # tokens per minute per organisation, so parallelism buys 429s rather than
    # speed.
    parser.add_argument("--concurrency", type=int, default=1)
    parser.add_argument("--delay", type=float, default=6.0,
                        help="pause after each lesson; Groq's free tier rate-limits hard")
    parser.add_argument("--attempts", type=int, default=6)
    parser.add_argument("--backup", help="where to write the previous content")
    args = parser.parse_args()
    return asyncio.run(run(args))


if __name__ == "__main__":
    raise SystemExit(main())
