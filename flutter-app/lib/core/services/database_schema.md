# LexiLingo Database Schema

## Database Information
- **Database Name**: `lexilingo.db`
- **Version**: 3
- **Engine**: SQLite
- **Location**: Local device storage

## Tables Overview

### Core Tables (User Management)
1. **users** - User accounts and statistics
2. **settings** - User preferences and app settings
3. **daily_goals** - Daily learning targets and achievements
4. **streaks** - Daily activity tracking
5. **course_enrollments** - User course enrollment tracking

### Learning Content Tables
6. **courses** - Available courses
7. **lessons** - Course lessons
8. **vocabulary** - Personal vocabulary list
9. **user_progress** - Learning progress tracking

### Feature Tables
10. **chat_history** - AI tutor conversations

---

## Detailed Schema

### 1. users
Stores user account information and overall statistics.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | TEXT | PRIMARY KEY | Firebase UID or unique user identifier |
| name | TEXT | NOT NULL | User's display name |
| email | TEXT | NOT NULL | User's email address |
| avatarUrl | TEXT | NULL | URL to user's profile picture |
| joinDate | TEXT | NOT NULL | ISO 8601 timestamp of account creation |
| lastLoginDate | TEXT | NULL | ISO 8601 timestamp of last login |
| totalXP | INTEGER | DEFAULT 0 | Total experience points earned |
| currentStreak | INTEGER | DEFAULT 0 | Current consecutive days streak |
| longestStreak | INTEGER | DEFAULT 0 | Longest streak ever achieved |
| totalLessonsCompleted | INTEGER | DEFAULT 0 | Total number of lessons completed |
| totalWordsLearned | INTEGER | DEFAULT 0 | Total vocabulary words learned |

---

### 2. settings
Stores user preferences and app configuration.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Unique settings identifier |
| userId | TEXT | NOT NULL, FOREIGN KEY | Reference to users.id |
| notificationEnabled | BOOLEAN | DEFAULT 1 | Whether notifications are enabled |
| notificationTime | TEXT | DEFAULT "09:00" | Daily reminder time (HH:MM format) |
| theme | TEXT | DEFAULT "system" | Theme preference (light, dark, system) |
| language | TEXT | DEFAULT "en" | App language code |
| soundEnabled | BOOLEAN | DEFAULT 1 | Whether sound effects are enabled |
| dailyGoalXP | INTEGER | DEFAULT 50 | Daily XP target |

**Foreign Keys**:
- `userId` → `users(id)` ON DELETE CASCADE

---

### 3. daily_goals
Tracks daily learning goals and achievements.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Unique goal record identifier |
| userId | TEXT | NOT NULL, FOREIGN KEY | Reference to users.id |
| date | TEXT | NOT NULL | Date in "YYYY-MM-DD" format |
| targetXP | INTEGER | DEFAULT 50 | Target XP for the day |
| earnedXP | INTEGER | DEFAULT 0 | XP earned so far |
| lessonsCompleted | INTEGER | DEFAULT 0 | Lessons completed today |
| wordsLearned | INTEGER | DEFAULT 0 | New words learned today |
| minutesSpent | INTEGER | DEFAULT 0 | Minutes spent learning today |

**Foreign Keys**:
- `userId` → `users(id)` ON DELETE CASCADE

**Unique Constraints**:
- `(userId, date)` - One goal record per user per day

---

### 4. streaks
Tracks daily activity streaks for gamification.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Unique streak record identifier |
| userId | TEXT | NOT NULL, FOREIGN KEY | Reference to users.id |
| date | TEXT | NOT NULL | Date in "YYYY-MM-DD" format |
| completed | BOOLEAN | DEFAULT 0 | Whether goal was completed (0 or 1) |

**Foreign Keys**:
- `userId` → `users(id)` ON DELETE CASCADE

**Unique Constraints**:
- `(userId, date)` - One streak record per user per day

---

