"""baseline: create the 23 tables that predate Alembic entirely

Every migration before this one assumed users/courses/lessons/... already
existed (they were created ad hoc, pre-Alembic). `alembic upgrade head`
from an empty database fails immediately on the very first migration
because of this. This migration recreates their ORIGINAL shape -- current
model minus every column/constraint/index a later migration in this same
chain already adds via ALTER -- so the rest of the chain applies unchanged
on top. See BACKEND_AUDIT_REPORT.md finding #3.

Existing databases (already stamped past this point in alembic_version)
are unaffected: alembic only runs migrations between a DB's current
revision and the target, and this revision sits before all of them.

Known-harmless name collision: this migration creates a plain unique
index `uq_xp_transactions_user_source_ref`, matching the current model.
`game_award_idempotency` later re-creates the same name as a *partial*
unique index (`WHERE source_id IS NOT NULL`) via `CREATE UNIQUE INDEX IF
NOT EXISTS`, which silently no-ops against the one created here. No
functional gap: Postgres already treats NULL source_id values as
distinct in a plain unique index, so both forms enforce the same
constraint for the rows that matter.

Revision ID: baseline_pre_alembic_tables
Revises:
Create Date: 2026-08-07
"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op

revision: str = "baseline_pre_alembic_tables"
down_revision: str | None = None
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE api_cache_entries (
	id UUID NOT NULL, 
	cache_key VARCHAR(512) NOT NULL, 
	api_name VARCHAR(50) NOT NULL, 
	data TEXT NOT NULL, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	hit_count INTEGER NOT NULL, 
	PRIMARY KEY (id)
);
        """
    )
    op.execute(
        """
        CREATE INDEX idx_api_cache_api_updated ON api_cache_entries (api_name, updated_at);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_api_cache_entries_api_name ON api_cache_entries (api_name);
        """
    )
    op.execute(
        """
        CREATE UNIQUE INDEX ix_api_cache_entries_cache_key ON api_cache_entries (cache_key);
        """
    )
    op.execute(
        """
        CREATE TABLE course_categories (
	id UUID NOT NULL, 
	name VARCHAR(100) NOT NULL, 
	slug VARCHAR(100) NOT NULL, 
	description TEXT, 
	icon VARCHAR(50), 
	color VARCHAR(20), 
	order_index INTEGER NOT NULL, 
	is_active BOOLEAN NOT NULL, 
	course_count INTEGER NOT NULL, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	UNIQUE (name)
);
        """
    )
    op.execute(
        """
        CREATE INDEX idx_category_active_order ON course_categories (is_active, order_index);
        """
    )
    op.execute(
        """
        CREATE UNIQUE INDEX ix_course_categories_slug ON course_categories (slug);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_course_categories_is_active ON course_categories (is_active);
        """
    )
    op.execute(
        """
        CREATE TABLE game_words (
	id UUID NOT NULL, 
	word VARCHAR(100) NOT NULL, 
	definition TEXT NOT NULL, 
	hint TEXT, 
	example_sentence TEXT, 
	ipa_pronunciation VARCHAR(200), 
	cefr_level VARCHAR(2) NOT NULL, 
	category VARCHAR(50) NOT NULL, 
	synonyms JSONB, 
	vietnamese_translation VARCHAR(200), 
	letter_count INTEGER NOT NULL, 
	xp_value INTEGER NOT NULL, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id)
);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_game_words_word ON game_words (word);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_game_words_category ON game_words (category);
        """
    )
    op.execute(
        """
        CREATE INDEX idx_game_words_level_category ON game_words (cefr_level, category);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_game_words_cefr_level ON game_words (cefr_level);
        """
    )
    op.execute(
        """
        CREATE TABLE media_resources (
	id UUID NOT NULL, 
	resource_type VARCHAR(20) NOT NULL, 
	url VARCHAR(500) NOT NULL, 
	filename VARCHAR(255) NOT NULL, 
	duration INTEGER, 
	size INTEGER, 
	mime_type VARCHAR(100), 
	reference_count INTEGER NOT NULL, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id)
);
        """
    )
    op.execute(
        """
        CREATE UNIQUE INDEX ix_media_resources_url ON media_resources (url);
        """
    )
    op.execute(
        """
        CREATE TABLE notifications (
	id UUID NOT NULL, 
	user_id UUID NOT NULL, 
	title VARCHAR(255) NOT NULL, 
	body TEXT NOT NULL, 
	type VARCHAR(50) NOT NULL, 
	data JSONB, 
	is_read BOOLEAN NOT NULL, 
	read_at TIMESTAMP WITHOUT TIME ZONE, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id)
);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_notifications_user_id ON notifications (user_id);
        """
    )
    op.execute(
        """
        CREATE TABLE refresh_tokens (
	id UUID NOT NULL, 
	user_id UUID NOT NULL, 
	token VARCHAR(500) NOT NULL, 
	device_id VARCHAR(255), 
	is_revoked BOOLEAN NOT NULL, 
	is_used BOOLEAN NOT NULL, 
	expires_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	revoked_at TIMESTAMP WITHOUT TIME ZONE, 
	PRIMARY KEY (id)
);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_refresh_tokens_user_id ON refresh_tokens (user_id);
        """
    )
    op.execute(
        """
        CREATE UNIQUE INDEX ix_refresh_tokens_token ON refresh_tokens (token);
        """
    )
    op.execute(
        """
        CREATE TABLE user_devices (
	id UUID NOT NULL, 
	user_id UUID NOT NULL, 
	device_id VARCHAR(255) NOT NULL, 
	fcm_token VARCHAR(500), 
	device_type VARCHAR(20) NOT NULL, 
	device_name VARCHAR(100), 
	last_active TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id)
);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_user_devices_user_id ON user_devices (user_id);
        """
    )
    op.execute(
        """
        CREATE UNIQUE INDEX ix_user_devices_device_id ON user_devices (device_id);
        """
    )
    op.execute(
        """
        CREATE TABLE users (
	id UUID NOT NULL, 
	email VARCHAR(255) NOT NULL, 
	username VARCHAR(100) NOT NULL, 
	hashed_password VARCHAR(255) NOT NULL, 
	display_name VARCHAR(100), 
	avatar_url VARCHAR(500), 
	native_language VARCHAR(10) NOT NULL, 
	target_language VARCHAR(10) NOT NULL, 
	level VARCHAR(20) NOT NULL, 
	total_xp INTEGER NOT NULL, 
	is_active BOOLEAN NOT NULL, 
	is_verified BOOLEAN NOT NULL, 
	provider JSONB NOT NULL, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	last_login TIMESTAMP WITHOUT TIME ZONE, 
	last_login_ip VARCHAR(50), 
	PRIMARY KEY (id)
);
        """
    )
    op.execute(
        """
        CREATE UNIQUE INDEX ix_users_email ON users (email);
        """
    )
    op.execute(
        """
        CREATE UNIQUE INDEX ix_users_username ON users (username);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_users_id ON users (id);
        """
    )
    op.execute(
        """
        CREATE TABLE challenge_reward_claims (
	id UUID NOT NULL, 
	user_id UUID NOT NULL, 
	challenge_id VARCHAR(100) NOT NULL, 
	claim_date TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	xp_reward INTEGER NOT NULL, 
	gems_reward INTEGER NOT NULL, 
	claimed_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE
);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_challenge_reward_claims_user_id ON challenge_reward_claims (user_id);
        """
    )
    op.execute(
        """
        CREATE UNIQUE INDEX idx_challenge_claim_user_date ON challenge_reward_claims (user_id, challenge_id, claim_date);
        """
    )
    op.execute(
        """
        CREATE TABLE courses (
	id UUID NOT NULL, 
	title VARCHAR(255) NOT NULL, 
	description TEXT, 
	language VARCHAR(10) NOT NULL, 
	level VARCHAR(20) NOT NULL, 
	category_id UUID, 
	tags JSONB, 
	total_xp INTEGER NOT NULL, 
	estimated_duration INTEGER NOT NULL, 
	content_version INTEGER NOT NULL, 
	total_lessons INTEGER NOT NULL, 
	thumbnail_url VARCHAR(500), 
	is_published BOOLEAN NOT NULL, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(category_id) REFERENCES course_categories (id) ON DELETE SET NULL
);
        """
    )
    op.execute(
        """
        CREATE INDEX idx_course_published_created_at ON courses (is_published, created_at);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_courses_category_id ON courses (category_id);
        """
    )
    op.execute(
        """
        CREATE INDEX idx_course_level_published ON courses (level, is_published);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_courses_level ON courses (level);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_courses_is_published ON courses (is_published);
        """
    )
    op.execute(
        """
        CREATE INDEX idx_course_published_lang_level ON courses (is_published, language, level);
        """
    )
    op.execute(
        """
        CREATE TABLE daily_activities (
	id UUID NOT NULL, 
	user_id UUID NOT NULL, 
	activity_date DATE NOT NULL, 
	xp_earned INTEGER NOT NULL, 
	lessons_completed INTEGER NOT NULL, 
	study_time_minutes INTEGER NOT NULL, 
	vocabulary_reviewed INTEGER NOT NULL, 
	daily_goal_met BOOLEAN NOT NULL, 
	daily_goal_xp INTEGER NOT NULL, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE
);
        """
    )
    op.execute(
        """
        CREATE INDEX idx_daily_activity_week ON daily_activities (user_id, activity_date);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_daily_activities_user_id ON daily_activities (user_id);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_daily_activities_activity_date ON daily_activities (activity_date);
        """
    )
    op.execute(
        """
        CREATE UNIQUE INDEX idx_daily_activity_user_date ON daily_activities (user_id, activity_date);
        """
    )
    op.execute(
        """
        CREATE TABLE daily_review_sessions (
	id UUID NOT NULL, 
	user_id UUID NOT NULL, 
	review_date DATE NOT NULL, 
	total_words INTEGER NOT NULL, 
	completed_words INTEGER NOT NULL, 
	correct_count INTEGER NOT NULL, 
	started_at TIMESTAMP WITHOUT TIME ZONE, 
	completed_at TIMESTAMP WITHOUT TIME ZONE, 
	is_completed BOOLEAN NOT NULL, 
	vocab_list JSONB, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE
);
        """
    )
    op.execute(
        """
        CREATE INDEX idx_daily_review_user_date ON daily_review_sessions (user_id, review_date);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_daily_review_sessions_user_id ON daily_review_sessions (user_id);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_daily_review_sessions_review_date ON daily_review_sessions (review_date);
        """
    )
    op.execute(
        """
        CREATE TABLE game_sessions (
	id UUID NOT NULL, 
	user_id UUID NOT NULL, 
	game_type VARCHAR(50) NOT NULL, 
	score INTEGER NOT NULL, 
	total_questions INTEGER NOT NULL, 
	correct_answers INTEGER NOT NULL, 
	xp_earned INTEGER NOT NULL, 
	cefr_level VARCHAR(2), 
	category VARCHAR(50), 
	duration_seconds INTEGER, 
	started_at TIMESTAMP WITHOUT TIME ZONE, 
	completed_at TIMESTAMP WITHOUT TIME ZONE, 
	xp_awarded BOOLEAN NOT NULL, 
	session_data JSONB, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE
);
        """
    )
    op.execute(
        """
        CREATE INDEX idx_game_sessions_created ON game_sessions (created_at);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_game_sessions_user_id ON game_sessions (user_id);
        """
    )
    op.execute(
        """
        CREATE INDEX idx_game_sessions_user_type ON game_sessions (user_id, game_type);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_game_sessions_game_type ON game_sessions (game_type);
        """
    )
    op.execute(
        """
        CREATE TABLE streaks (
	id UUID NOT NULL, 
	user_id UUID NOT NULL, 
	current_streak INTEGER NOT NULL, 
	longest_streak INTEGER NOT NULL, 
	last_activity_date DATE, 
	total_days_active INTEGER NOT NULL, 
	freeze_count INTEGER NOT NULL, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE
);
        """
    )
    op.execute(
        """
        CREATE UNIQUE INDEX ix_streaks_user_id ON streaks (user_id);
        """
    )
    op.execute(
        """
        CREATE TABLE user_vocab_knowledge (
	id UUID NOT NULL, 
	user_id UUID NOT NULL, 
	vocab_id UUID NOT NULL, 
	strength FLOAT NOT NULL, 
	ease_factor FLOAT NOT NULL, 
	interval_days INTEGER NOT NULL, 
	last_review_date TIMESTAMP WITHOUT TIME ZONE, 
	next_review_date TIMESTAMP WITHOUT TIME ZONE, 
	review_count INTEGER NOT NULL, 
	consecutive_correct INTEGER NOT NULL, 
	review_history JSONB, 
	mastery_level VARCHAR(20) NOT NULL, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE
);
        """
    )
    op.execute(
        """
        CREATE INDEX idx_vocab_knowledge_user_next_review ON user_vocab_knowledge (user_id, next_review_date);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_user_vocab_knowledge_user_id ON user_vocab_knowledge (user_id);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_user_vocab_knowledge_vocab_id ON user_vocab_knowledge (vocab_id);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_user_vocab_knowledge_next_review_date ON user_vocab_knowledge (next_review_date);
        """
    )
    op.execute(
        """
        CREATE TABLE xp_transactions (
	id UUID NOT NULL, 
	user_id UUID NOT NULL, 
	amount INTEGER NOT NULL, 
	base_amount INTEGER NOT NULL, 
	multiplier FLOAT NOT NULL, 
	source VARCHAR(50) NOT NULL, 
	source_id VARCHAR(100), 
	source_detail VARCHAR(100), 
	level_before INTEGER, 
	level_after INTEGER, 
	leveled_up BOOLEAN NOT NULL, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE
);
        """
    )
    op.execute(
        """
        CREATE UNIQUE INDEX uq_xp_transactions_user_source_ref ON xp_transactions (user_id, source, source_id);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_xp_transactions_source ON xp_transactions (source);
        """
    )
    op.execute(
        """
        CREATE INDEX idx_xp_transactions_user_created ON xp_transactions (user_id, created_at);
        """
    )
    op.execute(
        """
        CREATE INDEX idx_xp_transactions_source ON xp_transactions (source);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_xp_transactions_created_at ON xp_transactions (created_at);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_xp_transactions_user_id ON xp_transactions (user_id);
        """
    )
    op.execute(
        """
        CREATE TABLE units (
	id UUID NOT NULL, 
	course_id UUID NOT NULL, 
	title VARCHAR(255) NOT NULL, 
	description TEXT, 
	order_index INTEGER NOT NULL, 
	background_color VARCHAR(20), 
	icon_url VARCHAR(500), 
	total_lessons INTEGER NOT NULL, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(course_id) REFERENCES courses (id) ON DELETE CASCADE
);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_units_course_id ON units (course_id);
        """
    )
    op.execute(
        """
        CREATE INDEX idx_unit_course_order ON units (course_id, order_index);
        """
    )
    op.execute(
        """
        CREATE TABLE user_course_progress (
	id UUID NOT NULL, 
	user_id UUID NOT NULL, 
	course_id UUID NOT NULL, 
	progress_percentage FLOAT NOT NULL, 
	lessons_completed INTEGER NOT NULL, 
	total_xp_earned INTEGER NOT NULL, 
	started_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	last_activity_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE, 
	FOREIGN KEY(course_id) REFERENCES courses (id) ON DELETE CASCADE
);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_user_course_progress_user_id ON user_course_progress (user_id);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_user_course_progress_course_id ON user_course_progress (course_id);
        """
    )
    op.execute(
        """
        CREATE UNIQUE INDEX idx_user_course_unique ON user_course_progress (user_id, course_id);
        """
    )
    op.execute(
        """
        CREATE TABLE lessons (
	id UUID NOT NULL, 
	course_id UUID NOT NULL, 
	unit_id UUID, 
	title VARCHAR(255) NOT NULL, 
	description TEXT, 
	order_index INTEGER NOT NULL, 
	prerequisites UUID[], 
	pass_threshold INTEGER NOT NULL, 
	content JSONB, 
	content_version INTEGER NOT NULL, 
	estimated_minutes INTEGER NOT NULL, 
	xp_reward INTEGER NOT NULL, 
	total_exercises INTEGER NOT NULL, 
	lesson_type VARCHAR(50) NOT NULL, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(course_id) REFERENCES courses (id) ON DELETE CASCADE, 
	FOREIGN KEY(unit_id) REFERENCES units (id) ON DELETE CASCADE
);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_lessons_course_id ON lessons (course_id);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_lessons_unit_id ON lessons (unit_id);
        """
    )
    op.execute(
        """
        CREATE INDEX idx_lesson_unit_order ON lessons (unit_id, order_index);
        """
    )
    op.execute(
        """
        CREATE INDEX idx_lesson_course_order ON lessons (course_id, order_index);
        """
    )
    op.execute(
        """
        CREATE TABLE lesson_attempts (
	id UUID NOT NULL, 
	user_id UUID NOT NULL, 
	lesson_id UUID NOT NULL, 
	started_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	finished_at TIMESTAMP WITHOUT TIME ZONE, 
	score INTEGER NOT NULL, 
	passed BOOLEAN NOT NULL, 
	xp_earned INTEGER NOT NULL, 
	total_questions INTEGER NOT NULL, 
	correct_answers INTEGER NOT NULL, 
	hints_used INTEGER NOT NULL, 
	lives_remaining INTEGER NOT NULL, 
	time_spent_ms INTEGER NOT NULL, 
	avg_response_time_ms INTEGER NOT NULL, 
	device_type VARCHAR(20), 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE, 
	FOREIGN KEY(lesson_id) REFERENCES lessons (id) ON DELETE CASCADE
);
        """
    )
    op.execute(
        """
        CREATE INDEX idx_lesson_attempt_user_lesson ON lesson_attempts (user_id, lesson_id);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_lesson_attempts_lesson_id ON lesson_attempts (lesson_id);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_lesson_attempts_user_id ON lesson_attempts (user_id);
        """
    )
    op.execute(
        """
        CREATE TABLE lesson_completions (
	id UUID NOT NULL, 
	user_id UUID NOT NULL, 
	lesson_id UUID NOT NULL, 
	is_passed BOOLEAN NOT NULL, 
	best_score INTEGER NOT NULL, 
	completed_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE, 
	FOREIGN KEY(lesson_id) REFERENCES lessons (id) ON DELETE CASCADE
);
        """
    )
    op.execute(
        """
        CREATE UNIQUE INDEX idx_user_lesson_unique ON lesson_completions (user_id, lesson_id);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_lesson_completions_user_id ON lesson_completions (user_id);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_lesson_completions_lesson_id ON lesson_completions (lesson_id);
        """
    )
    op.execute(
        """
        CREATE TABLE user_progress (
	id UUID NOT NULL, 
	user_id UUID NOT NULL, 
	lesson_id UUID NOT NULL, 
	course_id UUID NOT NULL, 
	status VARCHAR(20) NOT NULL, 
	score INTEGER NOT NULL, 
	completed_at TIMESTAMP WITHOUT TIME ZONE, 
	time_spent_seconds INTEGER NOT NULL, 
	attempts INTEGER NOT NULL, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE, 
	FOREIGN KEY(lesson_id) REFERENCES lessons (id) ON DELETE CASCADE, 
	FOREIGN KEY(course_id) REFERENCES courses (id) ON DELETE CASCADE
);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_user_progress_lesson_id ON user_progress (lesson_id);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_user_progress_course_id ON user_progress (course_id);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_user_progress_user_id ON user_progress (user_id);
        """
    )
    op.execute(
        """
        CREATE TABLE question_attempts (
	id UUID NOT NULL, 
	lesson_attempt_id UUID NOT NULL, 
	question_id VARCHAR(255) NOT NULL, 
	question_type VARCHAR(50) NOT NULL, 
	user_answer TEXT, 
	correct_answer TEXT, 
	is_correct BOOLEAN NOT NULL, 
	time_spent_ms INTEGER NOT NULL, 
	hint_used BOOLEAN NOT NULL, 
	attempt_number INTEGER NOT NULL, 
	confidence_score FLOAT, 
	difficulty_rating VARCHAR(20), 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(lesson_attempt_id) REFERENCES lesson_attempts (id) ON DELETE CASCADE
);
        """
    )
    op.execute(
        """
        CREATE INDEX idx_question_attempt_lesson ON question_attempts (lesson_attempt_id, question_id);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_question_attempts_lesson_attempt_id ON question_attempts (lesson_attempt_id);
        """
    )
    op.execute(
        """
        CREATE INDEX ix_question_attempts_question_id ON question_attempts (question_id);
        """
    )


