"""Groq-backed lesson exercise generation: prompt, call, sanitising. Never writes to the DB."""
import asyncio
import json
import logging
import os
import re
import time
from collections.abc import Awaitable, Callable
from datetime import datetime, timezone

import httpx

from app.models.course import arrange_bank_matches, base_type_for, exercise_shape_problems
from app.services.vocabulary_translation import groq_keys

logger = logging.getLogger(__name__)

GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
# llama-3.3-70b-versatile and openai/gpt-oss-120b are gone/quota-bound on Groq.
GROQ_MODEL = os.getenv("EXERCISE_GEN_MODEL", "qwen/qwen3.8-27b")

# One admin request must finish inside the gateway's 300s read timeout, and
# under 100s so a Cloudflare-style proxy in front of the API does not cut it first.
ADMIN_ATTEMPT_CAP = 4
ADMIN_BUDGET_SECONDS = 90.0
CALL_TIMEOUT_SECONDS = 45.0


class ExerciseGenerationUnavailable(Exception):
    """No key, or the provider rejected the request: retrying cannot help."""


class ExerciseGenerationFailed(Exception):
    """Attempts ran out without a valid, varied lesson."""


_key_cursor = 0


def _next_key(keys: list[str]) -> str:
    global _key_cursor
    key = keys[_key_cursor % len(keys)]
    _key_cursor += 1
    return key


REQUIRED_KEYS = ("type", "ui_type", "question", "correct_answer", "explanation")
GAP_UI_TYPES = {"fill_in_the_blank", "dialogue_completion", "dictation"}
PAIRED_UI_TYPES = {"match_word_to_meaning", "categorization", "cognitive_fluidity"}
PRODUCTION_UI_TYPES = {
    "short_writing_answer",
    "dictation",
    "speaking_repeat",
    "pronunciation_practice",
    "grammar_correction",
}
MIN_DISTINCT_UI_TYPES = 3
# "Match the words with their meanings" and friends: an instruction that would
# fit any lesson in the catalogue, which is how 34 lessons ended up sharing one.
GENERIC_QUESTION_RE = re.compile(
    r"match (the |each )?(following )?(words?|items?)( with| to)? (their|its)?",
    re.I,
)

VERIFY_METHOD = "blind-answer-v1"
MIN_VERIFIED_EXERCISES = 3
VERIFY_MAX_TOKENS = 6000
# One right option, graded by exact match against correct_answer. Free-form
# writing has many right phrasings, speaking is graded by similarity, pair and
# arrange types have no single option to pick, and a listen_and_choose key is
# whatever the app speaks aloud, so a blind pick cannot check them.
UNVERIFIABLE_UI_TYPES = {
    "listen_and_choose",
    "short_writing_answer",
    "speaking_repeat",
    "pronunciation_practice",
    "arrange_the_sentence",
} | PAIRED_UI_TYPES


def sanitize_exercises(exercises: list) -> list:
    """Drop exercises the app cannot render, and repair the one case the model
    reliably gets wrong (true/false without options). Returns [] if anything
    is unusable so the caller retries rather than saving a broken lesson."""
    if not isinstance(exercises, list) or not exercises:
        return []

    cleaned = []
    for exercise in exercises:
        if not isinstance(exercise, dict):
            return []
        if any(not exercise.get(key) for key in REQUIRED_KEYS):
            return []

        ui_type = exercise["ui_type"]
        options = exercise.get("options") or []

        # The model copies ui_type into type often enough that 62 exercises
        # reached production with type="short_writing_answer", which the learner
        # endpoint rejects with a 500. Derive it; never trust it.
        base_type = base_type_for(ui_type)
        if base_type is None:
            return []
        exercise["type"] = base_type

        if ui_type == "true_or_false":
            # The renderer needs both choices; the model often omits them.
            exercise["options"] = ["True", "False"]
            if str(exercise["correct_answer"]).strip().lower() not in ("true", "false"):
                return []
        elif ui_type in PAIRED_UI_TYPES:
            if len(options) != 4 or ":" not in str(exercise["correct_answer"]):
                return []
        elif ui_type == "vocabulary_flashcard":
            # A card whose only option is "Got it!" grades itself correct and
            # pays XP for a tap.
            if len(options) < 2 or exercise["correct_answer"] not in options:
                return []
        elif ui_type in GAP_UI_TYPES:
            if "{blank}" not in exercise["question"]:
                return []
        elif ui_type == "arrange_the_sentence":
            # The word bank is the shuffled sentence, so correct_answer is never
            # one of the options — the generic check below would reject every
            # valid arrange exercise, and an empty bank would slip past it.
            if not arrange_bank_matches(options, exercise["correct_answer"]):
                return []
        elif options and exercise["correct_answer"] not in options:
            return []

        # The save path (_assert_exercises_playable) enforces this same check with a
        # 422, so a draft that fails it here could never be saved by the editor.
        if exercise_shape_problems(exercise):
            return []

        cleaned.append(exercise)

    return cleaned


