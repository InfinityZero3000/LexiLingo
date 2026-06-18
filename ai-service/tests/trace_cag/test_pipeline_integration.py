"""
Integration tests for TraceCAG Pipeline

Tests the full pipeline flow from input to output.
"""

import pytest
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch


@pytest.fixture(autouse=True)
def isolate_pipeline_dependencies(monkeypatch, mock_kg_service):
    """Integration tests must not contact Redis or Kuzu configured locally."""
    from api.core.redis_client import RedisClient
    from api.services import kg_service_v3 as kg_module
    from api.services.trace_cag import graph as graph_module
    from api.services.trace_cag import nodes_v2

    fake_redis = AsyncMock()
    fake_redis.get.return_value = None
    fake_redis.set.return_value = True
    fake_redis.lrange.return_value = []
    fake_redis.rpush.return_value = 1
    fake_redis.expire.return_value = True
    fake_redis.delete.return_value = 0
    fake_redis.ping.return_value = True

    async def get_instance():
        return fake_redis

    async def execute_with_reconnect(operation):
        return await operation(fake_redis)

    monkeypatch.setattr(RedisClient, "get_instance", get_instance)
    monkeypatch.setattr(
        RedisClient,
        "execute_with_reconnect",
        execute_with_reconnect,
    )
    monkeypatch.setattr(
        nodes_v2,
        "_throttled_post_json",
        AsyncMock(return_value=None),
    )
    mock_kg_service.get_seed_concepts_fast.return_value = []
    mock_kg_service.semantic_seed_concepts.return_value = []
    mock_kg_service.expand_best_first = AsyncMock(
        return_value=SimpleNamespace(expanded_nodes=[], paths=[])
    )
    monkeypatch.setattr(kg_module, "get_kg_service", lambda: mock_kg_service)
    kg_module._kg_instance = None
    graph_module._trace_cag_instance = None
    yield
    kg_module._kg_instance = None
    graph_module._trace_cag_instance = None


class TestTraceCAGPipeline:
    """Integration tests for the full TraceCAG pipeline."""

    @pytest.fixture
    def mock_all_services(self, mock_model_gateway, mock_kg_service):
        """Setup all mocks for integration testing."""
        # Mock ModelGateway
        mock_model_gateway.execute_task.side_effect = [
            # First call: diagnose
            {
                "success": True,
                "data": {
                    "errors": [
                        {
                            "type": "verb_tense",
                            "span": "go",
                            "correction": "went",
                            "explanation": "Past tense required",
                        }
                    ],
                    "fluency_score": 0.7,
                },
            },
            # Second call: generate
            {
                "success": True,
                "data": {"text": "Good effort! Use 'went' instead of 'go'."},
            },
        ]

        return {
            "gateway": mock_model_gateway,
            "kg": mock_kg_service,
        }

    @pytest.mark.asyncio
    async def test_full_pipeline_text_input(self, mock_all_services):
        """Test complete pipeline with text input."""
        with patch(
            "api.services.trace_cag.nodes_v2.get_gateway",
            return_value=mock_all_services["gateway"],
        ), patch(
            "api.services.logging_service.get_logging_service",
            return_value=AsyncMock(),
        ), patch(
            "api.services.kg_service_v3.KnowledgeGraphServiceV3",
            return_value=mock_all_services["kg"],
        ):
            from api.services.trace_cag import get_trace_cag

            pipeline = await get_trace_cag()

            result = await pipeline.analyze(
                user_input="I go to school yesterday.",
                session_id="test_session",
                user_id="test_user",
                input_type="text",
            )

            # Verify response structure
            assert "tutor_response" in result
            assert "corrections" in result
            assert "scores" in result
            assert "metadata" in result

    @pytest.mark.asyncio
    async def test_pipeline_response_structure(self, mock_all_services):
        """Test that pipeline returns correct response structure."""
        with patch(
            "api.services.trace_cag.nodes_v2.get_gateway",
            return_value=mock_all_services["gateway"],
        ), patch(
            "api.services.logging_service.get_logging_service",
            return_value=AsyncMock(),
        ):
            from api.services.trace_cag import get_trace_cag

            pipeline = await get_trace_cag()

            result = await pipeline.analyze(
                user_input="Hello",
                session_id="test",
            )

            # Check all expected fields
            expected_fields = [
                "tutor_response",
                "corrections",
                "scores",
                "action",
                "metadata",
            ]
            for field in expected_fields:
                assert field in result, f"Missing field: {field}"

    @pytest.mark.asyncio
    async def test_pipeline_scores_structure(self, mock_all_services):
        """Test that scores have correct structure."""
        with patch(
            "api.services.trace_cag.nodes_v2.get_gateway",
            return_value=mock_all_services["gateway"],
        ), patch(
            "api.services.logging_service.get_logging_service",
            return_value=AsyncMock(),
        ):
            from api.services.trace_cag import get_trace_cag

            pipeline = await get_trace_cag()

            result = await pipeline.analyze(
                user_input="Test input",
                session_id="test",
            )

            scores = result.get("scores", {})
            assert "fluency" in scores
            assert "grammar" in scores
            assert "overall" in scores
            assert "vocabulary_level" in scores

    @pytest.mark.asyncio
    async def test_pipeline_metadata_includes_latency(self, mock_all_services):
        """Test that metadata includes latency information."""
        with patch(
            "api.services.trace_cag.nodes_v2.get_gateway",
            return_value=mock_all_services["gateway"],
        ), patch(
            "api.services.logging_service.get_logging_service",
            return_value=AsyncMock(),
        ):
            from api.services.trace_cag import get_trace_cag

            pipeline = await get_trace_cag()

            result = await pipeline.analyze(
                user_input="Test",
                session_id="test",
            )

            metadata = result.get("metadata", {})
            assert "latency_ms" in metadata
            assert isinstance(metadata["latency_ms"], int)
            assert metadata["latency_ms"] >= 0

    @pytest.mark.asyncio
    async def test_pipeline_handles_error_gracefully(self):
        """Test that pipeline handles errors gracefully."""
        mock_gateway = AsyncMock()
        mock_gateway.execute_task.side_effect = Exception("Unexpected error")

        with patch(
            "api.services.trace_cag.nodes_v2.get_gateway",
            return_value=mock_gateway,
        ):
            from api.services.trace_cag import get_trace_cag

            pipeline = await get_trace_cag()

            result = await pipeline.analyze(
                user_input="Test",
                session_id="test",
            )

            # Should return error response, not crash
            assert "tutor_response" in result or "error" in result

    @pytest.mark.asyncio
    async def test_pipeline_with_learner_profile(self, mock_all_services):
        """Test pipeline with learner profile context."""
        with patch(
            "api.services.trace_cag.nodes_v2.get_gateway",
            return_value=mock_all_services["gateway"],
        ), patch(
            "api.services.logging_service.get_logging_service",
            return_value=AsyncMock(),
        ):
            from api.services.trace_cag import get_trace_cag

            pipeline = await get_trace_cag()

            learner_profile = {
                "user_id": "test_user",
                "level": "A2",
                "common_errors": ["articles", "verb_tense"],
            }

            result = await pipeline.analyze(
                user_input="I go yesterday",
                session_id="test",
                user_id="test_user",
                learner_profile=learner_profile,
            )

            # Should complete without error
            assert "tutor_response" in result
