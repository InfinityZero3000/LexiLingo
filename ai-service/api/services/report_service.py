"""
Report Service

Generates progress reports and learning analytics for users.
"""

import logging
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field

from api.core.database import get_database

logger = logging.getLogger(__name__)


# ============================================================
# MODELS
# ============================================================


class WeeklySummary(BaseModel):
    """Weekly learning summary."""
    week_start: datetime
    week_end: datetime
    total_interactions: int = 0
    total_practice_time_min: int = 0
    grammar_accuracy_avg: float = 0.0
    vocabulary_learned: int = 0
    concepts_reviewed: int = 0
    error_improvement: float = 0.0  # Positive = improved


class ProgressReport(BaseModel):
    """Complete progress report for a user."""
    user_id: str
    generated_at: datetime = Field(default_factory=datetime.utcnow)
    period_days: int = 30
    
    # Level progress
    current_level: str = "B1"
    level_progress: float = 0.0
    days_at_level: int = 0
    
    # Activity metrics
    total_interactions: int = 0
    active_days: int = 0
    avg_interactions_per_day: float = 0.0
    streak_days: int = 0
    
    # Performance metrics
    grammar_accuracy: float = 0.0
    fluency_score_avg: float = 0.0
    improvement_rate: float = 0.0
    
    # Learning focus
    top_strengths: List[str] = Field(default_factory=list)
    areas_to_focus: List[str] = Field(default_factory=list)
    common_error_types: List[Dict[str, Any]] = Field(default_factory=list)
    
    # Recommendations
    recommended_topics: List[str] = Field(default_factory=list)
    suggested_goals: List[str] = Field(default_factory=list)
    
    # Weekly breakdown
    weekly_summaries: List[WeeklySummary] = Field(default_factory=list)


# ============================================================
# REPORT SERVICE
# ============================================================


