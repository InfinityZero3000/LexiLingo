"""AI grading for the two productive IELTS skills.

Writing and Speaking are judged against four band descriptors each, and the
descriptors differ by skill: Writing scores Task Achievement/Response, Speaking
scores Fluency and Coherence and adds Pronunciation. Both share Lexical
Resource and Grammatical Range and Accuracy.

Requests go through `_throttled_post_json`, which injects the qwen reasoning
override for every Groq caller. Do not post to Groq with a raw client here —
`response_format: json_object` rejects a reply that opens with <think>, and the
failure arrives as a 400 that is easy to mistake for a bad prompt.
"""

from __future__ import annotations

import json
import logging
import os
from typing import Any

from api.core.groq_key_pool import get_available_groq_key
from api.services.trace_cag.llm_client import _throttled_post_json

logger = logging.getLogger(__name__)

GRADER_VERSION = "ielts-grader-v1"
_GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"

WRITING_CRITERIA = (
    "task_achievement",
    "coherence_cohesion",
    "lexical_resource",
    "grammatical_range",
)
SPEAKING_CRITERIA = (
    "fluency_coherence",
    "lexical_resource",
    "grammatical_range",
    "pronunciation",
)

_CRITERIA_LABELS = {
    "task_achievement": "Task Achievement / Task Response",
    "coherence_cohesion": "Coherence and Cohesion",
    "lexical_resource": "Lexical Resource",
    "grammatical_range": "Grammatical Range and Accuracy",
    "fluency_coherence": "Fluency and Coherence",
    "pronunciation": "Pronunciation",
}

# Below this, IELTS applies an under-length penalty to Task Achievement.
_MIN_WORDS = {"writing_task_1": 150, "writing_task_2": 250}

_SYSTEM_PROMPT = (
    "You are a certified IELTS examiner. You apply the public band descriptors "
    "strictly and consistently. You never inflate a score to be encouraging: a "
    "band 6 answer receives band 6. Reply with JSON only."
)


def _round_half_band(value: float) -> float:
    return round(value * 2) / 2


def _clamp_band(value: Any) -> float:
    try:
        band = float(value)
    except (TypeError, ValueError):
        return 0.0
    return _round_half_band(max(0.0, min(9.0, band)))


def _build_prompt(
    *,
    skill: str,
    part_key: str,
    task_prompt: str,
    answer_text: str,
    test_type: str,
) -> str:
    criteria = WRITING_CRITERIA if skill == "writing" else SPEAKING_CRITERIA
    criteria_lines = "\n".join(
        f'  "{key}": <band 0-9>,  // {_CRITERIA_LABELS[key]}' for key in criteria
    )
    word_count = len(answer_text.split())

    if skill == "writing":
        minimum = _MIN_WORDS.get(part_key, 150)
        context = (
            f"This is IELTS {test_type.replace('_', ' ').title()} Writing "
            f"{part_key.replace('writing_', '').replace('_', ' ').title()}. "
            f"The required minimum is {minimum} words; the response has "
            f"{word_count}. Apply the under-length penalty to Task Achievement "
            f"if it is short."
        )
        transcript_label = "CANDIDATE RESPONSE"
    else:
        context = (
            f"This is IELTS Speaking "
            f"{part_key.replace('speaking_', '').replace('_', ' ').title()}. "
            "You are given a transcript of the candidate's recorded answer. "
            "Judge Pronunciation only from what the transcript reveals "
            "(hesitation markers, repetition, incomplete words); if it reveals "
            "nothing, score Pronunciation in line with the other criteria "
            "rather than guessing."
        )
        transcript_label = "CANDIDATE TRANSCRIPT"

    return f"""{context}

TASK PROMPT:
{task_prompt}

{transcript_label}:
{answer_text}

Score each of the four band descriptors from 0 to 9 in half bands. Then give
feedback the candidate can act on.

Return exactly this JSON shape and nothing else:
{{
  "criteria": {{
{criteria_lines}
  }},
  "reasoning": "<two sentences justifying the scores against the descriptors>",
  "strengths": ["<what the answer does well>"],
  "improvements": ["<the specific change that would raise the band>"],
  "corrections": [
    {{"original": "<phrase from the answer>", "corrected": "<fixed phrase>", "note": "<why>"}}
  ]
}}"""


async def grade_submission(
    *,
    skill: str,
    part_key: str,
    task_prompt: str,
    answer_text: str,
    test_type: str = "academic",
    timeout_seconds: float = 60.0,
) -> dict[str, Any]:
    """Grade one Writing task or Speaking part. Raises on failure so the caller
    can mark the grading row failed and retry it, rather than storing a band
    nobody computed."""
    skill = (skill or "").strip().lower()
    if skill not in {"writing", "speaking"}:
        raise ValueError(f"Unsupported skill for grading: {skill!r}")

    answer_text = (answer_text or "").strip()
    if not answer_text:
        raise ValueError("Cannot grade an empty submission")

    model = os.getenv("IELTS_GRADER_MODEL") or os.getenv(
        "CONTENT_AGENT_GROQ_MODEL", "qwen/qwen3.6-27b"
    )
    api_key = await get_available_groq_key(estimated_tokens=3000)
    if not api_key:
        raise RuntimeError("No Groq API key available for IELTS grading")

    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": _SYSTEM_PROMPT},
            {
                "role": "user",
                "content": _build_prompt(
                    skill=skill,
                    part_key=part_key,
                    task_prompt=task_prompt,
                    answer_text=answer_text,
                    test_type=test_type,
                ),
            },
        ],
        "response_format": {"type": "json_object"},
        "temperature": 0.2,
        "max_tokens": 1500,
    }

    # _throttled_post_json returns the httpx Response, not parsed JSON,
    # despite the name.
    response = await _throttled_post_json(
        provider="groq",
        url=_GROQ_URL,
        payload=payload,
        headers={"Authorization": f"Bearer {api_key}"},
        timeout=timeout_seconds,
    )
    if response.status_code != 200:
        raise RuntimeError(
            f"Groq returned {response.status_code}: {response.text[:300]}"
        )
    content = response.json()["choices"][0]["message"]["content"]
    parsed = json.loads(content)

    criteria_keys = WRITING_CRITERIA if skill == "writing" else SPEAKING_CRITERIA
    raw_criteria = parsed.get("criteria") or {}
    criteria = {key: _clamp_band(raw_criteria.get(key)) for key in criteria_keys}

    # The reported band is the mean of the four descriptors, rounded to the
    # nearest half band — the same rule the overall score uses.
    band = _round_half_band(sum(criteria.values()) / len(criteria))

    return {
        "criteria": criteria,
        "band": band,
        "feedback": {
            "reasoning": str(parsed.get("reasoning") or "")[:2000],
            "strengths": [str(s)[:500] for s in (parsed.get("strengths") or [])[:5]],
            "improvements": [
                str(s)[:500] for s in (parsed.get("improvements") or [])[:5]
            ],
            "corrections": [
                {
                    "original": str(c.get("original") or "")[:300],
                    "corrected": str(c.get("corrected") or "")[:300],
                    "note": str(c.get("note") or "")[:300],
                }
                for c in (parsed.get("corrections") or [])[:10]
                if isinstance(c, dict)
            ],
        },
        "word_count": len(answer_text.split()),
        "grader_version": GRADER_VERSION,
        "model": model,
    }