### 5. course_enrollments
Tracks which users are enrolled in which courses.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Unique enrollment identifier |
| userId | TEXT | NOT NULL, FOREIGN KEY | Reference to users.id |
| courseId | INTEGER | NOT NULL, FOREIGN KEY | Reference to courses.id |
| enrolledAt | TEXT | NOT NULL | ISO 8601 timestamp of enrollment |
| lastAccessedAt | TEXT | NULL | ISO 8601 timestamp of last access |
| completedAt | TEXT | NULL | ISO 8601 timestamp of completion |
| currentProgress | REAL | DEFAULT 0.0 | Progress percentage (0.0 - 1.0) |

**Foreign Keys**:
- `userId` → `users(id)` ON DELETE CASCADE
- `courseId` → `courses(id)` ON DELETE CASCADE

**Unique Constraints**:
- `(userId, courseId)` - User can only enroll once per course

---

### 6. courses
Stores course information for language learning.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Unique course identifier |
| title | TEXT | NOT NULL | Course title |
| description | TEXT | NOT NULL | Course description |
| level | TEXT | NOT NULL | Difficulty level (A1, A2, B1, B2, C1, C2) |
| category | TEXT | NULL | Course category (e.g., "Language Basics", "Speaking", "Business") |
| imageUrl | TEXT | NULL | URL to course cover image |
| duration | TEXT | NULL | Estimated duration (e.g., "4 weeks", "12 hours") |
| lessonsCount | INTEGER | DEFAULT 0 | Number of lessons in the course |
| isFeatured | BOOLEAN | DEFAULT 0 | Whether course is featured (0 or 1) |
| rating | REAL | DEFAULT 0.0 | Course rating (0.0 - 5.0) |
| enrolledCount | INTEGER | DEFAULT 0 | Number of users enrolled |
| createdAt | TEXT | NULL | ISO 8601 timestamp of creation |
| updatedAt | TEXT | NULL | ISO 8601 timestamp of last update |

**Note**: User enrollment and progress are now tracked in `course_enrollments` and `user_progress` tables

**Sample Data**:
```sql
-- English for Beginners (Featured)
-- Conversational English (Featured)
-- Business English
-- IELTS Preparation (Featured)
-- English Grammar Mastery
-- Travel English
```

---

### 7. lessons
Stores individual lessons within courses.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Unique lesson identifier |
| courseId | INTEGER | NOT NULL, FOREIGN KEY | Reference to courses.id |
| title | TEXT | NOT NULL | Lesson title |
| description | TEXT | NULL | Lesson description |
| orderIndex | INTEGER | DEFAULT 0 | Display order within course |
| duration | TEXT | NULL | Estimated duration (e.g., "15 min") |
| status | TEXT | DEFAULT "locked" | Lesson status (locked, open, completed) |
| contentUrl | TEXT | NULL | URL to lesson content/media |

**Foreign Keys**:
- `courseId` → `courses(id)` ON DELETE CASCADE

---

### 8. vocabulary
Stores vocabulary words for learning and review.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Unique vocabulary identifier |
| userId | TEXT | FOREIGN KEY | Reference to users.id |
| word | TEXT | NOT NULL | The vocabulary word |
| definition | TEXT | NOT NULL | Word definition |
| example | TEXT | NULL | Example sentence using the word |
| phonetic | TEXT | NULL | Phonetic pronunciation (e.g., "/həˈloʊ/") |
| audioUrl | TEXT | NULL | URL to pronunciation audio |
| partOfSpeech | TEXT | NULL | Part of speech (noun, verb, adjective, etc.) |
| difficulty | TEXT | NULL | Difficulty level (beginner, intermediate, advanced) |
| isLearned | BOOLEAN | NOT NULL | Whether user has learned the word (0 or 1) |
| isFavorite | BOOLEAN | DEFAULT 0 | Whether word is marked as favorite (0 or 1) |
| createdAt | TEXT | NULL | ISO 8601 timestamp of creation |
| lastReviewedAt | TEXT | NULL | ISO 8601 timestamp of last review |
Foreign Keys**:
- `userId` → `users(id)` ON DELETE CASCADE

**
**Sample Data**:
```sql
-- hello: A greeting used to acknowledge someone's presence
-- beautiful: Pleasing the senses or mind aesthetically
```9. user_progress
Tracks user progress through courses and lessons.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Unique progress record identifier |
| userId | TEXT | FOREIGN KEY | Reference to users.id |
| sessionId | TEXT | NULL | Chat session grouping identifier |
| message | TEXT | NOT NULL | The message content |
| isUser | BOOLEAN | NOT NULL | Whether message is from user (1) or AI (0) |
| timestamp | TEXT | NOT NULL | ISO 8601 timestamp of message |

