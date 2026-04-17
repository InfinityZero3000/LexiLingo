-- LexiLingo PostgreSQL schema generated from SQLAlchemy models
-- Source: backend-service/app/models


CREATE TABLE achievements (
	id UUID NOT NULL, 
	name VARCHAR(100) NOT NULL, 
	slug VARCHAR(100), 
	description TEXT NOT NULL, 
	condition_type VARCHAR(50) NOT NULL, 
	condition_value INTEGER, 
	condition_data JSONB, 
	badge_icon VARCHAR(500), 
	badge_color VARCHAR(20), 
	category VARCHAR(50), 
	xp_reward INTEGER NOT NULL, 
	gems_reward INTEGER NOT NULL, 
	rarity VARCHAR(20) NOT NULL, 
	is_hidden BOOLEAN NOT NULL, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	UNIQUE (name), 
	UNIQUE (slug)
);


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


CREATE TABLE grammar_items (
	id UUID NOT NULL, 
	title VARCHAR(255) NOT NULL, 
	level VARCHAR(20) NOT NULL, 
	topic VARCHAR(100), 
	summary VARCHAR(500), 
	content TEXT NOT NULL, 
	examples JSONB, 
	tags JSONB, 
	is_active BOOLEAN NOT NULL, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id)
);


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


CREATE TABLE permissions (
	id UUID NOT NULL, 
	name VARCHAR(100) NOT NULL, 
	slug VARCHAR(100) NOT NULL, 
	resource VARCHAR(50) NOT NULL, 
	action VARCHAR(50) NOT NULL, 
	description TEXT, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	UNIQUE (name)
);


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


CREATE TABLE roles (
	id UUID NOT NULL, 
	name VARCHAR(50) NOT NULL, 
	slug VARCHAR(50) NOT NULL, 
	description TEXT, 
	level INTEGER NOT NULL, 
	is_system BOOLEAN NOT NULL, 
	is_active BOOLEAN NOT NULL, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	UNIQUE (name)
);


CREATE TABLE shop_items (
	id UUID NOT NULL, 
	name VARCHAR(100) NOT NULL, 
	description TEXT NOT NULL, 
	item_type VARCHAR(50) NOT NULL, 
	price_gems INTEGER NOT NULL, 
	effects JSONB, 
	icon_url VARCHAR(500), 
	is_available BOOLEAN NOT NULL, 
	stock_quantity INTEGER, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id)
);


CREATE TABLE test_exams (
	id UUID NOT NULL, 
	title VARCHAR(255) NOT NULL, 
	description TEXT, 
	level VARCHAR(20) NOT NULL, 
	duration_minutes INTEGER NOT NULL, 
	passing_score INTEGER NOT NULL, 
	question_ids JSONB, 
	is_published BOOLEAN NOT NULL, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id)
);


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


CREATE TABLE question_bank (
	id UUID NOT NULL, 
	prompt TEXT NOT NULL, 
	question_type VARCHAR(50) NOT NULL, 
	options JSONB, 
	answer JSONB, 
	explanation TEXT, 
	difficulty_level VARCHAR(20) NOT NULL, 
	tags JSONB, 
	is_active BOOLEAN NOT NULL, 
	grammar_id UUID, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(grammar_id) REFERENCES grammar_items (id) ON DELETE SET NULL
);


CREATE TABLE role_permissions (
	id UUID NOT NULL, 
	role_id UUID NOT NULL, 
	permission_id UUID NOT NULL, 
	granted_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(role_id) REFERENCES roles (id) ON DELETE CASCADE, 
	FOREIGN KEY(permission_id) REFERENCES permissions (id) ON DELETE CASCADE
);


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
	numeric_level INTEGER NOT NULL, 
	rank VARCHAR(20) NOT NULL, 
	is_onboarding_completed BOOLEAN NOT NULL, 
	role_id UUID, 
	is_active BOOLEAN NOT NULL, 
	is_verified BOOLEAN NOT NULL, 
	provider JSONB NOT NULL, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	last_login TIMESTAMP WITHOUT TIME ZONE, 
	last_login_ip VARCHAR(50), 
	PRIMARY KEY (id), 
	FOREIGN KEY(role_id) REFERENCES roles (id) ON DELETE SET NULL
);


