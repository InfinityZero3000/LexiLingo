#!/usr/bin/env python3
"""Test level-up by updating XP directly."""

import asyncio
from sqlalchemy import text

async def test_level_up():
    from app.core.database import engine
    
    user_id = '189cab24-ce44-447c-9d5e-49cdd666dcc1'
    
    async with engine.begin() as conn:
        # Update XP to 150 to trigger level 2
        await conn.execute(text(
            "UPDATE users SET total_xp = 150 WHERE id = :uid"
        ), {'uid': user_id})
        
        # Verify
        result = await conn.execute(text(
            "SELECT total_xp, numeric_level, rank FROM users WHERE id = :uid"
        ), {'uid': user_id})
        row = result.fetchone()
        print(f"Updated user:")
        print(f"  Total XP: {row[0]}")
        print(f"  Numeric Level: {row[1]}")
        print(f"  Rank: {row[2]}")

if __name__ == "__main__":
    import os
    import sys
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    asyncio.run(test_level_up())
