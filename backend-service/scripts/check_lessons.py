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
            SELECT l.title, l.id, l.course_id, l.unit_id,
                   (SELECT COUNT(*) FROM courses c WHERE c.id = l.course_id) as course_match,
                   (SELECT COUNT(*) FROM units u WHERE u.id = l.unit_id) as unit_match,
                   l.content IS NULL as is_null,
                   CAST(l.content AS text) as content_text
            FROM lessons l
            LIMIT 10
        '''))
        print('=== Diagnostic Lessons ===')
        for row in result.fetchall():
            print(f'Title: {row[0]}')
            print(f'ID: {row[1]}')
            print(f'CourseID: {row[2]} | CourseMatch: {row[4]}')
            print(f'UnitID: {row[3]} | UnitMatch: {row[5]}')
            print(f'IsNull: {row[6]} | ContentText: {row[7]}')
            print('-' * 40)

if __name__ == "__main__":
    asyncio.run(check_lessons())