CREATE TABLE activity_feeds (
	id UUID NOT NULL, 
	user_id UUID NOT NULL, 
	activity_type VARCHAR(50) NOT NULL, 
	activity_data JSONB, 
	message TEXT NOT NULL, 
	is_public BOOLEAN NOT NULL, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE
);


CREATE TABLE audit_logs (
	id UUID NOT NULL, 
	user_id UUID, 
	action VARCHAR(50) NOT NULL, 
	resource_type VARCHAR(50) NOT NULL, 
	resource_id VARCHAR(255), 
	details TEXT, 
	ip_address VARCHAR(50), 
	user_agent VARCHAR(500), 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE SET NULL
);


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


CREATE TABLE leaderboard_entries (
	id UUID NOT NULL, 
	user_id UUID NOT NULL, 
	week_start TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	week_end TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	league VARCHAR(20) NOT NULL, 
	xp_earned INTEGER NOT NULL, 
	lessons_completed INTEGER NOT NULL, 
	current_rank INTEGER, 
	is_promoted BOOLEAN NOT NULL, 
	is_demoted BOOLEAN NOT NULL, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE
);


CREATE TABLE level_assessment_tests (
	id UUID NOT NULL, 
	user_id UUID NOT NULL, 
	test_type VARCHAR(20) NOT NULL, 
	assessed_level VARCHAR(5) NOT NULL, 
	overall_score FLOAT NOT NULL, 
	skill_scores JSONB NOT NULL, 
	questions_count INTEGER NOT NULL, 
	correct_count INTEGER NOT NULL, 
	time_taken_seconds INTEGER, 
	started_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	completed_at TIMESTAMP WITHOUT TIME ZONE, 
	level_changed BOOLEAN, 
	previous_level VARCHAR(5), 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE
);


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
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE
);


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


