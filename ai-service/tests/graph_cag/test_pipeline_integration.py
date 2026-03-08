"""
Integration tests for GraphCAG Pipeline

Tests the full pipeline flow from input to output.
"""

import pytest
from unittest.mock import AsyncMock, patch, MagicMock


class TestGraphCAGPipeline:
    """Integration tests for the full GraphCAG pipeline."""

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
            "api.services.graph_cag.nodes_v2.get_gateway",
            return_value=mock_all_services["gateway"],
        ), patch(
            "api.services.logging_service.get_logging_service",
            return_value=AsyncMock(),
        ), patch(
            "api.services.kg_service_v3.KnowledgeGraphServiceV3",
            return_value=mock_all_services["kg"],
        ):
            from api.services.graph_cag import get_graph_cag

            pipeline = await get_graph_cag()
            
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
            "api.services.graph_cag.nodes_v2.get_gateway",
            return_value=mock_all_services["gateway"],
        ), patch(
            "api.services.logging_service.get_logging_service",
            return_value=AsyncMock(),
        ):
            from api.services.graph_cag import get_graph_cag

            pipeline = await get_graph_cag()
            
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
            "api.services.graph_cag.nodes_v2.get_gateway",
            return_value=mock_all_services["gateway"],
        ), patch(
            "api.services.logging_service.get_logging_service",
            return_value=AsyncMock(),
        ):
            from api.services.graph_cag import get_graph_cag

            pipeline = await get_graph_cag()
            
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
            "api.services.graph_cag.nodes_v2.get_gateway",
            return_value=mock_all_services["gateway"],
        ), patch(
            "api.services.logging_service.get_logging_service",
            return_value=AsyncMock(),
        ):
            from api.services.graph_cag import get_graph_cag

            pipeline = await get_graph_cag()
            
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
            "api.services.graph_cag.nodes_v2.get_gateway",
            return_value=mock_gateway,
        ):
            from api.services.graph_cag import get_graph_cag

            pipeline = await get_graph_cag()
            
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
            "api.services.graph_cag.nodes_v2.get_gateway",
            return_value=mock_all_services["gateway"],
        ), patch(
            "api.services.logging_service.get_logging_service",
            return_value=AsyncMock(),
        ):
            from api.services.graph_cag import get_graph_cag

            pipeline = await get_graph_cag()
            
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
