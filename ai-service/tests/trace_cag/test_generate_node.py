"""
Tests for generate_node

The generate_node is responsible for generating personalized
tutor responses based on diagnosis results.
"""

import pytest
from unittest.mock import AsyncMock, patch


class TestGenerateNode:
    """Tests for generate_node function."""

    @pytest.fixture(autouse=True)
    def mock_throttled_post(self):
        """Automatically mock _throttled_post_json in nodes_v2 to speed up tests."""
        from unittest.mock import AsyncMock, MagicMock, patch
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {
            "choices": [
                {
                    "message": {
                        "content": "Mocked tutor response text from Groq/Gemini."
                    }
                }
            ],
            "candidates": [
                {
                    "content": {
                        "parts": [{"text": "Mocked tutor response text from Groq/Gemini."}]
                    }
                }
            ],
            "usage": {
                "total_tokens": 100
            }
        }
        with patch("api.services.trace_cag.nodes_v2._throttled_post_json", new_callable=AsyncMock) as mock_post:
            mock_post.return_value = mock_resp
            yield mock_post

    @pytest.fixture(autouse=True)
    def mock_redis(self):
        """Automatically mock RedisClient to avoid connection attempts and timeouts during tests."""
        from unittest.mock import AsyncMock, patch
        mock_redis_client = AsyncMock()
        mock_redis_client.ping = AsyncMock(return_value=True)
        mock_redis_client.set = AsyncMock()
        mock_redis_client.get = AsyncMock(return_value=None)
        
        with patch("api.core.redis_client.RedisClient.get_instance", new=AsyncMock(return_value=mock_redis_client)):
            yield mock_redis_client

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
        from unittest.mock import AsyncMock, MagicMock
        mock_model_gateway.execute_task.return_value = {
            "success": False,
            "error": "Gateway error",
        }

        # Mock HTTP post to fail so fallback chain triggers
        mock_fail = MagicMock()
        mock_fail.status_code = 500

        with patch(
            "api.services.trace_cag.nodes_v2.get_gateway",
            return_value=mock_model_gateway,
        ), patch(
            "api.services.trace_cag.nodes_v2._throttled_post_json",
            new_callable=AsyncMock,
            return_value=mock_fail,
        ):
            from api.services.trace_cag.nodes_v2 import generate_node

            result = await generate_node(state_with_errors)

            # Should still return a response (from template)
            assert "tutor_response" in result
            assert len(result["tutor_response"]) > 0

    @pytest.mark.asyncio
    async def test_provider_outage_returns_safe_uncached_response(self, monkeypatch):
        """Normal chat must never expose or cache raw retrieval evidence."""
        import api.services.trace_cag.generate as generate

        leaked_context = (
            "Concept (concept:benchmark.tell): Tell Concept "
            "(concept:benchmark.lobban): Lobban Concept"
        )
        write_cache = AsyncMock()
        monkeypatch.delenv("GEMINI_API_KEY", raising=False)
        monkeypatch.setenv("TRACECAG_ENABLE_LOCAL_LLAMA_KV", "false")
        monkeypatch.setattr(
            "api.core.groq_key_pool.get_available_groq_key",
            AsyncMock(return_value=None),
        )
        monkeypatch.setattr(generate, "_throttled_post_json", AsyncMock(return_value=None))
        monkeypatch.setattr(generate, "_write_cache_entry", write_cache)

        result = await generate.generate_node(
            {
                "user_input": "Hello",
                "session_id": "session-1",
                "learner_profile": {"level": "B1"},
                "conversation_history": [],
                "diagnosis_errors": [],
                "diagnosis_intent": "correct",
                "retrieved_context": leaked_context,
                "retrieval_trace": [],
                "grammar_score": 0.8,
                "fluency_score": 0.8,
                "vocabulary_level": "B1",
                "cache_policy": "on",
            }
        )

        response = result["tutor_response"]
        assert response == generate.SAFE_TUTOR_FALLBACK
        assert "concept:benchmark" not in response
        assert "Lobban" not in response
        write_cache.assert_not_awaited()

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

    @pytest.mark.asyncio
    async def test_generate_uses_topic_system_prompt(self, monkeypatch):
        from unittest.mock import AsyncMock, MagicMock

        captured_payloads = []
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {
            "choices": [{"message": {"content": "May I see your passport?"}}],
            "usage": {"total_tokens": 50},
        }

        async def fake_post_json(**kwargs):
            captured_payloads.append(kwargs["payload"])
            return mock_resp

        monkeypatch.delenv("GEMINI_API_KEY", raising=False)
        monkeypatch.delenv("GROQ_MODEL", raising=False)
        monkeypatch.setattr(
            "api.core.groq_key_pool.get_available_groq_key",
            AsyncMock(return_value="groq-key"),
        )
        monkeypatch.setattr(
            "api.core.groq_key_pool.record_groq_key_usage",
            AsyncMock(),
        )
        monkeypatch.setattr(
            "api.services.trace_cag.generate._throttled_post_json",
            fake_post_json,
        )

        from api.services.trace_cag.generate import generate_node

        await generate_node(
            {
                "user_input": "I need check in.",
                "session_id": "sess-1",
                "learner_profile": {"level": "A2"},
                "conversation_history": [],
                "diagnosis_errors": [],
                "diagnosis_intent": "correct",
                "fluency_score": 0.9,
                "grammar_score": 0.9,
                "vocabulary_level": "A2",
                "retrieved_context": "",
                "topic_system_prompt": "You are Sarah, an airport check-in agent.",
                "cache_policy": "off",
            }
        )

        system_prompt = captured_payloads[0]["messages"][0]["content"]
        assert captured_payloads[0]["model"] == "qwen/qwen3.6-27b"
        assert captured_payloads[0]["reasoning_effort"] == "none"
        assert "You are Sarah, an airport check-in agent." in system_prompt
        assert "You are Lexi" not in system_prompt


