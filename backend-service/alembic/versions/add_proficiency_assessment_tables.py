"""Add proficiency assessment tables

Revision ID: add_proficiency_tables
Revises: 
Create Date: 2026-02-02

Adds tables for multi-dimensional proficiency assessment:
- user_proficiency_profiles: Overall proficiency profile
- user_skill_scores: Individual skill scores (vocab, grammar, etc.)
- user_level_history: Level change history
- exercise_attempts: Individual exercise tracking
- level_assessment_tests: Formal assessment test records
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID, JSONB


# revision identifiers, used by Alembic.
revision = 'add_proficiency_tables'
down_revision = None  # Update this to the latest revision
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Create SkillType enum
    skill_type_enum = sa.Enum(
        'vocabulary', 'grammar', 'reading', 'listening', 'speaking', 'writing',
        name='skilltype'
    )
    skill_type_enum.create(op.get_bind(), checkfirst=True)

    # Create user_proficiency_profiles table
    op.create_table(
        'user_proficiency_profiles',
        sa.Column('id', UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), unique=True, nullable=False),
        sa.Column('assessed_level', sa.String(5), default='A1', nullable=False),
        sa.Column('overall_score', sa.Float, default=0.0),
        sa.Column('total_xp', sa.Integer, default=0),
        sa.Column('total_exercises_completed', sa.Integer, default=0),
        sa.Column('total_correct_exercises', sa.Integer, default=0),
        sa.Column('total_lessons_completed', sa.Integer, default=0),
        sa.Column('last_assessment_at', sa.DateTime, nullable=True),
        sa.Column('last_level_change_at', sa.DateTime, nullable=True),
        sa.Column('created_at', sa.DateTime, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime, server_default=sa.func.now(), onupdate=sa.func.now()),
    )
    op.create_index('idx_proficiency_user_id', 'user_proficiency_profiles', ['user_id'])

    # Create user_skill_scores table
    op.create_table(
        'user_skill_scores',
        sa.Column('id', UUID(as_uuid=True), primary_key=True),
        sa.Column('profile_id', UUID(as_uuid=True), sa.ForeignKey('user_proficiency_profiles.id', ondelete='CASCADE'), nullable=False),
        sa.Column('skill', skill_type_enum, nullable=False),
        sa.Column('score', sa.Float, default=0.0),
        sa.Column('confidence', sa.Float, default=0.0),
        sa.Column('estimated_level', sa.String(5), default='A1'),
        sa.Column('exercises_completed', sa.Integer, default=0),
        sa.Column('correct_exercises', sa.Integer, default=0),
        sa.Column('score_7d_ago', sa.Float, nullable=True),
        sa.Column('score_30d_ago', sa.Float, nullable=True),
        sa.Column('last_updated', sa.DateTime, server_default=sa.func.now(), onupdate=sa.func.now()),
    )
    op.create_index('idx_skill_scores_profile', 'user_skill_scores', ['profile_id'])
    op.create_unique_constraint('uq_skill_scores_profile_skill', 'user_skill_scores', ['profile_id', 'skill'])

    # Create user_level_history table
    op.create_table(
        'user_level_history',
        sa.Column('id', UUID(as_uuid=True), primary_key=True),
        sa.Column('profile_id', UUID(as_uuid=True), sa.ForeignKey('user_proficiency_profiles.id', ondelete='CASCADE'), nullable=False),
        sa.Column('previous_level', sa.String(5), nullable=False),
        sa.Column('new_level', sa.String(5), nullable=False),
        sa.Column('change_type', sa.String(20), nullable=False),
        sa.Column('overall_score', sa.Float, nullable=True),
        sa.Column('skill_scores_snapshot', JSONB, nullable=True),
        sa.Column('exercises_completed', sa.Integer, nullable=True),
        sa.Column('accuracy', sa.Float, nullable=True),
        sa.Column('reason', sa.Text, nullable=True),
        sa.Column('triggered_at', sa.DateTime, server_default=sa.func.now()),
    )
    op.create_index('idx_level_history_profile', 'user_level_history', ['profile_id'])
    op.create_index('idx_level_history_triggered', 'user_level_history', ['triggered_at'])

    # Create exercise_attempts table
    op.create_table(
        'exercise_attempts',
        sa.Column('id', UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('exercise_type', sa.String(50), nullable=False),
        sa.Column('skill', skill_type_enum, nullable=False),
        sa.Column('difficulty_level', sa.String(5), nullable=False),
        sa.Column('is_correct', sa.Boolean, nullable=False),
        sa.Column('score', sa.Float, nullable=False),
        sa.Column('time_spent_seconds', sa.Integer, default=0),
        sa.Column('lesson_id', UUID(as_uuid=True), sa.ForeignKey('lessons.id', ondelete='SET NULL'), nullable=True),
        sa.Column('course_id', UUID(as_uuid=True), sa.ForeignKey('courses.id', ondelete='SET NULL'), nullable=True),
        sa.Column('attempted_at', sa.DateTime, server_default=sa.func.now()),
        sa.Column('metadata', JSONB, nullable=True),
    )
    op.create_index('idx_exercise_attempts_user', 'exercise_attempts', ['user_id'])
    op.create_index('idx_exercise_attempts_date', 'exercise_attempts', ['attempted_at'])
    op.create_index('idx_exercise_attempts_skill', 'exercise_attempts', ['skill'])

    # Create level_assessment_tests table
    op.create_table(
        'level_assessment_tests',
        sa.Column('id', UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('test_type', sa.String(20), nullable=False),
        sa.Column('assessed_level', sa.String(5), nullable=False),
        sa.Column('overall_score', sa.Float, nullable=False),
        sa.Column('skill_scores', JSONB, nullable=False),
        sa.Column('questions_count', sa.Integer, nullable=False),
        sa.Column('correct_count', sa.Integer, nullable=False),
        sa.Column('time_taken_seconds', sa.Integer, nullable=True),
        sa.Column('started_at', sa.DateTime, nullable=False),
        sa.Column('completed_at', sa.DateTime, server_default=sa.func.now()),
        sa.Column('level_changed', sa.Boolean, default=False),
        sa.Column('previous_level', sa.String(5), nullable=True),
    )
    op.create_index('idx_assessment_tests_user', 'level_assessment_tests', ['user_id'])
    op.create_index('idx_assessment_tests_completed', 'level_assessment_tests', ['completed_at'])


def downgrade() -> None:
    op.drop_table('level_assessment_tests')
    op.drop_table('exercise_attempts')
    op.drop_table('user_level_history')
    op.drop_table('user_skill_scores')
    op.drop_table('user_proficiency_profiles')
    
    # Drop enum
    skill_type_enum = sa.Enum(name='skilltype')
    skill_type_enum.drop(op.get_bind(), checkfirst=True)