def exercises_from_payload(data) -> list:
    """The model answers with {"exercises": [...]} — or, now and then, with the
    bare array. Unwrapping both saves a retry per stray response."""
    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        found = data.get("exercises", [])
        return found if isinstance(found, list) else []
    return []


def is_production(exercise: dict) -> bool:
    """Whether the learner produces the answer rather than picks it. A gap
    with no options is typed from memory, which is production too."""
    if exercise["ui_type"] in PRODUCTION_UI_TYPES:
        return True
    return exercise["ui_type"] == "fill_in_the_blank" and not exercise.get("options")


def lesson_is_varied(exercises: list) -> bool:
    """Lesson-level bar: five recognition questions in a row is not a lesson."""
    ui_types = {exercise["ui_type"] for exercise in exercises}
    if len(ui_types) < min(MIN_DISTINCT_UI_TYPES, len(exercises)):
        return False
    if not any(is_production(exercise) for exercise in exercises):
        return False
    return not any(
        GENERIC_QUESTION_RE.search(exercise["question"]) for exercise in exercises
    )


def generated_content(exercises: list, model: str = GROQ_MODEL) -> dict:
    """The lesson `content` a generation run writes, stamped with where it came from."""
    content = {
        "exercises": exercises,
        "version": 1,
        "generated_by": "exercise-generation",
        "model": model,
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }
    verification = getattr(exercises, "verification", None)
    if verification:
        content["verification"] = verification
    return content


def needs_regeneration(content) -> str | None:
    """Why an already-filled lesson should be rewritten, or None if it is fine."""
    exercises = (content or {}).get("exercises") if isinstance(content, dict) else None
    if not exercises:
        return "empty"
    try:
        return None if lesson_is_varied(exercises) else "low variety or generic wording"
    except KeyError:
        return "malformed exercise"


class VerificationUnavailable(Exception):
    """The blind pass could not be completed, so no key was checked."""


class VerifiedExercises(list):
    """The exercises, plus how far their answer keys were checked."""

    verification: dict

    def __init__(self, items=(), verification: dict | None = None) -> None:
        super().__init__(items)
        self.verification = verification or {}


def is_verifiable(exercise: dict) -> bool:
    options = exercise.get("options") or []
    return (
        exercise["ui_type"] not in UNVERIFIABLE_UI_TYPES
        and len(options) >= 2
        and exercise["correct_answer"] in options
    )


def _norm(value) -> str:
    return " ".join(str(value).strip().lower().split())


def _verification_prompt(course_title: str, level: str, lesson_title: str, items: list[dict]) -> str:
    lines = [
        json.dumps(
            {"n": n, "question": item["question"], "options": item["options"]},
            ensure_ascii=False,
        )
        for n, item in enumerate(items)
    ]
    return (
        f"You are checking quiz questions for an English course ('{course_title}', level {level}, "
        f"lesson '{lesson_title}'). Answer each question yourself; nothing tells you which option "
        "the author intended, so decide from the language alone. A True/False question is about "
        "whether the statement is true.\n\nQUESTIONS (one JSON object per line):\n"
        + "\n".join(lines)
        + "\n\nFor each question give the 0-based index of the single correct option, or -1 if "
        "no option is correct or more than one is.\n"
        'Return {"answers":[{"n":<n>,"index":<index>}]}'
    )


