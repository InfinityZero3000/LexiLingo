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
    async def test_diagnose_falls_back_to_groq_when_gateway_raises(self, state_with_input, mock_model_gateway):
        """A raised exception (e.g. unregistered local model) must still try
        Groq before degrading to rules — not skip straight to rule_fallback.

        Regression test for a live-run finding: gateway.execute_task() can
        *raise* ("Model 'qwen' not registered for task 'chat'") instead of
        returning {"success": False}, which used to bypass the Groq-fallback
        branch entirely.
        """
        mock_model_gateway.execute_task.side_effect = RuntimeError(
            "Model 'qwen' not registered for task 'chat'"
        )

        groq_resp = MagicMock()
        groq_resp.status_code = 200
        groq_resp.json.return_value = {
            "choices": [{"message": {"content": '{"errors": [], "intent": "correct", "confidence": 0.9}'}}],
            "usage": {"total_tokens": 42},
        }

        with patch(
            "api.services.trace_cag.nodes_v2.get_gateway",
            return_value=mock_model_gateway,
        ), patch(
            "api.core.groq_key_pool.get_available_groq_key",
            new=AsyncMock(return_value="fake-groq-key"),
        ), patch(
            "api.services.trace_cag.nodes_v2._throttled_post_json",
            new=AsyncMock(return_value=groq_resp),
        ):
            from api.services.trace_cag.nodes_v2 import diagnose_node

            result = await diagnose_node(state_with_input)

            assert result["models_used"][0].startswith("groq/")

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