class TestPersonalizationHint:
    """_build_base_system_prompt should fold onboarding goal/interest into
    both the default Lexi prompt and the topic-chat prompt."""

    def test_no_hint_when_profile_has_no_goal_or_interest(self):
        from api.services.trace_cag.generate import _build_base_system_prompt

        prompt = _build_base_system_prompt({"learner_profile": {"level": "B1"}}, "B1", "standard")
        assert "learning for" not in prompt and "into" not in prompt

    def test_hint_appears_in_default_lexi_prompt(self):
        from api.services.trace_cag.generate import _build_base_system_prompt

        prompt = _build_base_system_prompt(
            {"learner_profile": {"level": "B1", "goal": "career", "interest": "technology"}},
            "B1",
            "standard",
        )
        assert "career" in prompt
        assert "technology" in prompt

    def test_hint_appears_in_topic_prompt_branch(self):
        from api.services.trace_cag.generate import _build_base_system_prompt

        prompt = _build_base_system_prompt(
            {
                "topic_system_prompt": "You are Sarah, an airport check-in agent.",
                "learner_profile": {"level": "B1", "goal": "travel"},
            },
            "B1",
            "standard",
        )
        assert "You are Sarah, an airport check-in agent." in prompt
        assert "travel" in prompt

    def test_session_recap_appears_when_returning_after_a_gap(self):
        from api.services.trace_cag.generate import _build_base_system_prompt

        prompt = _build_base_system_prompt(
            {
                "learner_profile": {
                    "level": "B1",
                    "session_recap": "I want to talk about my dream job.",
                }
            },
            "B1",
            "standard",
        )
        assert "I want to talk about my dream job." in prompt

    def test_no_recap_line_on_a_continuing_conversation(self):
        from api.services.trace_cag.generate import _build_base_system_prompt

        prompt = _build_base_system_prompt(
            {"learner_profile": {"level": "B1"}}, "B1", "standard"
        )
        assert "Last time" not in prompt

    def test_no_common_errors_hint_when_cache_is_empty(self):
        from api.services.trace_cag.generate import _build_base_system_prompt

        prompt = _build_base_system_prompt(
            {"learner_profile": {"level": "B1", "common_errors": []}}, "B1", "standard"
        )
        assert "repeatedly struggled" not in prompt

    def test_common_errors_hint_uses_the_most_frequent_recent_type(self):
        from api.services.trace_cag.generate import _build_base_system_prompt

        prompt = _build_base_system_prompt(
            {
                "learner_profile": {
                    "level": "B1",
                    # lpush order (most recent first); "tense_error" is the
                    # most frequent even though it's not first in the list.
                    "common_errors": [
                        "article_error", "tense_error", "tense_error", "tense_error",
                    ],
                }
            },
            "B1",
            "standard",
        )
        assert "repeatedly struggled" in prompt
        assert "tense error" in prompt

    def test_durable_concept_state_hint_takes_priority_over_redis_cache(self):
        from api.services.trace_cag.generate import _build_base_system_prompt

        prompt = _build_base_system_prompt(
            {
                "learner_profile": {
                    "level": "B1",
                    "common_errors": ["article_error"],  # would fire alone
                },
                "diagnosis_root_causes": ["concept:grammar.tenses"],
                "learner_concept_states": {
                    "concept:grammar.tenses": {
                        "error_count": 3,
                        "mastery_probability": 0.3,
                    }
                },
            },
            "B1",
            "standard",
        )
        assert "persistent track record" in prompt
        assert "tenses" in prompt
        # Only one hint fires per turn — Postgres wins, Redis fallback is skipped.
        assert "article error" not in prompt

    def test_durable_concept_state_ignored_when_mastery_is_fine(self):
        from api.services.trace_cag.generate import _build_base_system_prompt

        prompt = _build_base_system_prompt(
            {
                "learner_profile": {"level": "B1"},
                "diagnosis_root_causes": ["concept:grammar.tenses"],
                "learner_concept_states": {
                    "concept:grammar.tenses": {
                        "error_count": 1,
                        "mastery_probability": 0.9,
                    }
                },
            },
            "B1",
            "standard",
        )
        assert "persistent track record" not in prompt

    def test_falls_back_to_redis_cache_when_concept_state_missing(self):
        from api.services.trace_cag.generate import _build_base_system_prompt

        prompt = _build_base_system_prompt(
            {
                "learner_profile": {
                    "level": "B1",
                    "common_errors": ["article_error"],
                },
                "diagnosis_root_causes": ["concept:grammar.tenses"],
                "learner_concept_states": {},  # LEARNER_STATE_MODE=off shape
            },
            "B1",
            "standard",
        )
        assert "persistent track record" not in prompt
        assert "repeatedly struggled" in prompt
        assert "article error" in prompt