CREATE TABLE user_achievements (
	id UUID NOT NULL, 
	user_id UUID NOT NULL, 
	achievement_id UUID NOT NULL, 
	unlocked_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	progress INTEGER NOT NULL, 
	is_showcased BOOLEAN NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT uq_user_achievement UNIQUE (user_id, achievement_id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE, 
	FOREIGN KEY(achievement_id) REFERENCES achievements (id) ON DELETE CASCADE
);


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


CREATE TABLE user_following (
	id UUID NOT NULL, 
	follower_id UUID NOT NULL, 
	following_id UUID NOT NULL, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT uq_user_following UNIQUE (follower_id, following_id), 
	FOREIGN KEY(follower_id) REFERENCES users (id) ON DELETE CASCADE, 
	FOREIGN KEY(following_id) REFERENCES users (id) ON DELETE CASCADE
);


CREATE TABLE user_inventory (
	id UUID NOT NULL, 
	user_id UUID NOT NULL, 
	shop_item_id UUID NOT NULL, 
	quantity INTEGER NOT NULL, 
	is_active BOOLEAN NOT NULL, 
	activated_at TIMESTAMP WITHOUT TIME ZONE, 
	expires_at TIMESTAMP WITHOUT TIME ZONE, 
	purchased_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE, 
	FOREIGN KEY(shop_item_id) REFERENCES shop_items (id) ON DELETE CASCADE
);


CREATE TABLE user_proficiency_profiles (
	id UUID NOT NULL, 
	user_id UUID NOT NULL, 
	assessed_level VARCHAR(5) NOT NULL, 
	overall_score FLOAT, 
	total_xp INTEGER, 
	total_exercises_completed INTEGER, 
	total_correct_exercises INTEGER, 
	total_lessons_completed INTEGER, 
	last_assessment_at TIMESTAMP WITHOUT TIME ZONE, 
	last_level_change_at TIMESTAMP WITHOUT TIME ZONE, 
	created_at TIMESTAMP WITHOUT TIME ZONE, 
	updated_at TIMESTAMP WITHOUT TIME ZONE, 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE
);


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


CREATE TABLE user_wallets (
	id UUID NOT NULL, 
	user_id UUID NOT NULL, 
	gems INTEGER NOT NULL, 
	total_gems_earned INTEGER NOT NULL, 
	total_gems_spent INTEGER NOT NULL, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE
);


CREATE TABLE vocabulary_decks (
	id UUID NOT NULL, 
	user_id UUID NOT NULL, 
	name VARCHAR(100) NOT NULL, 
	description TEXT, 
	is_public BOOLEAN NOT NULL, 
	color VARCHAR(7) NOT NULL, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE
);


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


CREATE TABLE user_level_history (
	id UUID NOT NULL, 
	profile_id UUID NOT NULL, 
	previous_level VARCHAR(5) NOT NULL, 
	new_level VARCHAR(5) NOT NULL, 
	change_type VARCHAR(20) NOT NULL, 
	overall_score FLOAT, 
	skill_scores_snapshot JSONB, 
	exercises_completed INTEGER, 
	accuracy FLOAT, 
	reason TEXT, 
	triggered_at TIMESTAMP WITHOUT TIME ZONE, 
	PRIMARY KEY (id), 
	FOREIGN KEY(profile_id) REFERENCES user_proficiency_profiles (id) ON DELETE CASCADE
);


CREATE TABLE user_skill_scores (
	id UUID NOT NULL, 
	profile_id UUID NOT NULL, 
	skill skilltype NOT NULL, 
	score FLOAT, 
	confidence FLOAT, 
	estimated_level VARCHAR(5), 
	exercises_completed INTEGER, 
	correct_exercises INTEGER, 
	score_7d_ago FLOAT, 
	score_30d_ago FLOAT, 
	last_updated TIMESTAMP WITHOUT TIME ZONE, 
	PRIMARY KEY (id), 
	FOREIGN KEY(profile_id) REFERENCES user_proficiency_profiles (id) ON DELETE CASCADE
);


CREATE TABLE wallet_transactions (
	id UUID NOT NULL, 
	wallet_id UUID NOT NULL, 
	user_id UUID NOT NULL, 
	transaction_type VARCHAR(50) NOT NULL, 
	amount INTEGER NOT NULL, 
	balance_after INTEGER NOT NULL, 
	source VARCHAR(100), 
	reference_id VARCHAR(255), 
	description TEXT, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(wallet_id) REFERENCES user_wallets (id) ON DELETE CASCADE, 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE
);


CREATE TABLE exercise_attempts (
	id UUID NOT NULL, 
	user_id UUID NOT NULL, 
	exercise_type VARCHAR(50) NOT NULL, 
	skill skilltype NOT NULL, 
	difficulty_level VARCHAR(5) NOT NULL, 
	is_correct BOOLEAN NOT NULL, 
	score FLOAT NOT NULL, 
	time_spent_seconds INTEGER, 
	lesson_id UUID, 
	course_id UUID, 
	attempted_at TIMESTAMP WITHOUT TIME ZONE, 
	attempt_metadata JSONB, 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE, 
	FOREIGN KEY(lesson_id) REFERENCES lessons (id) ON DELETE SET NULL, 
	FOREIGN KEY(course_id) REFERENCES courses (id) ON DELETE SET NULL
);


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


CREATE TABLE vocabulary_items (
	id UUID NOT NULL, 
	word VARCHAR(255) NOT NULL, 
	definition TEXT NOT NULL, 
	translation JSONB, 
	pronunciation VARCHAR(100), 
	audio_url VARCHAR(500), 
	part_of_speech part_of_speech_enum NOT NULL, 
	difficulty_level difficulty_level_enum NOT NULL, 
	course_id UUID, 
	lesson_id UUID, 
	usage_frequency INTEGER NOT NULL, 
	tags JSONB, 
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(course_id) REFERENCES courses (id) ON DELETE SET NULL, 
	FOREIGN KEY(lesson_id) REFERENCES lessons (id) ON DELETE SET NULL
);


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


CREATE TABLE user_vocabulary (
	id UUID NOT NULL, 
	user_id UUID NOT NULL, 
	vocabulary_id UUID NOT NULL, 
	status vocabulary_status_enum NOT NULL, 
	ease_factor FLOAT NOT NULL, 
	interval INTEGER NOT NULL, 
	repetitions INTEGER NOT NULL, 
	next_review_date TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	last_reviewed_at TIMESTAMP WITHOUT TIME ZONE, 
	total_reviews INTEGER NOT NULL, 
	correct_reviews INTEGER NOT NULL, 
	streak INTEGER NOT NULL, 
	longest_streak INTEGER NOT NULL, 
	total_xp_earned INTEGER NOT NULL, 
	notes TEXT, 
	added_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE, 
	FOREIGN KEY(vocabulary_id) REFERENCES vocabulary_items (id) ON DELETE CASCADE
);


CREATE TABLE vocabulary_deck_items (
	id UUID NOT NULL, 
	deck_id UUID NOT NULL, 
	user_vocabulary_id UUID NOT NULL, 
	"order" INTEGER NOT NULL, 
	added_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(deck_id) REFERENCES vocabulary_decks (id) ON DELETE CASCADE, 
	FOREIGN KEY(user_vocabulary_id) REFERENCES user_vocabulary (id) ON DELETE CASCADE
);


CREATE TABLE vocabulary_reviews (
	id UUID NOT NULL, 
	user_vocabulary_id UUID NOT NULL, 
	quality INTEGER NOT NULL, 
	time_spent_ms INTEGER NOT NULL, 
	ease_factor_after FLOAT, 
	interval_after INTEGER, 
	reviewed_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_vocabulary_id) REFERENCES user_vocabulary (id) ON DELETE CASCADE
);

