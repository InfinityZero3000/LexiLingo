"""
Generate High-Quality Course Exercises via Gemini AI
====================================================
Queries the database for all lessons that have empty/None content,
calls the Gemini API concurrently (with a rate-limit semaphore) to
generate 5 pedagogically accurate exercises for each lesson based on
the course topic, level, and lesson title, maps them to corresponding
visual templates (ui_type), and saves them to the database.

Run:
    cd backend-service
    venv/bin/python3 scripts/generate_exercises_ai.py
"""

import asyncio
import itertools
import os
import json
import re
import sys
from pathlib import Path
from dotenv import load_dotenv
import httpx

# Add backend directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.core.database import AsyncSessionLocal
from sqlalchemy import text

# Load env variables
load_dotenv()

GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
GROQ_MODEL = os.getenv("EXERCISE_GEN_MODEL", "llama-3.3-70b-versatile")

# Groq quota is per key AND per model, so rotating the configured pool
# multiplies the daily token budget instead of exhausting one account.
# ai-service has a Redis-backed pool; a standalone script must not reach
# across the service boundary, so it round-robins the same env var itself.
GROQ_API_KEYS = [
    key.strip()
    for key in (
        os.getenv("GROQ_API_KEYS") or os.getenv("GROQ_API_KEY") or ""
    ).split(",")
    if key.strip()
]

_key_cursor = itertools.cycle(GROQ_API_KEYS) if GROQ_API_KEYS else None
_key_lock = asyncio.Lock()


async def next_groq_key() -> str:
    async with _key_lock:
        return next(_key_cursor)


# Concurrency limit to prevent hitting API rate limits
SEMAPHORE_LIMIT = 5

REQUIRED_KEYS = ("type", "ui_type", "question", "correct_answer", "explanation")
GAP_UI_TYPES = {"fill_in_the_blank", "dialogue_completion", "dictation"}
PAIRED_UI_TYPES = {"match_word_to_meaning", "categorization", "cognitive_fluidity"}


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

        if ui_type == "true_or_false":
            # The renderer needs both choices; the model often omits them.
            exercise["options"] = ["True", "False"]
            if str(exercise["correct_answer"]).strip().lower() not in ("true", "false"):
                return []
        elif ui_type in PAIRED_UI_TYPES:
            if len(options) != 4 or ":" not in str(exercise["correct_answer"]):
                return []
        elif ui_type in GAP_UI_TYPES:
            if "{blank}" not in exercise["question"]:
                return []
        elif options and exercise["correct_answer"] not in options:
            return []

        cleaned.append(exercise)

    return cleaned


