"""
Cross-database compatible type definitions.

This module provides type helpers that work with both PostgreSQL and SQLite.
Import GUID from here instead of using SQLAlchemy's PostgreSQL UUID directly.
"""

import uuid
from sqlalchemy import TypeDecorator, CHAR, Text
from sqlalchemy.dialects.postgresql import UUID as PG_UUID, ARRAY as PG_ARRAY


class GUID(TypeDecorator):
    """Platform-independent GUID type.
    
    Uses PostgreSQL's UUID type when available, otherwise stores as CHAR(36).
    Works with both PostgreSQL and SQLite.
    
    Usage:
        from app.core.db_types import GUID
        
        id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True)
    """
    impl = CHAR(36)
    cache_ok = True

    def load_dialect_impl(self, dialect):
        if dialect.name == 'postgresql':
            return dialect.type_descriptor(PG_UUID(as_uuid=True))
        else:
            return dialect.type_descriptor(CHAR(36))

    def process_bind_param(self, value, dialect):
        if value is None:
            return value
        elif dialect.name == 'postgresql':
            return value
        else:
            if isinstance(value, uuid.UUID):
                return str(value)
            else:
                return str(uuid.UUID(value))

    def process_result_value(self, value, dialect):
        if value is None:
            return value
        if isinstance(value, uuid.UUID):
            return value
        return uuid.UUID(value)


class GUIDArray(TypeDecorator):
    """Platform-independent array of GUIDs.
    
    Uses PostgreSQL's ARRAY(UUID) when available, otherwise stores as JSON string.
    Works with both PostgreSQL and SQLite.
    
    Usage:
        from app.core.db_types import GUIDArray
        
        prerequisites: Mapped[list] = mapped_column(GUIDArray(), nullable=True)
    """
    impl = Text
    cache_ok = True

    def load_dialect_impl(self, dialect):
        if dialect.name == 'postgresql':
            return dialect.type_descriptor(PG_ARRAY(PG_UUID(as_uuid=True)))
        else:
            return dialect.type_descriptor(Text())

    def process_bind_param(self, value, dialect):
        if value is None:
            return value
        elif dialect.name == 'postgresql':
            return value
        else:
            # Store as JSON array string for SQLite
            import json
            return json.dumps([str(v) if isinstance(v, uuid.UUID) else v for v in value])

    def process_result_value(self, value, dialect):
        if value is None:
            return value
        if dialect.name == 'postgresql':
            return value
        else:
            # Parse JSON array string for SQLite
            import json
            if isinstance(value, str):
                return [uuid.UUID(v) for v in json.loads(value)]
            return value
