"""
Tests for diagnose_node

The diagnose_node is responsible for analyzing user input
and detecting grammar, vocabulary, and fluency issues.
"""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch


class TestDiagnoseNode:
    """Tests for diagnose_node function."""

    @pytest.fixture
    def state_with_input(self, sample_initial_state):
        """State ready for diagnosis."""
        state = sample_initial_state.copy()
        state["kg_seed_concepts"] = ["past_tense"]
        state["kg_expanded_nodes"] = [
            {"concept_id": "past_tense", "title": "Past Tense"}
        ]
        return state

    @pytest.mark.asyncio
    async def test_diagnose_detects_grammar_error(self, state_with_input, mock_model_gateway):
        """Test that diagnose_node detects grammar errors."""
        # Setup mock to return errors
        mock_model_gateway.execute_task.return_value = {
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
        }

        with patch(
            "api.services.trace_cag.nodes_v2.get_gateway",
            return_value=mock_model_gateway,
        ):
            from api.services.trace_cag.nodes_v2 import diagnose_node

            result = await diagnose_node(state_with_input)

            assert "diagnosis_errors" in result
            assert len(result["diagnosis_errors"]) > 0
            assert result["diagnosis_errors"][0]["type"] == "verb_tense"

    @pytest.mark.asyncio
    async def test_diagnose_correct_sentence(self, mock_model_gateway):
        """Test diagnosis of a correct sentence."""
        state = {
            "user_input": "I went to school yesterday.",
            "session_id": "test",
            "learner_profile": {"level": "B1"},
            "kg_expanded_nodes": [],
        }

        mock_model_gateway.execute_task.return_value = {
            "success": True,
            "data": {
                "errors": [],
                "fluency_score": 0.95,
            },
        }

        with patch(
            "api.services.trace_cag.nodes_v2.get_gateway",
            return_value=mock_model_gateway,
        ):
            from api.services.trace_cag.nodes_v2 import diagnose_node

            result = await diagnose_node(state)

            assert "diagnosis_errors" in result
            # Should have no errors or empty list
            errors = result.get("diagnosis_errors", [])
            assert len(errors) == 0 or errors == []

    @pytest.mark.asyncio
    async def test_diagnose_sets_intent(self, state_with_input, mock_model_gateway):
        """Test that diagnose_node sets the intent field."""
        mock_model_gateway.execute_task.return_value = {
            "success": True,
            "data": {"errors": [], "fluency_score": 0.8},
        }

        with patch(
            "api.services.trace_cag.nodes_v2.get_gateway",
            return_value=mock_model_gateway,
        ):
            from api.services.trace_cag.nodes_v2 import diagnose_node

            result = await diagnose_node(state_with_input)

            # Should set intent (correct, practice, question, etc.)
            assert "diagnosis_intent" in result

    @pytest.mark.asyncio
    async def test_diagnose_handles_gateway_failure(self, state_with_input, mock_model_gateway):
        """Test graceful handling of gateway failure."""
        mock_model_gateway.execute_task.return_value = {
            "success": False,
            "error": "Model timeout",
        }

        with patch(
            "api.services.trace_cag.nodes_v2.get_gateway",
            return_value=mock_model_gateway,
        ):
            from api.services.trace_cag.nodes_v2 import diagnose_node

            result = await diagnose_node(state_with_input)

            # Should still return a valid result with defaults
            assert "diagnosis_errors" in result
            assert "diagnosis_confidence" in result

    @pytest.mark.asyncio
    async def test_diagnose_sets_scores(self, state_with_input, mock_model_gateway):
        """Test that diagnose_node sets fluency and grammar scores."""
        mock_model_gateway.execute_task.return_value = {
            "success": True,
            "data": {
                "errors": [],
                "fluency_score": 0.85,
                "grammar_score": 0.9,
            },
        }

        with patch(
            "api.services.trace_cag.nodes_v2.get_gateway",
            return_value=mock_model_gateway,
        ):
            from api.services.trace_cag.nodes_v2 import diagnose_node

            result = await diagnose_node(state_with_input)

            # Should set score fields
            assert "fluency_score" in result or "grammar_score" in result

    @pytest.mark.asyncio
    async def test_diagnose_adds_to_models_used(self, state_with_input, mock_model_gateway):
        """Test that diagnose_node tracks which model was used."""
        mock_model_gateway.execute_task.return_value = {
            "success": True,
            "data": {"errors": []},
        }

        with patch(
            "api.services.trace_cag.nodes_v2.get_gateway",
            return_value=mock_model_gateway,
        ):
            from api.services.trace_cag.nodes_v2 import diagnose_node

            result = await diagnose_node(state_with_input)

            assert "models_used" in result
            assert len(result["models_used"]) > 0