async def generate_lesson_exercises(client: httpx.AsyncClient, course_title: str, level: str, unit_title: str, lesson_title: str, lesson_id: str) -> list:
    """Call Gemini to generate exercises for a single lesson"""
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
      "ui_type": "multiple_choice" | "true_or_false" | "fill_in_the_blank" | "arrange_the_sentence" | "translation_choice" | "dialogue_completion" | "collocation_choice" | "dictation" | "speaking_repeat" | "vocabulary_flashcard" | "grammar_correction" | "image_based_choice" | "listen_and_choose" | "pronunciation_practice" | "reading_comprehension" | "short_writing_answer" | "categorization" | "match_word_to_meaning" | "cognitive_fluidity",
      "question": "The question text. For fill_in_the_blank, dialogue_completion, dictation, or grammar_correction where the user is filling a gap, you MUST use the exact string '{{blank}}' inside the question to represent the gap.",
      "options": [
         // List of strings if multiple_choice, true_false, translation_choice, collocation_choice, or image_based_choice.
         // For match_word_to_meaning, categorization, or cognitive_fluidity (matching type), this must be a list of 4 items:
         // the first 2 are keys (words) and the next 2 are values (meanings). E.g. ["dog", "cat", "con chó", "con mèo"]
      ],
      "correct_answer": "The correct answer text. For matching/categorization type, this must format as 'key1:value1, key2:value2' (e.g. 'dog:con chó, cat:con mèo'). For fill_in_the_blank, dialogue_completion, or dictation, this should be the exact word(s) that replace '{{blank}}'.",
      "explanation": "Brief explanation of why this answer is correct."
    }}
    
    Pedagogical Guidelines:
    1. Exercises must be highly relevant to '{lesson_title}' and match the {level} difficulty.
    2. Vary the ui_type values across the 5 exercises to keep the lesson diverse.
    3. Ensure matching/categorization exercises contain 4 items in 'options' and their correct_answer matches the 'key1:value1, key2:value2' format.
    4. For fill_in_the_blank and dialogue_completion, include '{{blank}}' in the question.
    5. The learners are Vietnamese speakers studying English. Every translation,
       gloss or meaning MUST be Vietnamese (with correct diacritics) — never any
       other language. The prompt text itself stays in English.
    6. For true_false / true_or_false, 'options' MUST be exactly ["True", "False"]
       and 'correct_answer' MUST be either "True" or "False".
    """

    payload = {
        "model": GROQ_MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "response_format": {"type": "json_object"},
        "temperature": 0.7,
    }
    # Retry configuration for robustness. Each attempt takes the next key in
    # the rotation, so a key that is out of daily quota costs one attempt
    # rather than stalling the whole run.
    for attempt in range(max(3, len(GROQ_API_KEYS))):
        try:
            headers = {"Authorization": f"Bearer {await next_groq_key()}"}
            response = await client.post(
                GROQ_URL, json=payload, headers=headers, timeout=45.0
            )
            if response.status_code == 200:
                result_json = response.json()
                text_response = result_json["choices"][0]["message"]["content"]
                # Parse JSON
                data = json.loads(text_response)
                exercises = sanitize_exercises(data.get("exercises", []))
                if exercises:
                    return exercises
                print(f"    [Invalid payload] Lesson '{lesson_title}' - retrying...")
            elif response.status_code in (401, 403) or (
                response.status_code == 400
                and "json_validate_failed" not in response.text
            ):
                # Bad key/model/request — retrying just burns quota silently,
                # which is how a dead API key stayed invisible for 208 lessons.
                # A 400 json_validate_failed is only a bad roll of the dice,
                # so it falls through to the normal retry path below.
                print(
                    f"    [FATAL {response.status_code}] {response.text[:300]}"
                )
                raise SystemExit(
                    "Aborting: the API rejected the request (see error above)."
                )
            elif response.status_code == 429:
                # With a key pool the next attempt uses a different key, so
                # only back off hard when there is nothing to rotate to.
                wait_time = 1 if len(GROQ_API_KEYS) > 1 else 15 * (attempt + 1)
                print(f"    [Rate limit 429] Lesson '{lesson_title}' - retrying in {wait_time}s...")
                await asyncio.sleep(wait_time)
            elif response.status_code in (503, 500, 502):
                # Service temporarily unavailable — back off longer
                wait_time = 10 * (attempt + 1)
                print(f"    [HTTP Error {response.status_code}] Lesson '{lesson_title}' - retrying in {wait_time}s...")
                await asyncio.sleep(wait_time)
            else:
                print(
                    f"    [HTTP Error {response.status_code}] Lesson '{lesson_title}' "
                    f"- retrying... {response.text[:200]}"
                )
                await asyncio.sleep(5)
        except SystemExit:
            raise
        except Exception as e:
            print(f"    [Error] Lesson '{lesson_title}': {e} - retrying...")
            await asyncio.sleep(2)
            
    return []

async def process_lesson(sem: asyncio.Semaphore, client: httpx.AsyncClient, lesson_id: str, course_title: str, level: str, unit_title: str, lesson_title: str, delay: float = 4.0):
    """Worker task wrapper to process a single lesson with concurrency limit and rate-limiting delay"""
    async with sem:
        print(f"-> Generating exercises for: '{lesson_title}' ({course_title} - {level})")
        exercises = await generate_lesson_exercises(client, course_title, level, unit_title, lesson_title, lesson_id)
        if exercises:
            # Save to DB
            async with AsyncSessionLocal() as db:
                try:
                    content_json = {"exercises": exercises, "version": 1}
                    await db.execute(text('''
                        UPDATE lessons 
                        SET content = :content, total_exercises = :total 
                        WHERE id = :lid
                    '''), {
                        'content': json.dumps(content_json),
                        'total': len(exercises),
                        'lid': lesson_id
                    })
                    await db.commit()
                    print(f"   [SUCCESS] Saved {len(exercises)} exercises to '{lesson_title}'")
                    if delay > 0:
                        await asyncio.sleep(delay)
                    return True
                except Exception as db_err:
                    print(f"   [DB ERROR] Failed to save exercises for '{lesson_title}': {db_err}")
        else:
            print(f"   [FAILED] Failed to generate exercises for '{lesson_title}'")
        if delay > 0:
            await asyncio.sleep(delay)
        return False

async def main():
    if not GROQ_API_KEYS:
        print("Error: set GROQ_API_KEYS (comma-separated) or GROQ_API_KEY in backend-service/.env")
        sys.exit(1)
        
    limit = None
    delay = 4.0
    concurrency = 2
    
    for arg in sys.argv:
        if arg.startswith("--limit="):
            limit = int(arg.split("=")[1])
        elif arg.startswith("--delay="):
            delay = float(arg.split("=")[1])
        elif arg.startswith("--concurrency="):
            concurrency = int(arg.split("=")[1])
            
    print("=" * 80)
    print("LEXILINGO COURSE EXERCISES AI GENERATOR & SEEDER")
    print(f"Settings: concurrency={concurrency}, delay={delay}s, limit={limit}")
    print("=" * 80)
    
    # Query all lessons with NULL or empty content
    async with AsyncSessionLocal() as db:
        result = await db.execute(text('''
            SELECT l.id, c.title, c.level, u.title, l.title
            FROM lessons l
            JOIN courses c ON l.course_id = c.id
            JOIN units u ON l.unit_id = u.id
            WHERE l.content IS NULL OR CAST(l.content AS text) = 'null' OR CAST(l.content AS text) = '{}'
            ORDER BY c.created_at, u.order_index, l.order_index
        '''))
        lessons_to_process = result.fetchall()
        
    print(f"Found {len(lessons_to_process)} lessons requiring exercise data.")
    if not lessons_to_process:
        print("All lessons already have exercise content. Nothing to do!")
        sys.exit(0)
        
    if limit is not None:
        lessons_to_process = lessons_to_process[:limit]
        print(f"Limiting execution to the first {len(lessons_to_process)} lessons.")
        
    sem = asyncio.Semaphore(concurrency)
    
    limits = httpx.Limits(max_keepalive_connections=5, max_connections=10)
    async with httpx.AsyncClient(limits=limits) as client:
        tasks = []
        for l_id, c_title, c_lvl, u_title, l_title in lessons_to_process:
            # Stringify UUIDs safely
            tasks.append(process_lesson(sem, client, str(l_id), c_title, c_lvl, u_title, l_title, delay))
            
        results = await asyncio.gather(*tasks)
        
    success_count = sum(1 for r in results if r)
    print("\n" + "=" * 80)
    print("AI SEEDING COMPLETED")
    print("-" * 80)
    print(f"Processed: {len(lessons_to_process)} lessons")
    print(f"Successful: {success_count} lessons")
    print(f"Failed: {len(lessons_to_process) - success_count} lessons")
    print("=" * 80)


if __name__ == "__main__":
    asyncio.run(main())
