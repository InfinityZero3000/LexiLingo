"""
Inspect all courses, units, lessons, and exercises in the database
"""
import asyncio
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.core.database import AsyncSessionLocal
from sqlalchemy import text

async def inspect():
    async with AsyncSessionLocal() as db:
        # Get courses
        result = await db.execute(text('''
            SELECT id, title, level, is_published, total_lessons 
            FROM courses 
            ORDER BY created_at
        '''))
        courses = result.fetchall()
        
        print(f"Total Courses in DB: {len(courses)}")
        print("=" * 80)
        
        for c_id, c_title, c_level, c_pub, c_lessons in courses:
            print(f"Course: '{c_title}' (Level: {c_level})")
            print(f"  ID: {c_id}")
            print(f"  Status: {'Published' if c_pub else 'Draft'} | Expected Lessons: {c_lessons}")
            
            # Count actual units and lessons
            u_res = await db.execute(text('SELECT COUNT(*) FROM units WHERE course_id = :cid'), {'cid': c_id})
            u_count = u_res.scalar()
            
            l_res = await db.execute(text('SELECT id, title, content, total_exercises FROM lessons WHERE course_id = :cid ORDER BY order_index'), {'cid': c_id})
            lessons = l_res.fetchall()
            
            print(f"  Actual Units: {u_count} | Actual Lessons: {len(lessons)}")
            
            if not lessons:
                print("  --> WARNING: No lessons found for this course!")
            
            for l_id, l_title, l_content, l_ex_count in lessons:
                print(f"    - Lesson: '{l_title}' (ID: {l_id})")
                print(f"      Total Exercises (column): {l_ex_count}")
                
                if l_content:
                    exercises = l_content.get('exercises', [])
                    print(f"      Exercises in Content JSON: {len(exercises)}")
                    if exercises:
                        ui_types = [ex.get('ui_type') or ex.get('type') or 'UNKNOWN' for ex in exercises]
                        print(f"      Exercise UI Types: {', '.join(ui_types)}")
                        # Check for empty ui_type or missing template mapping
                        missing_ui = [i for i, ex in enumerate(exercises) if not ex.get('ui_type')]
                        if missing_ui:
                            print(f"      --> WARNING: Exercises at indices {missing_ui} are missing 'ui_type'!")
                    else:
                        print("      --> WARNING: 'content' is present but contains 0 exercises!")
                else:
                    print("      --> ERROR: Lesson content is NULL/None!")
            print("-" * 80)

if __name__ == "__main__":
    asyncio.run(inspect())