async def verify_exercises(
    exercises: list[dict],
    *,
    course_title: str,
    level: str,
    lesson_title: str,
    call: Callable[[str], Awaitable[dict]],
) -> tuple[list[dict], dict]:
    """Blind second pass: the model answers each choice question without the key or
    the explanation, and an exercise survives only if it picks the stored answer.
    Raises VerificationUnavailable when the pass cannot be completed (after one retry)."""
    checked = [e for e in exercises if is_verifiable(e)]
    stats = {"method": VERIFY_METHOD, "status": "verified", "checked": len(checked), "agreed": 0, "dropped": []}
    if not checked:
        return list(exercises), stats

    prompt = _verification_prompt(course_title, level, lesson_title, checked)
    picks: dict[int, int] = {}
    for attempt in range(2):
        try:
            reply = await call(prompt)
            answers = reply.get("answers") if isinstance(reply, dict) else None
            if not isinstance(answers, list):
                raise ValueError("no answers list")
            picks = {
                a["n"]: a["index"]
                for a in answers
                if isinstance(a, dict) and isinstance(a.get("n"), int) and isinstance(a.get("index"), int)
            }
            break
        except Exception as exc:
            logger.warning("answer-key verification failed (attempt %d): %s", attempt + 1, exc)
    else:
        raise VerificationUnavailable("blind pass failed twice")

    dropped_ids = set()
    for n, item in enumerate(checked):
        index = picks.get(n)
        options = item["options"]
        if index is not None and 0 <= index < len(options) and _norm(options[index]) == _norm(item["correct_answer"]):
            stats["agreed"] += 1
        else:
            dropped_ids.add(id(item))
            stats["dropped"].append(item.get("id"))
    return [e for e in exercises if id(e) not in dropped_ids], stats


