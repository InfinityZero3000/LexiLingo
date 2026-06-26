import pytest

from service.tracecag_service import TraceCAGRequest
from service.tracecag_service.adapters.lexilingo import LexiLingoTraceCAGAnalyzer


class FakePipeline:
    def __init__(self):
        self.calls = []

    async def analyze(self, **kwargs):
        self.calls.append(kwargs)
        return {
            "tutor_response": "from existing pipeline",
            "metadata": {"path": "slow", "cache_hit": False},
        }


@pytest.mark.asyncio
async def test_lexilingo_adapter_maps_request_to_existing_pipeline_kwargs():
    pipeline = FakePipeline()
    adapter = LexiLingoTraceCAGAnalyzer(pipeline_factory=lambda: pipeline)
    request = TraceCAGRequest(
        user_input="I go yesterday",
        session_id="s1",
        user_id="u1",
        input_type="text",
        learner_profile={"level": "A2"},
        conversation_history=[{"role": "user", "content": "hello"}],
        kg_seed_concepts=["concept:grammar.past_time_markers"],
        return_raw_state=True,
    )

    response = await adapter.analyze(request)

    assert response.tutor_response == "from existing pipeline"
    assert len(pipeline.calls) == 1
    call = pipeline.calls[0]
    assert call["user_input"] == "I go yesterday"
    assert call["session_id"] == "s1"
    assert call["user_id"] == "u1"
    assert call["learner_profile"] == {"level": "A2"}
    assert call["conversation_history"] == [{"role": "user", "content": "hello"}]
    assert call["kg_seed_concepts"] == ["concept:grammar.past_time_markers"]
    assert call["return_raw_state"] is True
    assert response.raw_state["tutor_response"] == "from existing pipeline"


@pytest.mark.asyncio
async def test_lexilingo_adapter_accepts_async_pipeline_factory():
    pipeline = FakePipeline()

    async def factory():
        return pipeline

    adapter = LexiLingoTraceCAGAnalyzer(pipeline_factory=factory)

    response = await adapter.analyze(
        TraceCAGRequest(user_input="hello", session_id="s1")
    )

    assert response.tutor_response == "from existing pipeline"
    assert len(pipeline.calls) == 1