CREATE INDEX ix_api_cache_entries_api_name ON api_cache_entries (api_name);

CREATE INDEX idx_api_cache_api_updated ON api_cache_entries (api_name, updated_at);

CREATE UNIQUE INDEX ix_api_cache_entries_cache_key ON api_cache_entries (cache_key);

CREATE INDEX idx_category_active_order ON course_categories (is_active, order_index);

CREATE INDEX ix_course_categories_is_active ON course_categories (is_active);

CREATE UNIQUE INDEX ix_course_categories_slug ON course_categories (slug);

CREATE INDEX idx_game_words_level_category ON game_words (cefr_level, category);

CREATE INDEX ix_game_words_cefr_level ON game_words (cefr_level);

CREATE INDEX ix_game_words_word ON game_words (word);

CREATE INDEX ix_game_words_category ON game_words (category);

CREATE INDEX ix_grammar_items_level ON grammar_items (level);

CREATE INDEX ix_grammar_items_topic ON grammar_items (topic);

CREATE UNIQUE INDEX ix_media_resources_url ON media_resources (url);

CREATE INDEX ix_permissions_resource ON permissions (resource);

CREATE UNIQUE INDEX ix_permissions_slug ON permissions (slug);

CREATE UNIQUE INDEX idx_permission_resource_action ON permissions (resource, action);

CREATE INDEX ix_refresh_tokens_user_id ON refresh_tokens (user_id);

CREATE UNIQUE INDEX ix_refresh_tokens_token ON refresh_tokens (token);

CREATE UNIQUE INDEX ix_roles_slug ON roles (slug);

CREATE INDEX ix_test_exams_level ON test_exams (level);

CREATE INDEX ix_test_exams_published ON test_exams (is_published);

CREATE UNIQUE INDEX ix_user_devices_device_id ON user_devices (device_id);

CREATE INDEX ix_user_devices_user_id ON user_devices (user_id);

CREATE INDEX ix_courses_level ON courses (level);

CREATE INDEX idx_course_published_lang_level ON courses (is_published, language, level);

CREATE INDEX ix_courses_is_published ON courses (is_published);

CREATE INDEX idx_course_published_created_at ON courses (is_published, created_at);

CREATE INDEX idx_course_level_published ON courses (level, is_published);

CREATE INDEX ix_courses_category_id ON courses (category_id);

CREATE INDEX ix_question_bank_grammar_id ON question_bank (grammar_id);

CREATE INDEX ix_question_bank_level ON question_bank (difficulty_level);

CREATE INDEX ix_question_bank_type ON question_bank (question_type);

CREATE UNIQUE INDEX idx_role_permission_unique ON role_permissions (role_id, permission_id);

CREATE INDEX ix_role_permissions_role_id ON role_permissions (role_id);

CREATE INDEX ix_role_permissions_permission_id ON role_permissions (permission_id);

CREATE UNIQUE INDEX ix_users_username ON users (username);

CREATE INDEX ix_users_id ON users (id);

CREATE UNIQUE INDEX ix_users_email ON users (email);

CREATE INDEX ix_users_role_id ON users (role_id);

CREATE INDEX ix_activity_feeds_user_id ON activity_feeds (user_id);

CREATE INDEX idx_activity_feed_public ON activity_feeds (user_id, is_public, created_at);

CREATE INDEX ix_activity_feeds_created_at ON activity_feeds (created_at);

CREATE INDEX ix_audit_logs_user_id ON audit_logs (user_id);

CREATE INDEX idx_audit_user_action ON audit_logs (user_id, action);

CREATE INDEX ix_audit_logs_created_at ON audit_logs (created_at);