**Foreign Keys**:
- `userId` → `user
### 4. chat_history
Stores AI tutor chat conversation history.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Unique message identifier |
| message | TEXT | NOT NULL | The message content |
| isUser | BOOLEAN | NOT NULL | Whether message is from user (1) or AI (0) |
| timestamp | TEXT | NOT NULL | ISO 8601 timestamp of message |

---

### 5. user_progress
Tracks user progress through courses and lessons.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Unique progress record identifier |
| courseId | INTEGER | NOT NULL, FOREIGN KEY | Reference to courses.id |
users (1) ──< (N) settings
   │
   ├──< (N) daily_goals
   │
   ├──< (N) streaks
   │
   ├──< (N) course_enrollments >─┐
   │                              │
   ├──< (N) vocabulary            │
   │                              │
   ├──< (N) chat_history          │
   │     User by Firebase UID
```sql
SELECT * FROM users WHERE id = ?;
```

#### Get User Settings
```sql
SELECT * User's Vocabulary
```sql
SELECT * FROM vocabulary 
WHERE userId = ?
ORDER BY cre
SELECT * FROM daily_goals 
WHERE userId = ? AND date = DATE('now');
```Chat History by Session
```sql
SELECT * FROM chat_history 
WHERE userId = ? AND sessionId = ?
ORDER BY timestamp ASC;
```

#### Get Course Progress for User
```sql
SELECT c.*,
       ce.currentProgress,
       COUNT(DISTINCT up.lessonId) as completedLessons
FROM courses c
INNER JOIN course_enrollments ce ON c.id = ce.courseId
LEFT JOIN user_progress up ON c.id = up.courseId 
  AND up.userId = ce.userId 
  AND up.completedAt IS NOT NULL
WHERE ce.userId = ? AND c.id = ?
GROUP BY c.id;
```

#### Update Daily Goal
```sql
INSERT INTO daily_goals (userId, date, earnedXP, lessonsCompleted, wordsLearned)
VALUES (?, DATE('now'), ?, ?, ?)
ON CONFLICT(userId, date) 
DO UPDATE SET 
  earnedXP = earnedXP + ?,
  lessonsCompleted = lessonsCompleted + ?,
  wordsLearned = wordsLearned + ?urse_enrollments e ON c.id = e.courseId
WHERE e.userId = ?
ORDER BY e.lastAccessedAt DESC;
```

### Version 2 → Version 3 (Current)
**Major structural changes for multi-user support:**

