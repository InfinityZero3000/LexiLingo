import sys
import os
from pathlib import Path

# Add backend-service to path
backend_path = Path(__file__).parent.parent
sys.path.insert(0, str(backend_path))

import asyncio
from sqlalchemy import text
from app.core.database import engine

from app.services.rank_service import calculate_rank, apply_rank_info_to_user
from app.services.level_service import calculate_numeric_level

async def check_users():
    async with engine.begin() as conn:
        # Check nhthang312@gmail.com
        res_nh = await conn.execute(text('''
            SELECT id, email, username, display_name, level, numeric_level, rank, rank_score, total_xp
            FROM users WHERE email = 'nhthang312@gmail.com'
        '''))
        user_nh = res_nh.fetchone()
        if user_nh:
            print(f"\n[INFO] nhthang312@gmail.com: Level={user_nh.level}, NumLvl={user_nh.numeric_level}, Rank={user_nh.rank}, Score={user_nh.rank_score}, XP={user_nh.total_xp}")
        
        # Check thefirestar312@gmail.com
        res_fs = await conn.execute(text('''
            SELECT id, email, username, display_name, level, numeric_level, rank, rank_score, total_xp
            FROM users WHERE email = 'thefirestar312@gmail.com'
        '''))
        user_fs = res_fs.fetchone()
        if user_fs:
            print(f"[INFO] thefirestar312@gmail.com (BEFORE): Level={user_fs.level}, NumLvl={user_fs.numeric_level}, Rank={user_fs.rank}, Score={user_fs.rank_score}, XP={user_fs.total_xp}")
            
            # Let's update thefirestar312@gmail.com to be MAX rank and max gems
            print("[ACTION] Syncing thefirestar312@gmail.com to MAX stats (C2, level 100, 200000 XP, 9999 gems)...")
            
            # Recalculate rank details
            new_level = "C2"
            new_numeric_level = 100
            new_xp = 200000
            
            # Calculate rank
            rank_info = calculate_rank(new_numeric_level, new_level)
            
            # Update user in DB
            await conn.execute(text(f'''
                UPDATE users
                SET level = :level,
                    numeric_level = :numeric_level,
                    total_xp = :total_xp,
                    rank = :rank,
                    rank_score = :rank_score,
                    rank_level_score = :rank_level_score,
                    rank_proficiency_score = :rank_proficiency_score
                WHERE id = :user_id
            '''), {
                "level": new_level,
                "numeric_level": new_numeric_level,
                "total_xp": new_xp,
                "rank": rank_info.rank.value,
                "rank_score": rank_info.score,
                "rank_level_score": rank_info.level_score,
                "rank_proficiency_score": rank_info.proficiency_score,
                "user_id": user_fs.id
            })
            
            # Clear and create UserProficiencyProfile
            await conn.execute(text("DELETE FROM user_proficiency_profiles WHERE user_id = :user_id"), {"user_id": user_fs.id})
            await conn.execute(text('''
                INSERT INTO user_proficiency_profiles (id, user_id, assessed_level, total_xp, overall_score, total_exercises_completed, total_correct_exercises, created_at, updated_at)
                VALUES (:id, :user_id, :assessed_level, :total_xp, :overall_score, :total_exercises_completed, :total_correct_exercises, NOW(), NOW())
            '''), {
                "id": os.urandom(16).hex(),
                "user_id": user_fs.id,
                "assessed_level": new_level,
                "total_xp": new_xp,
                "overall_score": 100.0,
                "total_exercises_completed": 1000,
                "total_correct_exercises": 1000
            })
            
            # Clear / Create / Update Wallet for 9999 gems
            await conn.execute(text("DELETE FROM user_wallets WHERE user_id = :user_id"), {"user_id": user_fs.id})
            await conn.execute(text('''
                INSERT INTO user_wallets (id, user_id, gems, total_gems_earned, total_gems_spent, created_at, updated_at)
                VALUES (:id, :user_id, 9999, 9999, 0, NOW(), NOW())
            '''), {
                "id": os.urandom(16).hex(),
                "user_id": user_fs.id
            })
            
            # Verify update
            res_verify = await conn.execute(text('''
                SELECT level, numeric_level, rank, rank_score, total_xp
                FROM users WHERE id = :user_id
            '''), {"user_id": user_fs.id})
            updated = res_verify.fetchone()
            
            res_wallet = await conn.execute(text('''
                SELECT gems FROM user_wallets WHERE user_id = :user_id
            '''), {"user_id": user_fs.id})
            wallet_gems = res_wallet.scalar()
            
            print(f"[INFO] thefirestar312@gmail.com (AFTER): Level={updated.level}, NumLvl={updated.numeric_level}, Rank={updated.rank}, Score={updated.rank_score}, XP={updated.total_xp}, Gems={wallet_gems}")
        else:
            print("No user with email 'thefirestar312@gmail.com' found in database.")

if __name__ == "__main__":
    asyncio.run(check_users())