CREATE INDEX ix_audit_logs_resource_type ON audit_logs (resource_type);

CREATE INDEX idx_audit_resource ON audit_logs (resource_type, resource_id);

CREATE INDEX ix_challenge_reward_claims_user_id ON challenge_reward_claims (user_id);

CREATE UNIQUE INDEX idx_challenge_claim_user_date ON challenge_reward_claims (user_id, challenge_id, claim_date);

CREATE INDEX ix_daily_activities_activity_date ON daily_activities (activity_date);

CREATE INDEX ix_daily_activities_user_id ON daily_activities (user_id);

CREATE INDEX idx_daily_activity_week ON daily_activities (user_id, activity_date);

CREATE UNIQUE INDEX idx_daily_activity_user_date ON daily_activities (user_id, activity_date);

CREATE INDEX idx_daily_review_user_date ON daily_review_sessions (user_id, review_date);

CREATE INDEX ix_daily_review_sessions_review_date ON daily_review_sessions (review_date);

CREATE INDEX ix_daily_review_sessions_user_id ON daily_review_sessions (user_id);

CREATE INDEX idx_game_sessions_user_type ON game_sessions (user_id, game_type);

CREATE INDEX ix_game_sessions_user_id ON game_sessions (user_id);

CREATE INDEX idx_game_sessions_created ON game_sessions (created_at);

CREATE INDEX ix_game_sessions_game_type ON game_sessions (game_type);

CREATE INDEX ix_leaderboard_entries_week_start ON leaderboard_entries (week_start);

CREATE INDEX ix_leaderboard_entries_user_id ON leaderboard_entries (user_id);

CREATE INDEX idx_leaderboard_week_league ON leaderboard_entries (week_start, league);

CREATE INDEX ix_level_assessment_tests_user_id ON level_assessment_tests (user_id);

CREATE INDEX idx_notification_user_read ON notifications (user_id, is_read);

CREATE INDEX ix_notifications_user_id ON notifications (user_id);

CREATE UNIQUE INDEX ix_streaks_user_id ON streaks (user_id);

CREATE INDEX ix_units_course_id ON units (course_id);

CREATE INDEX idx_unit_course_order ON units (course_id, order_index);

CREATE UNIQUE INDEX idx_user_achievement_unique ON user_achievements (user_id, achievement_id);

CREATE INDEX ix_user_achievements_achievement_id ON user_achievements (achievement_id);

CREATE INDEX ix_user_achievements_user_id ON user_achievements (user_id);

CREATE INDEX ix_user_course_progress_course_id ON user_course_progress (course_id);

CREATE UNIQUE INDEX idx_user_course_unique ON user_course_progress (user_id, course_id);

CREATE INDEX ix_user_course_progress_user_id ON user_course_progress (user_id);

CREATE UNIQUE INDEX idx_following_unique ON user_following (follower_id, following_id);

CREATE INDEX ix_user_following_following_id ON user_following (following_id);

CREATE INDEX ix_user_following_follower_id ON user_following (follower_id);

CREATE INDEX ix_user_inventory_user_id ON user_inventory (user_id);

CREATE UNIQUE INDEX ix_user_proficiency_profiles_user_id ON user_proficiency_profiles (user_id);

CREATE INDEX ix_user_vocab_knowledge_vocab_id ON user_vocab_knowledge (vocab_id);

CREATE INDEX ix_user_vocab_knowledge_user_id ON user_vocab_knowledge (user_id);

CREATE INDEX idx_vocab_knowledge_user_next_review ON user_vocab_knowledge (user_id, next_review_date);

CREATE INDEX ix_user_vocab_knowledge_next_review_date ON user_vocab_knowledge (next_review_date);

CREATE UNIQUE INDEX ix_user_wallets_user_id ON user_wallets (user_id);

CREATE INDEX ix_vocabulary_decks_user_id ON vocabulary_decks (user_id);

CREATE INDEX ix_vocabulary_decks_user ON vocabulary_decks (user_id);

CREATE INDEX ix_xp_transactions_user_id ON xp_transactions (user_id);

CREATE INDEX idx_xp_transactions_user_created ON xp_transactions (user_id, created_at);

CREATE INDEX ix_xp_transactions_created_at ON xp_transactions (created_at);

CREATE INDEX ix_xp_transactions_source ON xp_transactions (source);

CREATE INDEX idx_xp_transactions_source ON xp_transactions (source);

