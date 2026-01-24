# Database Migration Guide

## 🎯 Overview

This guide explains how to create and apply database migrations for the new models created in Phase 1-4.

## 📋 Prerequisites

```bash
cd backend-service

# Ensure alembic is installed
pip install alembic psycopg2-binary

# Verify alembic is configured
cat alembic.ini
```

## 🔧 Create Migration

### Step 1: Generate Migration Script

```bash
# Auto-generate migration from model changes
alembic revision --autogenerate -m "Add Phase 1-4 models: enhanced users, units, learning attempts, gamification"
```

This will create a new file in `alembic/versions/` like:
```
alembic/versions/xxxx_add_phase_1_4_models.py
```

### Step 2: Review Generated Migration

**IMPORTANT**: Always review the auto-generated migration before applying!

```python
# Example of what you might see:
def upgrade():
    # User tables (Phase 1)
    op.create_table('user_devices', ...)
    op.create_table('refresh_tokens', ...)
    op.add_column('users', sa.Column('provider', ...))
    op.add_column('users', sa.Column('last_login_ip', ...))
    
    # Course tables (Phase 2)
    op.create_table('units', ...)
    op.create_table('media_resources', ...)
    op.add_column('courses', sa.Column('tags', ...))
    op.add_column('lessons', sa.Column('unit_id', ...))
    
    # Learning tables (Phase 3)
    op.create_table('lesson_attempts', ...)
    op.create_table('question_attempts', ...)
    op.create_table('user_vocab_knowledge', ...)
    op.create_table('daily_review_sessions', ...)
    
    # Gamification tables (Phase 4)
    op.create_table('achievements', ...)
    op.create_table('user_achievements', ...)
    op.create_table('user_wallets', ...)
    op.create_table('wallet_transactions', ...)
    op.create_table('leaderboard_entries', ...)
    op.create_table('user_following', ...)
    op.create_table('activity_feeds', ...)
    op.create_table('shop_items', ...)
    op.create_table('user_inventory', ...)
    
    # Create indexes
    op.create_index('idx_course_level_published', ...)
    ...

def downgrade():
    # Reverse operations
    ...
```

### Step 3: Manual Adjustments (if needed)

Check for:
- **Enum types**: Alembic may not detect SQLAlchemy Enum changes
- **Index names**: Ensure they match your model definitions
- **Foreign key constraints**: Verify ON DELETE actions
- **Default values**: JSON fields should default to `{}`

Example manual fixes:
```python
# If alembic missed enum types
from sqlalchemy.dialects.postgresql import ENUM

def upgrade():
    # Create enum type first
    league_enum = ENUM('bronze', 'silver', 'gold', 'platinum', 'diamond',
                       name='league_type', create_type=False)
    league_enum.create(op.get_bind(), checkfirst=True)
    
    # Then create table
    op.create_table('leaderboard_entries', ...)
```

## 🚀 Apply Migration

### Development Environment

```bash
# Check current database version
alembic current

# Show pending migrations
alembic show

# Apply migrations
alembic upgrade head

# Or upgrade one step at a time
alembic upgrade +1

# Verify success
alembic current
```

### Rollback if Needed

```bash
# Rollback one migration
alembic downgrade -1

# Rollback to specific revision
alembic downgrade <revision_id>

# Rollback all migrations
alembic downgrade base
```

## 🔍 Troubleshooting

### Error: "Target database is not up to date"

```bash
# Check alembic version table
psql $DATABASE_URL -c "SELECT * FROM alembic_version;"

# If mismatch, stamp the database with correct version
alembic stamp head
```

### Error: "Table already exists"

If you manually created tables before:
```bash
# Option 1: Drop tables and start fresh
psql $DATABASE_URL -c "DROP TABLE IF EXISTS <table_name> CASCADE;"
alembic upgrade head

# Option 2: Mark migration as applied without running
alembic stamp <revision_id>
```

### Error: JSON column default value

If you get errors with JSON defaults:
```python
# In migration file, change:
sa.Column('tags', JSON, default={})  # ❌ Wrong

# To:
sa.Column('tags', JSON, server_default='{}')  # ✅ Correct
```

## 📊 Verify Migration Success

```bash
# List all tables
psql $DATABASE_URL -c "\dt"

# Check specific table structure
psql $DATABASE_URL -c "\d users"
psql $DATABASE_URL -c "\d lesson_attempts"
psql $DATABASE_URL -c "\d achievements"

# Count indexes
psql $DATABASE_URL -c "SELECT schemaname, tablename, indexname FROM pg_indexes WHERE schemaname = 'public' ORDER BY tablename, indexname;"

# Check foreign keys
psql $DATABASE_URL -c "SELECT
    tc.table_name, 
    kcu.column_name, 
    ccu.table_name AS foreign_table_name
FROM information_schema.table_constraints AS tc 
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
ORDER BY tc.table_name;"
```

## 🎨 Seed Data (After Migration)

```bash
# Run seed script to populate initial data
python scripts/seed_data.py

# Or use the init_db script if available
python scripts/init_db.py
```

## 📝 Migration Checklist

- [ ] Generated migration script
- [ ] Reviewed all table creations
- [ ] Verified foreign key constraints
- [ ] Checked index definitions
- [ ] Tested in development database
- [ ] Verified rollback works
- [ ] Updated database diagram/documentation
- [ ] Committed migration file to git

## 🏗️ Production Deployment

For production, use a more careful approach:

```bash
# 1. Backup database first!
pg_dump $DATABASE_URL > backup_$(date +%Y%m%d_%H%M%S).sql

# 2. Run migration in transaction (auto-rollback on error)
alembic upgrade head

# 3. Verify critical tables exist
psql $DATABASE_URL -c "SELECT COUNT(*) FROM users;"
psql $DATABASE_URL -c "SELECT COUNT(*) FROM courses;"

# 4. If issues, rollback
alembic downgrade -1
# Restore from backup if needed
psql $DATABASE_URL < backup_YYYYMMDD_HHMMSS.sql
```

## 🔗 Related Files

- `alembic.ini` - Alembic configuration
- `alembic/env.py` - Migration environment setup
- `alembic/versions/` - Migration scripts directory
- `app/models/` - SQLAlchemy model definitions
- `app/core/database.py` - Database connection setup

## 📚 References

- [Alembic Documentation](https://alembic.sqlalchemy.org/)
- [SQLAlchemy Migrations](https://docs.sqlalchemy.org/en/20/core/metadata.html)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
