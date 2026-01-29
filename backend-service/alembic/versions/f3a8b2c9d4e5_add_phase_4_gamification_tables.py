"""Add Phase 4 Gamification and Social Tables

Revision ID: f3a8b2c9d4e5
Revises: ec46e838b61e
Create Date: 2026-01-28

Phase 4 Tables:
- Achievement: Badge/achievement definitions
- UserAchievement: User unlocked achievements
- UserWallet: Virtual currency (gems)
- WalletTransaction: Transaction history
- LeaderboardEntry: Weekly leaderboard
- UserFollowing: Social following relationships
- ActivityFeed: Social activity feed
- ShopItem: Virtual shop items
- UserInventory: User purchased items
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = 'f3a8b2c9d4e5'
down_revision = 'ec46e838b61e'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # === Achievement Tables ===
    
    op.create_table(
        'achievements',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('name', sa.String(100), nullable=False, unique=True),
        sa.Column('description', sa.Text, nullable=False),
        sa.Column('condition_type', sa.String(50), nullable=False),
        sa.Column('condition_value', sa.Integer, nullable=True),
        sa.Column('condition_data', postgresql.JSON, nullable=True),
        sa.Column('badge_icon', sa.String(500), nullable=True),
        sa.Column('badge_color', sa.String(20), nullable=True),
        sa.Column('category', sa.String(50), nullable=True),
        sa.Column('xp_reward', sa.Integer, default=0),
        sa.Column('gems_reward', sa.Integer, default=0),
        sa.Column('rarity', sa.String(20), default='common'),
        sa.Column('is_hidden', sa.Boolean, default=False),
        sa.Column('created_at', sa.DateTime, server_default=sa.func.now()),
    )
    
    op.create_table(
        'user_achievements',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('achievement_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('achievements.id', ondelete='CASCADE'), nullable=False),
        sa.Column('unlocked_at', sa.DateTime, server_default=sa.func.now(), nullable=False),
        sa.Column('progress', sa.Integer, default=0),
        sa.Column('is_showcased', sa.Boolean, default=False),
    )
    op.create_index('idx_user_achievements_user', 'user_achievements', ['user_id'])
    op.create_index('idx_user_achievements_achievement', 'user_achievements', ['achievement_id'])
    op.create_index('idx_user_achievement_unique', 'user_achievements', ['user_id', 'achievement_id'], unique=True)
    
    # === Wallet Tables ===
    
    op.create_table(
        'user_wallets',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, unique=True),
        sa.Column('gems', sa.Integer, default=0),
        sa.Column('total_gems_earned', sa.Integer, default=0),
        sa.Column('total_gems_spent', sa.Integer, default=0),
        sa.Column('created_at', sa.DateTime, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime, server_default=sa.func.now(), onupdate=sa.func.now()),
    )
    op.create_index('idx_user_wallets_user', 'user_wallets', ['user_id'])
    
    op.create_table(
        'wallet_transactions',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('wallet_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('user_wallets.id', ondelete='CASCADE'), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('transaction_type', sa.String(50), nullable=False),
        sa.Column('amount', sa.Integer, nullable=False),
        sa.Column('balance_after', sa.Integer, nullable=False),
        sa.Column('source', sa.String(100), nullable=True),
        sa.Column('reference_id', sa.String(255), nullable=True),
        sa.Column('description', sa.Text, nullable=True),
        sa.Column('created_at', sa.DateTime, server_default=sa.func.now()),
    )
    op.create_index('idx_wallet_transactions_wallet', 'wallet_transactions', ['wallet_id'])
    op.create_index('idx_wallet_transactions_user', 'wallet_transactions', ['user_id'])
    op.create_index('idx_wallet_transactions_created', 'wallet_transactions', ['created_at'])
    
    # === Leaderboard Tables ===
    
    op.create_table(
        'leaderboard_entries',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('week_start', sa.DateTime, nullable=False),
        sa.Column('week_end', sa.DateTime, nullable=False),
        sa.Column('league', sa.String(20), default='bronze'),
        sa.Column('xp_earned', sa.Integer, default=0),
        sa.Column('lessons_completed', sa.Integer, default=0),
        sa.Column('current_rank', sa.Integer, nullable=True),
        sa.Column('is_promoted', sa.Boolean, default=False),
        sa.Column('is_demoted', sa.Boolean, default=False),
        sa.Column('created_at', sa.DateTime, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime, server_default=sa.func.now(), onupdate=sa.func.now()),
    )
    op.create_index('idx_leaderboard_user', 'leaderboard_entries', ['user_id'])
    op.create_index('idx_leaderboard_week_start', 'leaderboard_entries', ['week_start'])
    op.create_index('idx_leaderboard_week_league', 'leaderboard_entries', ['week_start', 'league'])
    
    # === Social Tables ===
    
    op.create_table(
        'user_following',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('follower_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('following_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('created_at', sa.DateTime, server_default=sa.func.now()),
    )
    op.create_index('idx_user_following_follower', 'user_following', ['follower_id'])
    op.create_index('idx_user_following_following', 'user_following', ['following_id'])
    op.create_index('idx_following_unique', 'user_following', ['follower_id', 'following_id'], unique=True)
    
    op.create_table(
        'activity_feeds',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('activity_type', sa.String(50), nullable=False),
        sa.Column('activity_data', postgresql.JSON, nullable=True),
        sa.Column('message', sa.Text, nullable=False),
        sa.Column('is_public', sa.Boolean, default=True),
        sa.Column('created_at', sa.DateTime, server_default=sa.func.now()),
    )
    op.create_index('idx_activity_feed_user', 'activity_feeds', ['user_id'])
    op.create_index('idx_activity_feed_created', 'activity_feeds', ['created_at'])
    op.create_index('idx_activity_feed_public', 'activity_feeds', ['user_id', 'is_public', 'created_at'])
    
    # === Shop Tables ===
    
    op.create_table(
        'shop_items',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('name', sa.String(100), nullable=False),
        sa.Column('description', sa.Text, nullable=False),
        sa.Column('item_type', sa.String(50), nullable=False),
        sa.Column('price_gems', sa.Integer, nullable=False),
        sa.Column('effects', postgresql.JSON, nullable=True),
        sa.Column('icon_url', sa.String(500), nullable=True),
        sa.Column('is_available', sa.Boolean, default=True),
        sa.Column('stock_quantity', sa.Integer, nullable=True),
        sa.Column('created_at', sa.DateTime, server_default=sa.func.now()),
    )
    
    op.create_table(
        'user_inventory',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('shop_item_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('shop_items.id', ondelete='CASCADE'), nullable=False),
        sa.Column('quantity', sa.Integer, default=1),
        sa.Column('is_active', sa.Boolean, default=False),
        sa.Column('activated_at', sa.DateTime, nullable=True),
        sa.Column('expires_at', sa.DateTime, nullable=True),
        sa.Column('purchased_at', sa.DateTime, server_default=sa.func.now()),
    )
    op.create_index('idx_user_inventory_user', 'user_inventory', ['user_id'])


def downgrade() -> None:
    # Drop tables in reverse order due to foreign key constraints
    op.drop_table('user_inventory')
    op.drop_table('shop_items')
    op.drop_table('activity_feeds')
    op.drop_table('user_following')
    op.drop_table('leaderboard_entries')
    op.drop_table('wallet_transactions')
    op.drop_table('user_wallets')
    op.drop_table('user_achievements')
    op.drop_table('achievements')
