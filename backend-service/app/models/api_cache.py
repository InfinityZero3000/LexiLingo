"""
API Cache Entry Model — Persistent Cache Storage in PostgreSQL

Stores all external API responses for long-term caching and fallback.
Used as Layer 2 in the 3-layer cache architecture.

Phase 0 Infrastructure: Required by APICacheService.
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import DateTime, Index, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.core.db_types import GUID


class APICacheEntry(Base):
    """
    Persistent cache for external API responses.
    
    Key design decisions:
    - cache_key is the unique lookup (e.g. "news:en:tech:2026-02-24")
    - api_name enables per-API analytics and cleanup
    - data stores the raw JSON response as text
    - hit_count tracks popularity for cache warming decisions
    - updated_at is used for TTL freshness checks
    """
    
    __tablename__ = "api_cache_entries"
    
    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4,
    )
    
    # Cache lookup key (e.g. "news:en:tech:2026-02-24")
    cache_key: Mapped[str] = mapped_column(
        String(512),
        unique=True,
        nullable=False,
        index=True,
    )
    
    # API source identifier (e.g. "newsapi", "youtube", "gutenberg")
    api_name: Mapped[str] = mapped_column(
        String(50),
        nullable=False,
        index=True,
    )
    
    # Raw JSON response data
    data: Mapped[str] = mapped_column(Text, nullable=False)
    
    # Timestamps
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(timezone.utc), nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    
    # Analytics
    hit_count: Mapped[int] = mapped_column(Integer, default=0)
    
    def is_expired(self, ttl_seconds: int) -> bool:
        """Check if this entry is older than the given TTL."""
        if self.updated_at is None:
            return True
        age = (datetime.now(timezone.utc) - self.updated_at).total_seconds()
        return age > ttl_seconds
    
    @property
    def age_seconds(self) -> float:
        """Get age of this cache entry in seconds."""
        if self.updated_at is None:
            return float('inf')
        return (datetime.now(timezone.utc) - self.updated_at).total_seconds()
    
    def __repr__(self) -> str:
        return (
            f"<APICacheEntry key={self.cache_key!r} "
            f"api={self.api_name} hits={self.hit_count}>"
        )


# Composite index for per-API cleanup queries
Index(
    "idx_api_cache_api_updated",
    APICacheEntry.api_name,
    APICacheEntry.updated_at,
)