def downgrade() -> None:
    op.execute(
        """
        DROP TABLE IF EXISTS question_attempts CASCADE;
        """
    )
    op.execute(
        """
        DROP TABLE IF EXISTS user_progress CASCADE;
        """
    )
    op.execute(
        """
        DROP TABLE IF EXISTS lesson_completions CASCADE;
        """
    )
    op.execute(
        """
        DROP TABLE IF EXISTS lesson_attempts CASCADE;
        """
    )
    op.execute(
        """
        DROP TABLE IF EXISTS lessons CASCADE;
        """
    )
    op.execute(
        """
        DROP TABLE IF EXISTS user_course_progress CASCADE;
        """
    )
    op.execute(
        """
        DROP TABLE IF EXISTS units CASCADE;
        """
    )
    op.execute(
        """
        DROP TABLE IF EXISTS xp_transactions CASCADE;
        """
    )
    op.execute(
        """
        DROP TABLE IF EXISTS user_vocab_knowledge CASCADE;
        """
    )
    op.execute(
        """
        DROP TABLE IF EXISTS streaks CASCADE;
        """
    )
    op.execute(
        """
        DROP TABLE IF EXISTS game_sessions CASCADE;
        """
    )
    op.execute(
        """
        DROP TABLE IF EXISTS daily_review_sessions CASCADE;
        """
    )
    op.execute(
        """
        DROP TABLE IF EXISTS daily_activities CASCADE;
        """
    )
    op.execute(
        """
        DROP TABLE IF EXISTS courses CASCADE;
        """
    )
    op.execute(
        """
        DROP TABLE IF EXISTS challenge_reward_claims CASCADE;
        """
    )
    op.execute(
        """
        DROP TABLE IF EXISTS users CASCADE;
        """
    )
    op.execute(
        """
        DROP TABLE IF EXISTS user_devices CASCADE;
        """
    )
    op.execute(
        """
        DROP TABLE IF EXISTS refresh_tokens CASCADE;
        """
    )
    op.execute(
        """
        DROP TABLE IF EXISTS notifications CASCADE;
        """
    )
    op.execute(
        """
        DROP TABLE IF EXISTS media_resources CASCADE;
        """
    )
    op.execute(
        """
        DROP TABLE IF EXISTS game_words CASCADE;
        """
    )
    op.execute(
        """
        DROP TABLE IF EXISTS course_categories CASCADE;
        """
    )
    op.execute(
        """
        DROP TABLE IF EXISTS api_cache_entries CASCADE;
        """
    )
