"""
Script to seed sample courses into the database
Run: python -m scripts.seed_courses
"""

import sys
import os
from pathlib import Path

# Add backend-service to path
backend_path = Path(__file__).parent.parent
sys.path.insert(0, str(backend_path))

import uuid
import asyncio
from datetime import datetime
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import AsyncSessionLocal
from app.models.course import Course, Unit, Lesson


async def create_sample_courses(db: AsyncSession):
    """Create sample courses with units and lessons"""
    
    courses_data = [
        {
            "title": "English for Beginners - Free Course",
            "description": "Start your English learning journey with basic vocabulary, grammar, and conversation skills. Perfect for absolute beginners!",
            "language": "en",
            "level": "A1",
            "tags": ["beginner", "vocabulary", "grammar", "free"],
            "total_xp": 500,
            "estimated_duration": 300,  # 5 hours
            "thumbnail_url": "https://images.unsplash.com/photo-1546410531-bb4caa6b424d?w=400",
            "is_published": True,
            "units": [
                {
                    "title": "Getting Started",
                    "description": "Learn basic greetings and introductions",
                    "order_index": 1,
                    "background_color": "#4CAF50",
                    "lessons": [
                        {
                            "title": "Hello & Greetings",
                            "description": "Learn how to greet people in English",
                            "order_index": 1,
                            "estimated_minutes": 15,
                            "xp_reward": 10,
                            "total_exercises": 5,
                            "lesson_type": "lesson"
                        },
                        {
                            "title": "Introducing Yourself",
                            "description": "Learn to introduce yourself and others",
                            "order_index": 2,
                            "estimated_minutes": 20,
                            "xp_reward": 15,
                            "total_exercises": 7,
                            "lesson_type": "lesson"
                        }
                    ]
                },
                {
                    "title": "Basic Vocabulary",
                    "description": "Essential words for everyday life",
                    "order_index": 2,
                    "background_color": "#2196F3",
                    "lessons": [
                        {
                            "title": "Numbers 1-20",
                            "description": "Learn numbers from 1 to 20",
                            "order_index": 1,
                            "estimated_minutes": 15,
                            "xp_reward": 10,
                            "total_exercises": 6,
                            "lesson_type": "lesson"
                        },
                        {
                            "title": "Colors",
                            "description": "Learn common colors in English",
                            "order_index": 2,
                            "estimated_minutes": 15,
                            "xp_reward": 10,
                            "total_exercises": 5,
                            "lesson_type": "lesson"
                        }
                    ]
                }
            ]
        },
        {
            "title": "Business English Essentials",
            "description": "Master professional English for the workplace. Learn business vocabulary, email writing, presentations, and meeting skills.",
            "language": "en",
            "level": "B1",
            "tags": ["business", "professional", "intermediate"],
            "total_xp": 800,
            "estimated_duration": 480,  # 8 hours
            "thumbnail_url": "https://images.unsplash.com/photo-1454165804606-c3d57bc86b40?w=400",
            "is_published": True,
            "units": [
                {
                    "title": "Office Communication",
                    "description": "Professional communication in the workplace",
                    "order_index": 1,
                    "background_color": "#FF9800",
                    "lessons": [
                        {
                            "title": "Email Etiquette",
                            "description": "Write professional business emails",
                            "order_index": 1,
                            "estimated_minutes": 25,
                            "xp_reward": 20,
                            "total_exercises": 8,
                            "lesson_type": "lesson"
                        },
                        {
                            "title": "Phone Conversations",
                            "description": "Handle professional phone calls",
                            "order_index": 2,
                            "estimated_minutes": 30,
                            "xp_reward": 25,
                            "total_exercises": 10,
                            "lesson_type": "lesson"
                        }
                    ]
                }
            ]
        },
        {
            "title": "Everyday Conversation - Free",
            "description": "Build confidence in daily English conversations. Learn practical phrases for shopping, dining, travel, and social situations.",
            "language": "en",
            "level": "A2",
            "tags": ["conversation", "practical", "elementary", "free"],
            "total_xp": 600,
            "estimated_duration": 360,  # 6 hours
            "thumbnail_url": "https://images.unsplash.com/photo-1557804506-669a67965ba0?w=400",
            "is_published": True,
            "units": [
                {
                    "title": "At the Restaurant",
                    "description": "Order food and handle restaurant situations",
                    "order_index": 1,
                    "background_color": "#E91E63",
                    "lessons": [
                        {
                            "title": "Making Reservations",
                            "description": "Learn to book a table at a restaurant",
                            "order_index": 1,
                            "estimated_minutes": 20,
                            "xp_reward": 15,
                            "total_exercises": 6,
                            "lesson_type": "lesson"
                        },
                        {
                            "title": "Ordering Food",
                            "description": "Practice ordering meals and drinks",
                            "order_index": 2,
                            "estimated_minutes": 25,
                            "xp_reward": 20,
                            "total_exercises": 8,
                            "lesson_type": "lesson"
                        }
                    ]
                }
            ]
        },
        {
            "title": "Advanced Grammar Mastery",
            "description": "Perfect your English grammar with advanced topics. Covers complex tenses, conditionals, reported speech, and more.",
            "language": "en",
            "level": "B2",
            "tags": ["grammar", "advanced", "upper-intermediate"],
            "total_xp": 1000,
            "estimated_duration": 600,  # 10 hours
            "thumbnail_url": "https://images.unsplash.com/photo-1456513080510-7bf3a84b82f8?w=400",
            "is_published": True,
            "units": [
                {
                    "title": "Complex Tenses",
                    "description": "Master advanced verb tenses",
                    "order_index": 1,
                    "background_color": "#9C27B0",
                    "lessons": [
                        {
                            "title": "Perfect Continuous Tenses",
                            "description": "Learn perfect continuous tenses",
                            "order_index": 1,
                            "estimated_minutes": 30,
                            "xp_reward": 25,
                            "total_exercises": 10,
                            "lesson_type": "lesson"
                        }
                    ]
                }
            ]
        },
        {
            "title": "IELTS Preparation Course",
            "description": "Comprehensive preparation for all IELTS sections: Listening, Reading, Writing, and Speaking. Achieve your target band score!",
            "language": "en",
            "level": "C1",
            "tags": ["test-prep", "ielts", "advanced"],
            "total_xp": 1500,
            "estimated_duration": 900,  # 15 hours
            "thumbnail_url": "https://images.unsplash.com/photo-1434030216411-0b793f4b4173?w=400",
            "is_published": True,
            "units": [
                {
                    "title": "IELTS Writing Task 2",
                    "description": "Master essay writing for IELTS",
                    "order_index": 1,
                    "background_color": "#3F51B5",
                    "lessons": [
                        {
                            "title": "Essay Structure",
                            "description": "Learn the perfect IELTS essay structure",
                            "order_index": 1,
                            "estimated_minutes": 35,
                            "xp_reward": 30,
                            "total_exercises": 12,
                            "lesson_type": "lesson"
                        }
                    ]
                }
            ]
        },
        {
            "title": "Travel English - Free Course",
            "description": "Essential English phrases for travelers. Learn to navigate airports, hotels, and tourist attractions with confidence.",
            "language": "en",
            "level": "A2",
            "tags": ["travel", "practical", "elementary", "free"],
            "total_xp": 400,
            "estimated_duration": 240,  # 4 hours
            "thumbnail_url": "https://images.unsplash.com/photo-1488646953014-85cb44e25828?w=400",
            "is_published": True,
            "units": [
                {
                    "title": "At the Airport",
                    "description": "Navigate airports with confidence",
                    "order_index": 1,
                    "background_color": "#00BCD4",
                    "lessons": [
                        {
                            "title": "Check-in & Security",
                            "description": "Handle airport check-in procedures",
                            "order_index": 1,
                            "estimated_minutes": 20,
                            "xp_reward": 15,
                            "total_exercises": 6,
                            "lesson_type": "lesson"
                        }
                    ]
                }
            ]
        }
    ]
    
    print("🌱 Starting to seed courses...")
    
    for course_data in courses_data:
        units_data = course_data.pop("units", [])
        
        # Create course
        course = Course(**course_data)
        db.add(course)
        await db.flush()  # Get course ID
        
        print(f"  ✅ Created course: {course.title}")
        
        # Create units and lessons
        total_lessons = 0
        for unit_data in units_data:
            lessons_data = unit_data.pop("lessons", [])
            
            unit = Unit(
                course_id=course.id,
                **unit_data
            )
            db.add(unit)
            await db.flush()  # Get unit ID
            
            print(f"    📦 Created unit: {unit.title}")
            
            # Create lessons
            for lesson_data in lessons_data:
                lesson = Lesson(
                    course_id=course.id,
                    unit_id=unit.id,
                    **lesson_data
                )
                db.add(lesson)
                total_lessons += 1
                print(f"      📝 Created lesson: {lesson.title}")
            
            # Update unit's total_lessons
            unit.total_lessons = len(lessons_data)
        
        # Update course's total_lessons
        course.total_lessons = total_lessons
    
    await db.commit()
    print(f"\n✨ Successfully seeded {len(courses_data)} courses!")


async def main():
    """Main function to run seeding"""
    print("=" * 60)
    print("LexiLingo - Course Database Seeding")
    print("=" * 60)
    
    async with AsyncSessionLocal() as db:
        try:
            # Check if courses already exist
            from sqlalchemy import select
            result = await db.execute(select(Course))
            existing_courses = len(result.scalars().all())
            
            if existing_courses > 0:
                print(f"\n⚠️  Found {existing_courses} existing courses.")
                print("Adding more courses...")
            
            await create_sample_courses(db)
            
            # Print summary
            result = await db.execute(select(Course))
            total_courses = len(result.scalars().all())
            
            from app.models.course import Unit, Lesson
            result = await db.execute(select(Unit))
            total_units = len(result.scalars().all())
            
            result = await db.execute(select(Lesson))
            total_lessons = len(result.scalars().all())
            
            print("\n" + "=" * 60)
            print("📊 Database Summary:")
            print(f"  Courses: {total_courses}")
            print(f"  Units: {total_units}")
            print(f"  Lessons: {total_lessons}")
            print("=" * 60)
            
        except Exception as e:
            print(f"\n❌ Error seeding database: {e}")
            await db.rollback()
            raise


if __name__ == "__main__":
    asyncio.run(main())