def _build_prompt(course_title: str, level: str, unit_title: str, lesson_title: str, lesson_id: str) -> str:
    prompt = f"""
    Generate exactly 5 structured learning exercises for an English learning course.
    
    Context:
    - Course Title: {course_title}
    - Level: {level} (CEFR A1, A2, B1, B2, C1, or C2)
    - Unit Title: {unit_title}
    - Lesson Title: {lesson_title}
    
    You must return a JSON object with a single key "exercises" containing a list of 5 exercise objects.
    Each exercise object in the list must match the following format exactly:
    {{
      "id": "ex_{lesson_id}_1", // Replace 1 with 1-5 index
      "type": "multiple_choice" | "true_false" | "fill_blank" | "translate" | "matching",
      // image_based_choice is deliberately absent: there is no image pipeline, so
      // a question that refers to a picture is unanswerable in the app.
      "ui_type": "multiple_choice" | "true_or_false" | "fill_in_the_blank" | "arrange_the_sentence" | "translation_choice" | "dialogue_completion" | "collocation_choice" | "dictation" | "speaking_repeat" | "vocabulary_flashcard" | "grammar_correction" | "listen_and_choose" | "pronunciation_practice" | "reading_comprehension" | "short_writing_answer" | "categorization" | "match_word_to_meaning" | "cognitive_fluidity",
      "question": "The question text. For fill_in_the_blank, dialogue_completion, dictation, or grammar_correction where the user is filling a gap, you MUST use the exact string '{{blank}}' inside the question to represent the gap.",
      "options": [
         // List of strings if multiple_choice, true_false, translation_choice or collocation_choice.
         // For match_word_to_meaning, categorization, or cognitive_fluidity (matching type), this must be a list of 4 items:
         // the first 2 are keys (words) and the next 2 are values (meanings). E.g. ["dog", "cat", "con chó", "con mèo"]
      ],
      "correct_answer": "The correct answer text. For matching/categorization type, this must format as 'key1:value1, key2:value2' (e.g. 'dog:con chó, cat:con mèo'). For fill_in_the_blank, dialogue_completion, or dictation, this should be the exact word(s) that replace '{{blank}}'.",
      "explanation": "Brief explanation of why this answer is correct."
    }}
    
    Pedagogical Guidelines:
    1. Exercises must be highly relevant to '{lesson_title}' and match the {level} difficulty.
    2. All 5 exercises MUST use 5 different ui_type values, and at least one of them
       must be a production task (short_writing_answer, dictation, speaking_repeat,
       pronunciation_practice or grammar_correction) — a lesson of 5 recognition
       questions teaches nothing.
    2b. Write every 'question' around this lesson's own content. Never reuse a generic
       instruction such as "Match the words with their meanings"; say what is being
       matched, e.g. "Match each kitchen object with its Vietnamese meaning".
    3. Ensure matching/categorization exercises contain 4 items in 'options' and their correct_answer matches the 'key1:value1, key2:value2' format.
    4. For fill_in_the_blank and dialogue_completion, include '{{blank}}' in the question.
    5. The learners are Vietnamese speakers studying English. Every translation,
       gloss or meaning MUST be Vietnamese (with correct diacritics) — never any
       other language. The prompt text itself stays in English.
    6. For true_false / true_or_false, 'options' MUST be exactly ["True", "False"]
       and 'correct_answer' MUST be either "True" or "False".
    7. For vocabulary_flashcard, 'options' MUST contain at least 2 real choices and
       'correct_answer' MUST be one of them — never a single "Got it!" button.
    7b. For short_writing_answer, 'correct_answer' is ONE model sentence in the
       language the learner must write (English unless the prompt asks for
       Vietnamese). Never pack a translation next to it ("English | Tiếng Việt").
       short_writing_answer is only for writing: a True/False question is
       true_or_false, a question with options to pick from is multiple_choice,
       and a gap with one right answer is fill_in_the_blank.
    8. For arrange_the_sentence, 'options' MUST be the words of the sentence in
       shuffled order (one word per item, no punctuation) and 'correct_answer'
       MUST be the full sentence built from exactly those words — never a list of
       candidate sentences.
    """
    return prompt


