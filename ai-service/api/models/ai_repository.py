from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List
from uuid import uuid4

from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorDatabase


class AIRepository:
    """MongoDB repository for AI interaction logs and analytics."""

    def __init__(self, db: AsyncIOMotorDatabase):
        self.db = db
        self.collection = db["ai_interactions"]

    async def log_interaction(self, request: Any) -> str:
        payload: Dict[str, Any] = (
            request.model_dump() if hasattr(request, "model_dump") else dict(request)
        )
        payload.setdefault("interaction_id", str(uuid4()))
        payload.setdefault("created_at", datetime.now(timezone.utc))
        await self.collection.insert_one(payload)
        return str(payload["interaction_id"])

    async def get_user_interactions(self, user_id: str, limit: int = 100, skip: int = 0) -> List[Dict[str, Any]]:
        cursor = self.collection.find({"user_id": user_id}).sort("created_at", -1).skip(skip).limit(limit)
        docs = await cursor.to_list(length=limit)
        return [self._normalize_doc(doc) for doc in docs]

    async def get_session_interactions(self, session_id: str) -> List[Dict[str, Any]]:
        cursor = self.collection.find({"session_id": session_id}).sort("created_at", 1)
        docs = await cursor.to_list(length=1000)
        return [self._normalize_doc(doc) for doc in docs]

    async def update_feedback(self, interaction_id: str, feedback: Dict[str, Any]) -> bool:
        result = await self.collection.update_one(
            {"interaction_id": interaction_id},
            {"$set": {"feedback": feedback, "feedback_updated_at": datetime.now(timezone.utc)}},
        )
        if result.matched_count > 0:
            return True

        if ObjectId.is_valid(interaction_id):
            result = await self.collection.update_one(
                {"_id": ObjectId(interaction_id)},
                {"$set": {"feedback": feedback, "feedback_updated_at": datetime.now(timezone.utc)}},
            )
            return result.matched_count > 0

        return False

    async def get_user_error_stats(self, user_id: str, days: int = 30) -> List[Dict[str, Any]]:
        since = datetime.now(timezone.utc) - timedelta(days=max(days, 1))
        pipeline = [
            {"$match": {"user_id": user_id, "created_at": {"$gte": since}}},
            {"$project": {"error_types": {"$ifNull": ["$metadata.error_types", []]}}},
            {"$unwind": "$error_types"},
            {"$group": {"_id": "$error_types", "count": {"$sum": 1}}},
            {"$sort": {"count": -1}},
        ]
        results = await self.collection.aggregate(pipeline).to_list(length=200)
        return [{"error_type": row.get("_id", "unknown"), "count": int(row.get("count", 0))} for row in results]

    @staticmethod
    def _normalize_doc(doc: Dict[str, Any]) -> Dict[str, Any]:
        normalized = dict(doc)
        if "_id" in normalized:
            normalized["_id"] = str(normalized["_id"])
        return normalized
