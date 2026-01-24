"""
SQLAlchemy Models

Import all models here for Alembic auto-detection
"""

from app.models.user import User
from app.models.course import Course, Lesson
from app.models.vocabulary import Vocabulary, UserVocabulary
from app.models.progress import UserProgress, Streak

__all__ = [
    "User",
    "Course",
    "Lesson",
    "Vocabulary",
    "UserVocabulary",
    "UserProgress",
    "Streak",
]
