"""
Admin Monitoring Route
System metrics, request stats, and service health for the admin dashboard.
Requires admin or super_admin role.
"""

import time
import logging
from datetime import datetime, timezone

import psutil
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_admin
from app.models.user import User

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/admin/monitoring", tags=["Admin Monitoring"])


def _bytes_to_mb(b: float) -> float:
    return round(b / (1024 * 1024), 2)


@router.get("/system")
async def get_system_metrics(
    _: User = Depends(get_current_admin),
):
    """
    Return live system resource metrics via psutil.
    CPU %, memory, disk, load averages, network I/O.
    """
    try:
        cpu = psutil.cpu_percent(interval=0.5)
        mem = psutil.virtual_memory()
        disk = psutil.disk_usage("/")
        load = list(psutil.getloadavg())
        net_io = psutil.net_io_counters()
        disk_io = psutil.disk_io_counters()

        return {
            "cpu_percent": cpu,
            "memory": {
                "total_mb": _bytes_to_mb(mem.total),
                "used_mb": _bytes_to_mb(mem.used),
                "available_mb": _bytes_to_mb(mem.available),
                "percent": mem.percent,
            },
            "disk": {
                "total_gb": round(disk.total / (1024 ** 3), 2),
                "used_gb": round(disk.used / (1024 ** 3), 2),
                "free_gb": round(disk.free / (1024 ** 3), 2),
                "percent": disk.percent,
            },
            "load_avg": {
                "1m": round(load[0], 2),
                "5m": round(load[1], 2),
                "15m": round(load[2], 2),
            },
            "network": {
                "bytes_sent_mb": _bytes_to_mb(net_io.bytes_sent),
                "bytes_recv_mb": _bytes_to_mb(net_io.bytes_recv),
                "packets_sent": net_io.packets_sent,
                "packets_recv": net_io.packets_recv,
            },
            "disk_io": {
                "read_mb": _bytes_to_mb(disk_io.read_bytes) if disk_io else 0,
                "write_mb": _bytes_to_mb(disk_io.write_bytes) if disk_io else 0,
            },
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
    except Exception as e:
        logger.error("System metrics error: %s", e)
        raise HTTPException(status_code=500, detail="Failed to collect system metrics")


@router.get("/services")
async def get_services_health(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_admin),
):
    """
    Check health of all backend dependencies:
    PostgreSQL, Redis, and (optionally) AI service.
    """
    import asyncio
    import httpx
    from app.core.config import settings

    result = {
        "postgres": "unknown",
        "redis": "unknown",
        "ai_service": "unknown",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }

    # PostgreSQL
    try:
        await db.execute(text("SELECT 1"))
        result["postgres"] = "healthy"
    except Exception as e:
        logger.warning("Postgres health check failed: %s", e)
        result["postgres"] = "unhealthy"

    # Redis
    try:
        from app.core.redis import RedisClient
        redis = await RedisClient.get_instance()
        if redis:
            await redis.ping()
            result["redis"] = "healthy"
        else:
            result["redis"] = "not_configured"
    except Exception as e:
        logger.warning("Redis health check failed: %s", e)
        result["redis"] = "unhealthy"

    # AI Service — fire-and-forget with short timeout
    ai_url = getattr(settings, "AI_SERVICE_URL", "http://ai-service:8001")
    try:
        async with httpx.AsyncClient(timeout=3.0) as client:
            resp = await client.get(f"{ai_url}/health")
            result["ai_service"] = "healthy" if resp.status_code < 400 else "unhealthy"
    except Exception:
        result["ai_service"] = "unreachable"

    return result


@router.get("/db-stats")
async def get_db_stats(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_admin),
):
    """Quick row-count stats from main tables for dashboard overview."""
    try:
        counts: dict = {}
        for table in ("users", "courses", "lessons", "vocabulary_items"):
            try:
                row = await db.execute(text(f"SELECT COUNT(*) FROM {table}"))  # noqa: S608
                counts[table] = row.scalar_one()
            except Exception:
                counts[table] = None

        return {"counts": counts, "timestamp": datetime.now(timezone.utc).isoformat()}
    except Exception as e:
        logger.error("DB stats error: %s", e)
        raise HTTPException(status_code=500, detail="Failed to fetch DB stats")


@router.get("/request-stats")
async def get_request_stats(
    _: User = Depends(get_current_admin),
):
    """
    Return request counters from Redis if available.
    Keys written by RateLimitMiddleware (rl:{ip}:minute / rl:{ip}:hour).
    Also returns a simple snapshot of active connections via psutil.
    """
    stats: dict = {
        "active_connections": 0,
        "redis_available": False,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }

    # Network connections count
    try:
        conns = psutil.net_connections(kind="inet")
        stats["active_connections"] = sum(
            1 for c in conns if c.status == "ESTABLISHED"
        )
    except Exception:
        pass

    # Try to aggregate request counters from Redis
    try:
        from app.core.redis import RedisClient
        redis = await RedisClient.get_instance()
        if redis:
            stats["redis_available"] = True
            # Scan for rate-limit minute keys and sum their values
            minute_total = 0
            async for key in redis.scan_iter("rl:*:minute"):
                try:
                    val = await redis.get(key)
                    if val:
                        minute_total += int(val)
                except Exception:
                    pass
            stats["requests_last_minute"] = minute_total
    except Exception as e:
        logger.debug("Redis request stats: %s", e)

    return stats
