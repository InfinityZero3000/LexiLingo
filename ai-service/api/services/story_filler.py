"""Template filler that scripts/generate_tracecag_topic_corpus.py used to write into stories.

One place for the patterns, shared by the master prompt (which must not feed
them to the model) and scripts/enrich_topic_stories.py (which must not accept
them back from it). Only the distinctive sentences are matched here; generic
ones ("Could you explain the X?") are natural English, so the enrichment gate
rejects those only when they are unchanged from the story's old value.
"""

import re
from typing import Any

PLACEHOLDER_DEFINITION_RE = re.compile(
    r"^\s*A useful expression or concept for handling\b", re.IGNORECASE
)
TEMPLATE_GRAMMAR_EXPLANATION_RE = re.compile(
    r"to keep the .* conversation clear and accurate", re.IGNORECASE
)
TEMPLATE_GRAMMAR_USAGE_RE = re.compile(
    r"^\s*This structure helps the learner ask, explain, or respond during\b", re.IGNORECASE
)
TEMPLATE_VOCAB_EXAMPLE_RE = re.compile(
    r"^\s*Could you help me with the .+ during this .+\?\s*$", re.IGNORECASE
)


def is_placeholder_definition(text: Any) -> bool:
    return not str(text or "").strip() or bool(PLACEHOLDER_DEFINITION_RE.search(str(text)))


def is_template_grammar_explanation(text: Any) -> bool:
    return not str(text or "").strip() or bool(TEMPLATE_GRAMMAR_EXPLANATION_RE.search(str(text)))


def is_template_grammar_usage(text: Any) -> bool:
    return bool(TEMPLATE_GRAMMAR_USAGE_RE.search(str(text or "")))


def is_template_vocab_example(text: Any) -> bool:
    return bool(TEMPLATE_VOCAB_EXAMPLE_RE.match(str(text or "")))
