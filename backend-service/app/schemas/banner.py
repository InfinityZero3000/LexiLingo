"""Request/response schemas for Banner endpoints."""

from datetime import datetime
from typing import Literal, Optional
import uuid

from pydantic import BaseModel, ConfigDict, Field

BannerPosition = Literal["hero", "sidebar", "interstitial"]


class BannerBase(BaseModel):
    title: str = Field(..., min_length=1, max_length=200)
    description: Optional[str] = None
    image_url: str = Field(..., min_length=1, max_length=1000)
    link_url: Optional[str] = Field(None, max_length=1000)
    position: BannerPosition = Field(default="hero")
    priority: int = Field(default=0)
    is_active: bool = Field(default=True)
    start_at: Optional[datetime] = None
    end_at: Optional[datetime] = None
    target_min_level: Optional[str] = Field(None, max_length=10)
    target_max_level: Optional[str] = Field(None, max_length=10)
    target_language: Optional[str] = Field(None, max_length=10)


class BannerCreate(BannerBase):
    pass


class BannerUpdate(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=200)
    description: Optional[str] = None
    image_url: Optional[str] = Field(None, min_length=1, max_length=1000)
    link_url: Optional[str] = Field(None, max_length=1000)
    position: Optional[BannerPosition] = None
    priority: Optional[int] = None
    is_active: Optional[bool] = None
    start_at: Optional[datetime] = None
    end_at: Optional[datetime] = None
    target_min_level: Optional[str] = Field(None, max_length=10)
    target_max_level: Optional[str] = Field(None, max_length=10)
    target_language: Optional[str] = Field(None, max_length=10)


class BannerResponse(BannerBase):
    id: uuid.UUID
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class BannerPublic(BaseModel):
    """Minimal shape exposed to learners — no targeting/priority/schedule internals."""

    id: uuid.UUID
    title: str
    description: Optional[str] = None
    image_url: str
    link_url: Optional[str] = None
    position: BannerPosition

    model_config = ConfigDict(from_attributes=True)
