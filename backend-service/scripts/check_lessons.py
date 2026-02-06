"""
Check lesson content structure
"""
import asyncio
from sqlalchemy import text
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.core.database import engine

async def check_lessons():
    async with engine.begin() as conn:
        result = await conn.execute(text('''
            SELECT l.title, l.lesson_type, l.content, l.total_exercises
            FROM lessons l
            LIMIT 3
        '''))
        print('=== Sample Lessons ===')
        for row in result.fetchall():
            print(f'Title: {row[0]}')
            print(f'Type: {row[1]}')
            print(f'Exercises: {row[3]}')
            content = row[2]
            if content:
                print(f'Content (first 500 chars): {str(content)[:500]}')
            else:
                print('Content: None')
            print('-' * 40)

if __name__ == "__main__":
    asyncio.run(check_lessons())
