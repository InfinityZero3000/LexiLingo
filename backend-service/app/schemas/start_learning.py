import uuid

from pydantic import BaseModel


class StartLearningRequest(BaseModel):
    course_id: uuid.UUID | None = None


class StartLearningResponse(BaseModel):
    course_id: uuid.UUID
    course_title: str
    first_lesson_id: uuid.UUID
    already_enrolled: bool
