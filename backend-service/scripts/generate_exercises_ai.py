"""
Generate High-Quality Course Exercises via Groq
===============================================
Queries the database for lessons with empty content (or, with --regenerate,
lessons whose content is playable but weak), calls Groq concurrently over the
configured key pool to generate 5 exercises per lesson from the course topic,
level and lesson title, maps them to visual templates (ui_type), and saves
them. A lesson is only overwritten once the new set passes sanitize_exercises.

Run:
    cd backend-service
    venv/bin/python3 scripts/generate_exercises_ai.py
    venv/bin/python3 scripts/generate_exercises_ai.py --regenerate --concurrency=2 --delay=6
"""

import asyncio
import itertools
import os
import json
import sys
from pathlib import Path
from dotenv import load_dotenv
import httpx

# Add backend directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.core.database import AsyncSessionLocal
from app.services.exercise_generation import (  # noqa: F401  (re-exported for tests/tools)
    ExerciseGenerationFailed,
    ExerciseGenerationUnavailable,
    GENERIC_QUESTION_RE,
    GROQ_MODEL,
    GROQ_URL,
    MIN_DISTINCT_UI_TYPES,
    PRODUCTION_UI_TYPES,
    exercises_from_payload,
    generate_lesson_exercises,
    lesson_is_varied,
    needs_regeneration,
    sanitize_exercises,
)
from sqlalchemy import text

# Load env variables
load_dotenv()

# Quota is per key AND per model, so the script rotates its own key pool.
GROQ_API_KEYS = [
    key.strip()
    for key in (
        os.getenv("GROQ_API_KEYS") or os.getenv("GROQ_API_KEY") or ""
    ).split(",")
    if key.strip()
]

# translate_vocabulary.py and regenerate_ielts_exercises.py rotate the same pool.
_key_cursor = itertools.cycle(GROQ_API_KEYS) if GROQ_API_KEYS else None
_key_lock = asyncio.Lock()


async def next_groq_key() -> str:
    async with _key_lock:
        return next(_key_cursor)


# Concurrency limit to prevent hitting API rate limits
SEMAPHORE_LIMIT = 5


async def process_lesson(sem: asyncio.Semaphore, client: httpx.AsyncClient, lesson_id: str, course_title: str, level: str, unit_title: str, lesson_title: str, delay: float = 4.0):
    """Worker task wrapper to process a single lesson with concurrency limit and rate-limiting delay"""
    async with sem:
        print(f"-> Generating exercises for: '{lesson_title}' ({course_title} - {level})")
        try:
            exercises = await generate_lesson_exercises(
                course_title=course_title,
                level=level,
                unit_title=unit_title,
                lesson_title=lesson_title,
                lesson_id=lesson_id,
                keys=GROQ_API_KEYS,
                client=client,
                max_attempts=max(3, len(GROQ_API_KEYS)),
            )
        except ExerciseGenerationUnavailable as exc:
            print(f"    [FATAL] {exc}")
            raise SystemExit("Aborting: the API rejected the request (see error above).")
        except ExerciseGenerationFailed:
            exercises = []
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
    regenerate = "--regenerate" in sys.argv

    for arg in sys.argv:
        if arg.startswith("--limit="):
            limit = int(arg.split("=")[1])
        elif arg.startswith("--delay="):
            delay = float(arg.split("=")[1])
        elif arg.startswith("--concurrency="):
            concurrency = int(arg.split("=")[1])

    print("=" * 80)
    print("LEXILINGO COURSE EXERCISES AI GENERATOR & SEEDER")
    print(
        f"Settings: concurrency={concurrency}, delay={delay}s, limit={limit}, "
        f"regenerate={regenerate}"
    )
    print("=" * 80)

    async with AsyncSessionLocal() as db:
        if regenerate:
            # Rewrite lessons whose content is playable but weak. A lesson is
            # only overwritten once its replacement passes sanitize_exercises,
            # so a failed call leaves the existing content alone.
            result = await db.execute(text('''
                SELECT l.id, c.title, c.level, u.title, l.title, l.content
                FROM lessons l
                JOIN courses c ON l.course_id = c.id
                JOIN units u ON l.unit_id = u.id
                ORDER BY c.created_at, u.order_index, l.order_index
            '''))
            lessons_to_process = []
            for row in result.fetchall():
                content = row[5]
                if isinstance(content, str):
                    try:
                        content = json.loads(content)
                    except json.JSONDecodeError:
                        content = None
                reason = needs_regeneration(content)
                if reason:
                    lessons_to_process.append(row[:5])
        else:
            # Lessons with NULL or empty content
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
