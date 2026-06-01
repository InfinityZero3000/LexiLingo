"""
Tests for generate_node

The generate_node is responsible for generating personalized
tutor responses based on diagnosis results.
"""

import pytest
from unittest.mock import AsyncMock, patch


class TestGenerateNode:
    """Tests for generate_node function."""

    @pytest.fixture
    def state_with_errors(self, sample_state_after_diagnosis):
        """State with grammar errors for testing."""
        return sample_state_after_diagnosis

    @pytest.fixture
    def state_no_errors(self, sample_initial_state):
        """State with no grammar errors."""
        state = sample_initial_state.copy()
        state["diagnosis_errors"] = []
        state["diagnosis_intent"] = "correct"
        state["diagnosis_confidence"] = 0.95
        state["fluency_score"] = 0.9
        state["grammar_score"] = 0.95
        return state

    @pytest.mark.asyncio
    async def test_generate_response_with_errors(self, state_with_errors, mock_model_gateway):
        """Test generating response when errors are present."""
        mock_model_gateway.execute_task.return_value = {
            "success": True,
            "data": {
                "text": "Good effort! Just a small correction: 'go' should be 'went'. Keep practicing!",
            },
        }

        with patch(
            "api.services.trace_cag.nodes_v2.get_gateway",
            return_value=mock_model_gateway,
        ):
            from api.services.trace_cag.nodes_v2 import generate_node

            result = await generate_node(state_with_errors)

            assert "tutor_response" in result
            assert len(result["tutor_response"]) > 0

    @pytest.mark.asyncio
    async def test_generate_praise_for_correct(self, state_no_errors, mock_model_gateway):
        """Test generating praise when no errors."""
        mock_model_gateway.execute_task.return_value = {
            "success": True,
            "data": {"text": "Excellent work! Your sentence is perfect."},
        }

        with patch(
            "api.services.trace_cag.nodes_v2.get_gateway",
            return_value=mock_model_gateway,
        ):
            from api.services.trace_cag.nodes_v2 import generate_node

            result = await generate_node(state_no_errors)

            assert "tutor_response" in result
            # Strategy should be praise for correct input
            assert result.get("strategy") == "praise"

    @pytest.mark.asyncio
    async def test_generate_sets_strategy(self, state_with_errors, mock_model_gateway):
        """Test that generate_node sets the strategy field."""
        mock_model_gateway.execute_task.return_value = {
            "success": True,
            "data": {"text": "Let me help you with that."},
        }

        with patch(
            "api.services.trace_cag.nodes_v2.get_gateway",
            return_value=mock_model_gateway,
        ):
            from api.services.trace_cag.nodes_v2 import generate_node

            result = await generate_node(state_with_errors)

            assert "strategy" in result
            assert result["strategy"] in ["praise", "feedback", "scaffold"]

    @pytest.mark.asyncio
    async def test_generate_sets_next_action(self, state_with_errors, mock_model_gateway):
        """Test that generate_node sets next_action field."""
        mock_model_gateway.execute_task.return_value = {
            "success": True,
            "data": {"text": "Response"},
        }

        with patch(
            "api.services.trace_cag.nodes_v2.get_gateway",
            return_value=mock_model_gateway,
        ):
            from api.services.trace_cag.nodes_v2 import generate_node

            result = await generate_node(state_with_errors)

            assert "next_action" in result
            assert result["next_action"] in ["continue", "hint", "correct"]

    @pytest.mark.asyncio
    async def test_generate_calculates_overall_score(self, state_with_errors, mock_model_gateway):
        """Test that overall score is calculated."""
        mock_model_gateway.execute_task.return_value = {
            "success": True,
            "data": {"text": "Response"},
        }

        with patch(
            "api.services.trace_cag.nodes_v2.get_gateway",
            return_value=mock_model_gateway,
        ):
            from api.services.trace_cag.nodes_v2 import generate_node

            result = await generate_node(state_with_errors)

            assert "overall_score" in result
            assert 0.0 <= result["overall_score"] <= 1.0

    @pytest.mark.asyncio
    async def test_generate_fallback_on_failure(self, state_with_errors, mock_model_gateway):
        """Test template fallback when gateway fails."""
        mock_model_gateway.execute_task.return_value = {
            "success": False,
            "error": "Gateway error",
        }

        with patch(
            "api.services.trace_cag.nodes_v2.get_gateway",
            return_value=mock_model_gateway,
        ):
            from api.services.trace_cag.nodes_v2 import generate_node

            result = await generate_node(state_with_errors)

            # Should still return a response (from template)
            assert "tutor_response" in result
            assert len(result["tutor_response"]) > 0

    @pytest.mark.asyncio
    async def test_generate_tracks_models_used(self, state_with_errors, mock_model_gateway):
        """Test that models_used is tracked."""
        mock_model_gateway.execute_task.return_value = {
            "success": True,
            "data": {"text": "Response"},
        }

        with patch(
            "api.services.trace_cag.nodes_v2.get_gateway",
            return_value=mock_model_gateway,
        ):
            from api.services.trace_cag.nodes_v2 import generate_node

            result = await generate_node(state_with_errors)

            assert "models_used" in result