class ReportService:
    """
    Report generation service.

    Generates comprehensive learning progress reports.
    """

    COLLECTION = "user_reports"

    def __init__(self):
        self._db = None

    async def _get_db(self):
        """Get database connection."""
        if self._db is None:
            self._db = await get_database()
        return self._db

    async def generate_report(
        self,
        user_id: str,
        days: int = 30,
        save: bool = True,
    ) -> ProgressReport:
        """
        Generate complete progress report for user.

        Args:
            user_id: User to generate report for
            days: Number of days to analyze
            save: Whether to save report to DB

        Returns:
            Complete progress report
        """
        try:
            db = await self._get_db()
            cutoff = datetime.utcnow() - timedelta(days=days)

            # Get interaction data
            interactions = await self._get_interactions(user_id, cutoff)
            
            # Calculate metrics
            activity = self._calculate_activity_metrics(interactions, days)
            performance = self._calculate_performance_metrics(interactions)
            errors = await self._analyze_errors(interactions)
            weekly = self._calculate_weekly_summaries(interactions, days)

            # Get assessment
            assessment = await self._get_latest_assessment(user_id)

            # Generate recommendations
            recommendations = self._generate_recommendations(
                performance, errors, assessment
            )

            report = ProgressReport(
                user_id=user_id,
                period_days=days,
                current_level=assessment.get("current_level", "B1"),
                level_progress=assessment.get("progress_to_next", 0.0),
                
                total_interactions=activity["total"],
                active_days=activity["active_days"],
                avg_interactions_per_day=activity["avg_per_day"],
                streak_days=activity.get("streak", 0),
                
                grammar_accuracy=performance["grammar_accuracy"],
                fluency_score_avg=performance["fluency_avg"],
                improvement_rate=performance.get("improvement_rate", 0.0),
                
                top_strengths=assessment.get("strengths", []),
                areas_to_focus=assessment.get("areas_to_improve", []),
                common_error_types=errors[:5],
                
                recommended_topics=recommendations["topics"],
                suggested_goals=recommendations["goals"],
                weekly_summaries=weekly,
            )

            if save:
                await self._save_report(report)

            return report

        except Exception as e:
            logger.error(f"Failed to generate report: {e}")
            return ProgressReport(user_id=user_id, period_days=days)

    async def _get_interactions(
        self,
        user_id: str,
        cutoff: datetime,
    ) -> List[Dict[str, Any]]:
        """Get user interactions from database."""
        try:
            db = await self._get_db()
            cursor = db["ai_interactions"].find({
                "user_id": user_id,
                "timestamp": {"$gte": cutoff},
            }).sort("timestamp", 1)

            return [doc async for doc in cursor]

        except Exception:
            return []

    def _calculate_activity_metrics(
        self,
        interactions: List[Dict[str, Any]],
        days: int,
    ) -> Dict[str, Any]:
        """Calculate activity metrics from interactions."""
        if not interactions:
            return {"total": 0, "active_days": 0, "avg_per_day": 0.0}

        # Count unique active days
        active_dates = set()
        for i in interactions:
            ts = i.get("timestamp")
            if ts:
                active_dates.add(ts.date())

        total = len(interactions)
        active_days = len(active_dates)
        avg = total / days if days > 0 else 0

        return {
            "total": total,
            "active_days": active_days,
            "avg_per_day": round(avg, 2),
        }

    def _calculate_performance_metrics(
        self,
        interactions: List[Dict[str, Any]],
    ) -> Dict[str, Any]:
        """Calculate performance metrics."""
        if not interactions:
            return {"grammar_accuracy": 0.0, "fluency_avg": 0.0}

        total_errors = 0
        total_fluency = 0.0
        count = 0

        for i in interactions:
            analysis = i.get("analysis", {})
            errors = analysis.get("grammar_errors", [])
            fluency = analysis.get("fluency_score", 0.5)

            total_errors += len(errors)
            total_fluency += fluency
            count += 1

        if count == 0:
            return {"grammar_accuracy": 0.0, "fluency_avg": 0.0}

        error_rate = total_errors / count
        grammar_accuracy = max(0.0, 1.0 - error_rate / 3.0)  # Normalize

        return {
            "grammar_accuracy": round(grammar_accuracy, 3),
            "fluency_avg": round(total_fluency / count, 3),
        }

    async def _analyze_errors(
        self,
        interactions: List[Dict[str, Any]],
    ) -> List[Dict[str, Any]]:
        """Analyze common error types."""
        error_counts: Dict[str, int] = {}

        for i in interactions:
            analysis = i.get("analysis", {})
            for error in analysis.get("grammar_errors", []):
                error_type = error.get("type", "unknown")
                error_counts[error_type] = error_counts.get(error_type, 0) + 1

        # Sort by count
        sorted_errors = sorted(
            error_counts.items(),
            key=lambda x: x[1],
            reverse=True,
        )

        return [
            {"type": e[0], "count": e[1]}
            for e in sorted_errors
        ]

    def _calculate_weekly_summaries(
        self,
        interactions: List[Dict[str, Any]],
        days: int,
    ) -> List[WeeklySummary]:
        """Calculate weekly breakdowns."""
        if not interactions:
            return []

        weeks: Dict[int, List[Dict[str, Any]]] = {}
        now = datetime.utcnow()

        for i in interactions:
            ts = i.get("timestamp", now)
            week_num = (now - ts).days // 7
            if week_num not in weeks:
                weeks[week_num] = []
            weeks[week_num].append(i)

        summaries = []
        for week_num in sorted(weeks.keys()):
            week_interactions = weeks[week_num]
            week_end = now - timedelta(days=week_num * 7)
            week_start = week_end - timedelta(days=7)

            perf = self._calculate_performance_metrics(week_interactions)

            summaries.append(WeeklySummary(
                week_start=week_start,
                week_end=week_end,
                total_interactions=len(week_interactions),
                grammar_accuracy_avg=perf["grammar_accuracy"],
            ))

        return summaries[:4]  # Last 4 weeks

    async def _get_latest_assessment(self, user_id: str) -> Dict[str, Any]:
        """Get latest assessment for user."""
        try:
            from api.services.assessment_service import get_assessment_service
            service = get_assessment_service()
            assessment = await service.assess_user(user_id)
            return {
                "current_level": assessment.current_level.value,
                "progress_to_next": assessment.progress_to_next,
                "strengths": assessment.strengths,
                "areas_to_improve": assessment.areas_to_improve,
            }
        except Exception:
            return {}

    def _generate_recommendations(
        self,
        performance: Dict[str, Any],
        errors: List[Dict[str, Any]],
        assessment: Dict[str, Any],
    ) -> Dict[str, List[str]]:
        """Generate personalized recommendations."""
        topics = []
        goals = []

        # Based on errors
        if errors:
            top_error = errors[0]["type"]
            topics.append(f"Focus on {top_error} exercises")

        # Based on performance
        if performance.get("grammar_accuracy", 0) < 0.6:
            goals.append("Improve grammar accuracy to 80%")
            topics.append("Grammar fundamentals review")

        if performance.get("fluency_avg", 0) < 0.5:
            goals.append("Practice speaking fluency")
            topics.append("Conversation practice")

        # Default recommendations
        if not topics:
            topics = ["Vocabulary expansion", "Reading comprehension"]
        if not goals:
            goals = ["Complete 10 practice sessions", "Review past mistakes"]

        return {"topics": topics[:3], "goals": goals[:3]}

    async def _save_report(self, report: ProgressReport):
        """Save report to database."""
        try:
            db = await self._get_db()
            await db[self.COLLECTION].insert_one(report.model_dump())
        except Exception as e:
            logger.warning(f"Failed to save report: {e}")

    async def get_saved_reports(
        self,
        user_id: str,
        limit: int = 5,
    ) -> List[ProgressReport]:
        """Get previously saved reports."""
        try:
            db = await self._get_db()
            cursor = (
                db[self.COLLECTION]
                .find({"user_id": user_id})
                .sort("generated_at", -1)
                .limit(limit)
            )

            reports = []
            async for doc in cursor:
                doc.pop("_id", None)
                reports.append(ProgressReport(**doc))

            return reports

        except Exception:
            return []


# ============================================================
# SINGLETON
# ============================================================

_service: Optional[ReportService] = None


def get_report_service() -> ReportService:
    """Get ReportService singleton."""
    global _service
    if _service is None:
        _service = ReportService()
    return _service