CREATE INDEX ix_lessons_course_id ON lessons (course_id);

CREATE INDEX idx_lesson_course_order ON lessons (course_id, order_index);

CREATE INDEX ix_lessons_unit_id ON lessons (unit_id);

CREATE INDEX idx_lesson_unit_order ON lessons (unit_id, order_index);

CREATE INDEX ix_user_level_history_profile_id ON user_level_history (profile_id);

CREATE INDEX ix_user_skill_scores_profile_id ON user_skill_scores (profile_id);

CREATE INDEX ix_wallet_transactions_created_at ON wallet_transactions (created_at);

CREATE INDEX ix_wallet_transactions_user_id ON wallet_transactions (user_id);

CREATE INDEX ix_wallet_transactions_wallet_id ON wallet_transactions (wallet_id);

CREATE INDEX ix_exercise_attempts_user_id ON exercise_attempts (user_id);

CREATE INDEX ix_exercise_attempts_attempted_at ON exercise_attempts (attempted_at);

CREATE INDEX ix_lesson_attempts_user_id ON lesson_attempts (user_id);

CREATE INDEX idx_lesson_attempt_user_lesson ON lesson_attempts (user_id, lesson_id);

CREATE INDEX ix_lesson_attempts_lesson_id ON lesson_attempts (lesson_id);

CREATE INDEX ix_lesson_completions_user_id ON lesson_completions (user_id);

CREATE UNIQUE INDEX idx_user_lesson_unique ON lesson_completions (user_id, lesson_id);

CREATE INDEX ix_lesson_completions_lesson_id ON lesson_completions (lesson_id);

CREATE INDEX ix_user_progress_course_id ON user_progress (course_id);

CREATE INDEX ix_user_progress_lesson_id ON user_progress (lesson_id);

CREATE INDEX ix_user_progress_user_id ON user_progress (user_id);

CREATE INDEX ix_vocabulary_items_course_id ON vocabulary_items (course_id);

CREATE INDEX ix_vocabulary_items_word ON vocabulary_items (word);

CREATE INDEX ix_vocabulary_items_part_of_speech ON vocabulary_items (part_of_speech);

CREATE INDEX ix_vocabulary_items_word_lower ON vocabulary_items (word);

CREATE INDEX ix_vocabulary_items_lesson_id ON vocabulary_items (lesson_id);

CREATE INDEX ix_vocabulary_items_difficulty_level ON vocabulary_items (difficulty_level);

CREATE INDEX ix_vocabulary_items_course_difficulty ON vocabulary_items (course_id, difficulty_level);

CREATE INDEX idx_question_attempt_lesson ON question_attempts (lesson_attempt_id, question_id);

CREATE INDEX ix_question_attempts_question_id ON question_attempts (question_id);

CREATE INDEX ix_question_attempts_lesson_attempt_id ON question_attempts (lesson_attempt_id);

CREATE INDEX ix_user_vocabulary_vocabulary_id ON user_vocabulary (vocabulary_id);

CREATE INDEX ix_user_vocabulary_next_review ON user_vocabulary (user_id, next_review_date);

CREATE INDEX ix_user_vocabulary_user_id ON user_vocabulary (user_id);

CREATE INDEX ix_user_vocabulary_next_review_date ON user_vocabulary (next_review_date);

CREATE INDEX ix_user_vocabulary_status ON user_vocabulary (status);

CREATE INDEX ix_user_vocabulary_user_status ON user_vocabulary (user_id, status);

CREATE UNIQUE INDEX ix_user_vocabulary_unique ON user_vocabulary (user_id, vocabulary_id);

CREATE INDEX ix_vocabulary_deck_items_user_vocabulary_id ON vocabulary_deck_items (user_vocabulary_id);

CREATE INDEX ix_vocabulary_deck_items_deck_id ON vocabulary_deck_items (deck_id);

CREATE UNIQUE INDEX ix_vocabulary_deck_items_unique ON vocabulary_deck_items (deck_id, user_vocabulary_id);

CREATE INDEX ix_vocabulary_reviews_user_vocabulary_id ON vocabulary_reviews (user_vocabulary_id);

CREATE INDEX ix_vocabulary_reviews_user_vocab_date ON vocabulary_reviews (user_vocabulary_id, reviewed_at);

CREATE INDEX ix_vocabulary_reviews_reviewed_at ON vocabulary_reviews (reviewed_at);
