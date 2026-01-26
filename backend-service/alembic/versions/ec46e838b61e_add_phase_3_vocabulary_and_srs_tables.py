"""Add Phase 3 vocabulary and SRS tables

Revision ID: ec46e838b61e
Revises: 
Create Date: 2026-01-25 15:08:30.056637

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = 'ec46e838b61e'
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ENUMs will be created automatically by SQLAlchemy when creating tables
    # No need for manual CREATE TYPE statements
    
    # Create vocabulary_items table
    op.create_table(
        'vocabulary_items',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('word', sa.String(255), nullable=False, index=True),
        sa.Column('definition', sa.Text, nullable=False),
        sa.Column('translation', postgresql.JSON, nullable=True),
        sa.Column('pronunciation', sa.String(100), nullable=True),
        sa.Column('audio_url', sa.String(500), nullable=True),
        sa.Column('part_of_speech', sa.Enum('noun', 'verb', 'adjective', 'adverb', 'pronoun', 'preposition', 'conjunction', 'interjection', 'phrase', name='part_of_speech_enum'), nullable=False, index=True),
        sa.Column('difficulty_level', sa.Enum('A1', 'A2', 'B1', 'B2', 'C1', 'C2', name='difficulty_level_enum'), nullable=False, index=True),
        sa.Column('course_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('courses.id', ondelete='SET NULL'), nullable=True, index=True),
        sa.Column('lesson_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('lessons.id', ondelete='SET NULL'), nullable=True, index=True),
        sa.Column('usage_frequency', sa.Integer, default=0),
        sa.Column('tags', postgresql.JSON, nullable=True),
        sa.Column('created_at', sa.DateTime, default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime, default=sa.func.now(), onupdate=sa.func.now())
    )
    
    # Create indexes for vocabulary_items
    op.create_index('ix_vocabulary_items_word_lower', 'vocabulary_items', ['word'])
    op.create_index('ix_vocabulary_items_course_difficulty', 'vocabulary_items', ['course_id', 'difficulty_level'])
    
    # Create user_vocabulary table (SRS data)
    op.create_table(
        'user_vocabulary',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('vocabulary_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('vocabulary_items.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('status', sa.Enum('learning', 'reviewing', 'mastered', 'archived', name='vocabulary_status_enum'), nullable=False, default='learning', index=True),
        sa.Column('ease_factor', sa.Float, default=2.5),
        sa.Column('interval', sa.Integer, default=1),
        sa.Column('repetitions', sa.Integer, default=0),
        sa.Column('next_review_date', sa.DateTime, default=sa.text("NOW() + INTERVAL '1 day'"), index=True),
        sa.Column('last_reviewed_at', sa.DateTime, nullable=True),
        sa.Column('total_reviews', sa.Integer, default=0),
        sa.Column('correct_reviews', sa.Integer, default=0),
        sa.Column('streak', sa.Integer, default=0),
        sa.Column('longest_streak', sa.Integer, default=0),
        sa.Column('total_xp_earned', sa.Integer, default=0),
        sa.Column('notes', sa.Text, nullable=True),
        sa.Column('added_at', sa.DateTime, default=sa.func.now())
    )
    
    # Create indexes for user_vocabulary
    op.create_index('ix_user_vocabulary_user_status', 'user_vocabulary', ['user_id', 'status'])
    op.create_index('ix_user_vocabulary_next_review', 'user_vocabulary', ['user_id', 'next_review_date'])
    op.create_index('ix_user_vocabulary_unique', 'user_vocabulary', ['user_id', 'vocabulary_id'], unique=True)
    
    # Create vocabulary_reviews table
    op.create_table(
        'vocabulary_reviews',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('user_vocabulary_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('user_vocabulary.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('quality', sa.Integer, nullable=False),
        sa.Column('time_spent_ms', sa.Integer, default=0),
        sa.Column('ease_factor_after', sa.Float, nullable=True),
        sa.Column('interval_after', sa.Integer, nullable=True),
        sa.Column('reviewed_at', sa.DateTime, default=sa.func.now(), index=True)
    )
    
    # Create index for vocabulary_reviews
    op.create_index('ix_vocabulary_reviews_user_vocab_date', 'vocabulary_reviews', ['user_vocabulary_id', 'reviewed_at'])
    
    # Create vocabulary_decks table (custom collections)
    op.create_table(
        'vocabulary_decks',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('name', sa.String(100), nullable=False),
        sa.Column('description', sa.Text, nullable=True),
        sa.Column('is_public', sa.Boolean, default=False),
        sa.Column('color', sa.String(7), default='#2196F3'),
        sa.Column('created_at', sa.DateTime, default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime, default=sa.func.now(), onupdate=sa.func.now())
    )
    
    op.create_index('ix_vocabulary_decks_user', 'vocabulary_decks', ['user_id'])
    
    # Create vocabulary_deck_items table (many-to-many)
    op.create_table(
        'vocabulary_deck_items',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('deck_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('vocabulary_decks.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('user_vocabulary_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('user_vocabulary.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('order', sa.Integer, default=0),
        sa.Column('added_at', sa.DateTime, default=sa.func.now())
    )
    
    op.create_index('ix_vocabulary_deck_items_unique', 'vocabulary_deck_items', ['deck_id', 'user_vocabulary_id'], unique=True)


def downgrade() -> None:
    # Drop tables in reverse order
    op.drop_table('vocabulary_deck_items')
    op.drop_table('vocabulary_decks')
    op.drop_table('vocabulary_reviews')
    op.drop_table('user_vocabulary')
    op.drop_table('vocabulary_items')
    
    # Drop ENUMs
    op.execute('DROP TYPE IF EXISTS vocabulary_status_enum')
    op.execute('DROP TYPE IF EXISTS difficulty_level_enum')
    op.execute('DROP TYPE IF EXISTS part_of_speech_enum')
