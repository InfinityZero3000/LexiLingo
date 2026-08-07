"""Celery configuration for background workers."""

from __future__ import annotations

from types import SimpleNamespace

from app.core.config import settings

try:  # pragma: no cover - exercised only when dependency is installed
    from celery import Celery
    from celery.schedules import crontab
except ImportError:  # pragma: no cover - local test env may not install Celery yet
    Celery = None  # type: ignore[assignment]
    crontab = None  # type: ignore[assignment]


if Celery is not None:
    celery_app = Celery(
        "lexilingo",
        broker=settings.effective_celery_broker_url,
        backend=settings.effective_celery_result_backend,
        include=[
            "app.tasks.content_agent",
            "app.tasks.content_prefetch_schedule",
            "app.tasks.ranking_agent",
            "app.tasks.reminders",
            "app.tasks.streak_reminders",
            "app.tasks.word_of_day",
        ],
    )
    celery_app.conf.timezone = "UTC"
    celery_app.conf.enable_utc = True
    celery_app.conf.task_acks_late = True
    celery_app.conf.worker_prefetch_multiplier = 1
    celery_app.conf.beat_schedule = {
        "scan-fsrs-reminders": {
            "task": "app.tasks.reminders.scan_fsrs_reminders",
            "schedule": settings.REMINDER_SCAN_INTERVAL_SECONDS,
        },
        "send-streak-alerts": {
            "task": "app.tasks.streak_reminders.send_streak_alerts",
            "schedule": crontab(hour=20, minute=0),
        },
        "send-word-of-day": {
            "task": "app.tasks.word_of_day.send_word_of_day",
            "schedule": crontab(hour=8, minute=0),
        },
        "cleanup-expired-content-agent-uploads": {
            "task": "app.tasks.content_agent.cleanup_expired_content_agent_uploads",
            "schedule": crontab(hour=3, minute=15),
        },
        "auto-league-reset": {
            "task": "app.tasks.ranking_agent.auto_league_reset",
            "schedule": crontab(hour=0, minute=5, day_of_week=1),
        },
        "prefetch-news": {
            "task": "app.tasks.content_prefetch_schedule.prefetch_news",
            "schedule": crontab(minute=0, hour="*/6"),
        },
        "prefetch-youtube": {
            "task": "app.tasks.content_prefetch_schedule.prefetch_youtube",
            "schedule": crontab(minute=0, hour="*/12"),
        },
        "prefetch-podcasts": {
            "task": "app.tasks.content_prefetch_schedule.prefetch_podcasts",
            "schedule": crontab(minute=0, hour=0),
        },
    }
else:
    class _FallbackCelery:
        """Tiny import-time fallback so tests can run before dependencies install."""

        def __init__(self) -> None:
            self.conf = SimpleNamespace(
                timezone="UTC",
                enable_utc=True,
                task_acks_late=True,
                worker_prefetch_multiplier=1,
                beat_schedule={
                    "scan-fsrs-reminders": {
                        "task": "app.tasks.reminders.scan_fsrs_reminders",
                        "schedule": settings.REMINDER_SCAN_INTERVAL_SECONDS,
                    },
                    "send-streak-alerts": {
                        "task": "app.tasks.streak_reminders.send_streak_alerts",
                        "schedule": 86400,  # fallback: 24h when Celery is not installed
                    },
                    "cleanup-expired-content-agent-uploads": {
                        "task": (
                            "app.tasks.content_agent."
                            "cleanup_expired_content_agent_uploads"
                        ),
                        "schedule": 86400,
                    },
                    "auto-league-reset": {
                        "task": "app.tasks.ranking_agent.auto_league_reset",
                        "schedule": 604800,  # weekly fallback
                    },
                },
            )

        def task(self, *args, **kwargs):
            def decorator(func):
                return func

            return decorator

    celery_app = _FallbackCelery()
