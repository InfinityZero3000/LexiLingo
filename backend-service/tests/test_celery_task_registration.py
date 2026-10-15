"""A scheduled or dispatched task the worker never imported dies silently.

`app.tasks.notification_campaign` defined a task and a route dispatched it with
.delay(), but the module was missing from celery_app's include list, so the
worker rejected every message as an unregistered task.
"""

import importlib
import pathlib
import re

import pytest

from app.core.celery_app import celery_app

TASKS_DIR = pathlib.Path(__file__).resolve().parents[1] / "app" / "tasks"


@pytest.fixture(scope="module")
def registered_tasks() -> set[str]:
    for module in celery_app.conf.include or []:
        importlib.import_module(module)
    return set(celery_app.tasks.keys())


def test_every_module_defining_a_task_is_imported_by_the_worker():
    defined_in = {
        f"app.tasks.{path.stem}"
        for path in TASKS_DIR.glob("*.py")
        if path.stem != "__init__" and "@celery_app.task" in path.read_text()
    }
    missing = defined_in - set(celery_app.conf.include or [])
    assert not missing, (
        f"Task modules missing from celery_app include=[]: {sorted(missing)}. "
        "The worker cannot run a task it never imported."
    )


def test_scheduled_tasks_are_registered(registered_tasks: set[str]):
    scheduled = {
        entry["task"] for entry in (celery_app.conf.beat_schedule or {}).values()
    }
    unknown = scheduled - registered_tasks
    assert not unknown, f"beat_schedule references unregistered tasks: {sorted(unknown)}"


def test_declared_task_names_match_their_module(registered_tasks: set[str]):
    """A task named after the wrong module is unroutable in the same way."""
    mismatched = []
    for path in TASKS_DIR.glob("*.py"):
        for name in re.findall(
            r'@celery_app\.task\(\s*name="([\w.]+)"', path.read_text()
        ):
            if not name.startswith(f"app.tasks.{path.stem}."):
                mismatched.append(f"{path.name}: {name}")
    assert not mismatched, f"Task names not matching their module: {mismatched}"