**New Tables:**
- `users` - User accounts and statistics
- `settings` - User preferences
- `daDates**: All date-only values are stored as TEXT in "YYYY-MM-DD" format
4. **Cascading Deletes**: Deleting a user automatically deletes all their related data (enrollments, progress, vocabulary, etc.)
5. **Progress Values**: All progress values are stored as REAL between 0.0 and 1.0 (representing 0% to 100%)
6. **Platform Support**: Database is only available on mobile (iOS/Android) and desktop. Web uses mock data.
7. **User ID**: User IDs are TEXT to support Firebase UID format (e.g., "firebase:abc123...")

**Modified Tables:**
- `courses`: Removed `progress` and `isEnrolled` (moved to `course_enrollments`)
- `lessons`: Changed `isCompleted BOOLEAN` to `status TEXT` (locked/open/completed)
- `vocabulary`: Added `userId` foreign key
- `chat_history`: Added `userId` and `sessionId` fields
- `user_progress`: Added `userId` field and unique constraint

#### Get                          │ and enrollments
- `VocabLocalDataSource`: Data access for vocabulary
- `ChatLocalDataSource`: Data access for chat history
- `UserLocalDataSource`: Data access for users and settings (to be implemented)
- `ProgressLocalDataSource`: Data access for daily goals and streaks (to be implemented)
courses (1) ──< (N) lessons       │ │
   Data Access Layer

### Required DataSources to Implement:

1. **UserLocalDataSource** (High Priority)
   - `createUser(user)` - Create new user
   - `getUser(userId)` - Get user by ID
   - `updateUser(user)` - Update user info
   - `updateUserStats(userId, xp, streak, etc.)` - Update statistics

2. **SettingsLocalDataSource** (High Priority)
   - `getSettings(userId)` - Get user settings
   - `updateSettings(settings)` - Update preferences
   - `setNotificationTime(userId, time)` - Set reminder time

3. **DailyGoalLocalDataSource** (High Priority)
   - `getTodayGoal(userId)` - Get today's goal
   - `updateDailyProgress(userId, xp, lessons, words)` - Update progress
   - `getGoalHistory(userId, days)` - Get past goals

4. **StreakLocalDataSource** (High Priority)
   - `getCurrentStreak(userId)` - Calculate current streak
   - `markDayComplete(userId, date)` - Mark day as completed
   - `getStreakHistory(userId, days)` - Get streak history

5. **EnrollmentLocalDataSource** (High Priority)
   - `enrollInCourse(userId, courseId)` - Enroll user in course
   - `getEnrolledCourses(userId)` - Get user's courses
   - `updateCourseProgress(userId, courseId, progress)` - Update progress

## Future Enhancements

Planned additions:
- [ ] `achievements` table for gamification badges
- [ ] `quiz_sessions` table for assessment tracking
- [ ] `scheduled_notifications` table for local reminders
- [ ] Full-text search indices for vocabulary and courses
- [ ] Offline sync mechanism with Firebase/Firestore
- [ ] `learning_analytics` table for detailed usage statistics

## Relationships

```
courses (1) ──< (N) lessons
   │
   └──< (N) user_progress >──┐
                              │
lessons (1) ──< (N) user_progress
```

## Database Operations

### Common Queries

#### Get All Featured Courses
```sql
SELECT * FROM courses 
WHERE isFeatured = 1 
ORDER BY rating DESC;
```

#### Get Enrolled Courses
```sql
SELECT * FROM courses 
WHERE isEnrolled = 1 
ORDER BY updatedAt DESC;
```

#### Get Unlearned Vocabulary
```sql
SELECT * FROM vocabulary 
WHERE isLearned = 0 
ORDER BY createdAt DESC;
```

#### Get Chat History
```sql
SELECT * FROM chat_history 
ORDER BY timestamp ASC;
```

#### Get Course with Progress
```sql
SELECT c.*, 
       COALESCE(AVG(up.progress), 0) as overall_progress
FROM courses c
LEFT JOIN user_progress up ON c.id = up.courseId
WHERE c.id = ?
GROUP BY c.id;
```

---

## Database Migrations

### Version 1 → Version 2
Added columns to `courses` table:
- `imageUrl TEXT`
- `category TEXT`
- `duration TEXT`
- `lessonsCount INTEGER DEFAULT 0`

---

## Notes

1. **Boolean Values**: SQLite doesn't have a native BOOLEAN type, so we use INTEGER (0 = false, 1 = true)
2. **Timestamps**: All timestamps are stored as TEXT in ISO 8601 format (e.g., "2026-01-13T10:30:00.000Z")
3. **Cascading Deletes**: Deleting a course automatically deletes all related lessons and progress records
4. **Progress Values**: All progress values are stored as REAL between 0.0 and 1.0 (representing 0% to 100%)
5. **Platform Support**: Database is only available on mobile (iOS/Android) and desktop. Web uses mock data.

---

## Implementation

See: `/lib/core/services/database_helper.dart` for the complete implementation.

**Key Classes**:
- `DatabaseHelper`: Singleton class managing database connection and operations
- `CourseLocalDataSource`: Data access for courses
- `VocabLocalDataSource`: Data access for vocabulary
- `ChatLocalDataSource`: Data access for chat history

---

## Future Enhancements

Planned additions:
- [ ] `achievements` table for gamification
- [ ] `user_preferences` table for app settings
- [ ] `quiz_results` table for assessment tracking
- [ ] `notifications` table for scheduled reminders
- [ ] Full-text search indices for vocabulary and courses
- [ ] Offline sync mechanism with Firebase
