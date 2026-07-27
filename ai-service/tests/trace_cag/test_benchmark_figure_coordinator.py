import importlib.util
from pathlib import Path
import threading
import sys


PATH = Path(__file__).parents[2] / "model-development" / "scripts" / "benchmark_figure_coordinator.py"
SPEC = importlib.util.spec_from_file_location("benchmark_figure_coordinator", PATH)
module = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = module
SPEC.loader.exec_module(module)
FigureRenderCoordinator = module.FigureRenderCoordinator


class Clock:
    now = 0.0
    def __call__(self): return self.now


def test_five_samples_render_immediately_and_zero_delta_does_not():
    calls = []
    c = FigureRenderCoordinator(calls.append)
    assert c.submit_progress("r", "s", 5, 10, {"v": 1})
    assert c.wait_idle()
    assert [x.completed_count for x in calls] == [5]
    assert not c.submit_progress("r", "s", 5, 10, {"v": 2})
    c.process_due(); assert c.wait_idle()
    assert len(calls) == 1
    c.close()


def test_first_four_render_at_exactly_thirty_seconds_and_timer_resets():
    clock, calls = Clock(), []
    c = FigureRenderCoordinator(calls.append, clock=clock)
    c.submit_progress("r", "s", 4, 20, {})
    clock.now = 29.999; assert c.process_due() == 0
    clock.now = 30.0; assert c.process_due() == 1
    assert c.wait_idle()
    c.submit_progress("r", "s", 6, 20, {})
    clock.now = 59.9; assert c.process_due() == 0
    clock.now = 60.0; assert c.process_due() == 1
    assert c.wait_idle()
    assert [x.completed_count for x in calls] == [4, 6]
    c.close()


def test_state_is_independent_per_run_and_stage():
    calls = []
    c = FigureRenderCoordinator(calls.append)
    c.submit_progress("r1", "full", 4, 9, {})
    c.submit_progress("r2", "full", 5, 9, {})
    c.submit_progress("r1", "pre", 5, 9, {})
    assert c.wait_idle()
    assert {(x.run_id, x.stage_id) for x in calls} == {("r2", "full"), ("r1", "pre")}
    c.close()


def test_rendering_is_global_serial_and_arrivals_coalesce_once():
    entered, release = threading.Event(), threading.Event()
    calls, active, maximum = [], 0, 0
    lock = threading.Lock()
    def render(request):
        nonlocal active, maximum
        with lock: active += 1; maximum = max(maximum, active)
        calls.append(request)
        if len(calls) == 1: entered.set(); release.wait(2)
        with lock: active -= 1
    c = FigureRenderCoordinator(render)
    c.submit_progress("r", "s", 5, 20, {"n": 5})
    assert entered.wait(1)
    c.submit_progress("r", "s", 6, 20, {"n": 6})
    c.submit_progress("r", "s", 7, 20, {"n": 7})
    c.submit_progress("other", "s", 5, 20, {})
    release.set(); assert c.wait_idle()
    assert maximum == 1
    assert [(x.run_id, x.completed_count) for x in calls].count(("r", 7)) == 1
    assert len(calls) == 3
    c.close()


def test_terminal_cancels_timer_and_preserves_by_not_calling_renderer():
    clock, calls = Clock(), []
    c = FigureRenderCoordinator(calls.append, clock=clock)
    c.submit_progress("r", "s", 4, 10, {})
    c.mark_terminal("r", "s")
    clock.now = 31; assert c.process_due() == 0
    assert c.wait_idle() and calls == []
    c.close()


def test_final_and_discovery_request_publication_formats():
    calls = []
    c = FigureRenderCoordinator(calls.append)
    assert c.discover_completed([{"run_id":"r", "stage_id":"s", "completed_count":8,
                                  "target_count":8}]) == 1
    assert c.wait_idle()
    assert calls[0].final and calls[0].formats == ("png", "svg", "pdf")
    c.close()


def test_renderer_failure_is_reported_and_worker_survives():
    errors, calls = [], []
    def render(request):
        calls.append(request)
        if len(calls) == 1: raise OSError("disk full")
    c = FigureRenderCoordinator(render, on_error=lambda request, exc: errors.append(str(exc)))
    c.submit_progress("r1", "s", 5, 5, {})
    c.submit_progress("r2", "s", 5, 5, {})
    assert c.wait_idle()
    assert errors == ["disk full"] and len(calls) == 2
    c.close()


def test_failed_render_remains_due_for_later_retry():
    clock, calls = Clock(), []
    def render(request):
        calls.append(request)
        if len(calls) == 1: raise OSError("temporary")
    c = FigureRenderCoordinator(render, clock=clock)
    c.submit_progress("r", "s", 5, 10, {})
    assert c.wait_idle()
    clock.now = 29.9; assert c.process_due() == 0
    clock.now = 30.0; assert c.process_due() == 1
    assert c.wait_idle() and len(calls) == 2
    c.close()
