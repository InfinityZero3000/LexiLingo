"""Service package exports.

Heavy service implementations live in dedicated modules. Keep package import
lightweight so unrelated routes do not load achievement-checking dependencies
unless they explicitly need them.
"""

from importlib import import_module
from typing import Any

__all__ = [
    "AchievementCheckerService",
    "TRIGGER_CONDITIONS",
    "check_achievements_for_user",
]


def __getattr__(name: str) -> Any:
    if name not in __all__:
        raise AttributeError(f"module {__name__!r} has no attribute {name!r}")

    module = import_module("app.services.achievement_checker_service")
    return getattr(module, name)