async def generate_lesson_exercises(
    *,
    course_title: str,
    level: str,
    unit_title: str,
    lesson_title: str,
    lesson_id: str,
    keys: list[str] | None = None,
    client: httpx.AsyncClient | None = None,
    max_attempts: int | None = None,
) -> VerifiedExercises:
    """Ask Groq for 5 exercises and check each choice question's key with a blind second pass.
    Raises ExerciseGenerationUnavailable / ExerciseGenerationFailed. The result is a list
    carrying `.verification` (see verify_exercises); if the second pass itself cannot run,
    the batch mode fails and the admin mode returns the draft with status "unverified".

    max_attempts=None is the bounded admin-request mode (attempt cap + time budget);
    an explicit value is the batch-script mode and runs without a deadline.
    """
    keys = keys if keys is not None else groq_keys()
    if not keys:
        raise ExerciseGenerationUnavailable("no Groq key configured")
    deadline = time.monotonic() + ADMIN_BUDGET_SECONDS if max_attempts is None else None
    attempts = max_attempts or min(ADMIN_ATTEMPT_CAP, max(3, len(keys)))
    payload = {
        "model": GROQ_MODEL,
        "messages": [
            {
                "role": "user",
                "content": _build_prompt(course_title, level, unit_title, lesson_title, lesson_id),
            }
        ],
        "response_format": {"type": "json_object"},
        "temperature": 0.7,
        # Five exercises are ~800 tokens of JSON, but a reasoning model spends
        # its budget thinking first and returns json_validate_failed with an
        # empty failed_generation when it runs out. Leave room for both.
        "max_tokens": 4000,
    }

    async def pause(seconds: float) -> None:
        if deadline is not None:
            seconds = min(seconds, max(0.0, deadline - time.monotonic()))
        await asyncio.sleep(seconds)

    owns_client = client is None
    http = client or httpx.AsyncClient()

    async def verify_call(prompt: str) -> dict:
        timeout = CALL_TIMEOUT_SECONDS
        if deadline is not None:
            timeout = min(timeout, deadline - time.monotonic())
            if timeout <= 1:
                raise TimeoutError("no time left to verify")
        response = await http.post(
            GROQ_URL,
            json={
                "model": GROQ_MODEL,
                "messages": [{"role": "user", "content": prompt}],
                "response_format": {"type": "json_object"},
                "temperature": 0,
                "max_tokens": VERIFY_MAX_TOKENS,
            },
            headers={"Authorization": f"Bearer {_next_key(keys)}"},
            timeout=timeout,
        )
        response.raise_for_status()
        return json.loads(response.json()["choices"][0]["message"]["content"])

    try:
        # Each attempt takes the next key in the rotation, so a key that is out
        # of daily quota costs one attempt rather than stalling the request.
        for attempt in range(attempts):
            timeout = CALL_TIMEOUT_SECONDS
            if deadline is not None:
                remaining = deadline - time.monotonic()
                if remaining <= 1:
                    break
                timeout = min(timeout, remaining)
            try:
                response = await http.post(
                    GROQ_URL,
                    json=payload,
                    headers={"Authorization": f"Bearer {_next_key(keys)}"},
                    timeout=timeout,
                )
                if response.status_code == 200:
                    content = response.json()["choices"][0]["message"]["content"]
                    exercises = sanitize_exercises(exercises_from_payload(json.loads(content)))
                    if exercises and lesson_is_varied(exercises):
                        try:
                            survivors, stats = await verify_exercises(
                                exercises,
                                course_title=course_title,
                                level=level,
                                lesson_title=lesson_title,
                                call=verify_call,
                            )
                        except VerificationUnavailable:
                            if deadline is None:
                                raise ExerciseGenerationFailed("answer keys could not be verified")
                            return VerifiedExercises(
                                exercises,
                                {"method": VERIFY_METHOD, "status": "unverified", "checked": 0, "agreed": 0, "dropped": []},
                            )
                        if not stats["dropped"] or (
                            len(survivors) >= MIN_VERIFIED_EXERCISES and lesson_is_varied(survivors)
                        ):
                            return VerifiedExercises(survivors, stats)
                        reason = "answer keys disagreed"
                    else:
                        reason = "invalid payload" if not exercises else "too uniform"
                    logger.warning("exercise generation %s for lesson %s - retrying", reason, lesson_id)
                elif response.status_code in (401, 403) or (
                    response.status_code == 400 and "json_validate_failed" not in response.text
                ):
                    # Retrying a bad key/model/request only burns quota silently.
                    # A 400 json_validate_failed is a bad roll, so it retries below.
                    logger.error("Groq rejected exercise generation: %s %s", response.status_code, response.text[:300])
                    raise ExerciseGenerationUnavailable(f"Groq rejected the request: {response.status_code}")
                elif response.status_code == 429:
                    # With a key pool the next attempt uses a different key.
                    await pause(1 if len(keys) > 1 else 15 * (attempt + 1))
                elif response.status_code in (500, 502, 503):
                    await pause(10 * (attempt + 1))
                else:
                    logger.warning("Groq HTTP %s for lesson %s: %s", response.status_code, lesson_id, response.text[:200])
                    await pause(5)
            except ExerciseGenerationUnavailable:
                raise
            except Exception as exc:
                logger.warning("exercise generation error for lesson %s: %s - retrying", lesson_id, exc)
                await pause(2)
    finally:
        if owns_client:
            await http.aclose()
    raise ExerciseGenerationFailed(f"no valid lesson after {attempts} attempts")
