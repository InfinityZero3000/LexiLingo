import sys
import os
from pathlib import Path

# Add backend-service to path
backend_path = Path(__file__).parent.parent
sys.path.insert(0, str(backend_path))

import asyncio
from sqlalchemy import select
from app.core.database import engine
from app.models.user import User
from app.crud.gamification import LeaderboardCRUD
from app.services.rank_service import calculate_rank, apply_rank_info_to_user
from sqlalchemy.ext.asyncio import AsyncSession

async def test_api():
    async_session = AsyncSession(engine)
    async with async_session as db:
        # Get user nhthang312@gmail.com
        res = await db.execute(select(User).where(User.email == 'nhthang312@gmail.com'))
        current_user = res.scalar_one_or_none()
        if not current_user:
            print("User nhthang312@gmail.com not found!")
            return
            
        print(f"User in DB: email={current_user.email}, rank={current_user.rank}, level={current_user.level}, numeric_level={current_user.numeric_level}")
        current_user_id = current_user.id
        
        # 1. Simulate get_my_league_status logic
        rank_info = calculate_rank(
            numeric_level=current_user.numeric_level or 1,
            proficiency_level=current_user.level or "A1",
        )
        print(f"Calculated Rank Info: rank={rank_info.rank.value}, score={rank_info.score}, level_score={rank_info.level_score}, proficiency_score={rank_info.proficiency_score}")
        
        apply_rank_info_to_user(current_user, rank_info)
        await db.commit()
        print("Rank applied and DB committed.")

        # Sync weekly entries
        await LeaderboardCRUD.sync_current_week_entries_to_user_rank(db)
        print("Sync complete.")

        entry = await LeaderboardCRUD.get_or_create_entry(db, current_user_id)
        print(f"Leaderboard Entry: id={entry.id}, league={entry.league}, xp_earned={entry.xp_earned}, lessons={entry.lessons_completed}")

        rank = await LeaderboardCRUD.get_user_rank(db, current_user_id)
        print(f"User Rank in leaderboard: {rank}")
        
        # 2. Simulate get_leaderboard logic for league = 'silver'
        print("\n=== GET LEADERBOARD (league=silver) ===")
        entries = await LeaderboardCRUD.get_leaderboard(db, 'silver')
        print(f"Number of entries: {len(entries)}")
        for rank_num, (e, u) in enumerate(entries, 1):
            print(f"Rank {rank_num}: Email={u.email}, League={e.league}, XP={e.xp_earned}, UserRank={u.rank}")

if __name__ == "__main__":
    asyncio.run(test_api())
