"""SCAR-L1 decisions that mirror the current drift-probe failure modes."""

import time

import pytest

from api.services.trace_cag.l1_state_cache import (
    L1Candidate,
    L1Request,
    decide_l1_reuse,
)


def _request(
    *,
    query: str,
    concepts: set[str],
    entities: set[str],
    answer_target: str,
    relations: set[str],
    level: str = "B1",
):
    return L1Request(
        query_norm=query.lower(),
        intent="ask",
        level=level,
        profile_epoch=7,
        session_turn=0,
        concepts=concepts,
        entities=entities,
        answer_target=answer_target,
        relation_hints=relations,
        evidence_hash="",
        policy_version="policy_v1",
        kg_version="kg_v1",
    )


def _candidate(
    *,
    query: str,
    concepts: set[str],
    entities: set[str],
    answer_target: str,
    relations: set[str],
    level: str = "B1",
):
    return L1Candidate(
        cache_key="cached",
        query_norm=query.lower(),
        intent="ask",
        level=level,
        profile_epoch=7,
        session_turn=0,
        concepts=concepts,
        entities=entities,
        answer_target=answer_target,
        relation_hints=relations,
        evidence_hash="",
        policy_version="policy_v1",
        kg_version="kg_v1",
        created_at=time.time(),
        ttl=3600,
    )


@pytest.mark.parametrize(
    ("current", "candidate"),
    [
        (
            _request(
                query="Which film came out first: Blind Shaft or The Mask Of Fu Manchu?",
                concepts={"blind shaft", "fu manchu"},
                entities={"blind shaft", "fu manchu"},
                answer_target="entity",
                relations={"time_order"},
            ),
            _candidate(
                query="Which film came out first, Blind Shaft or The Mask Of Fu Manchu?",
                concepts={"blind shaft", "fu manchu"},
                entities={"blind shaft", "fu manchu"},
                answer_target="entity",
                relations={"time_order"},
            ),
        ),
        (
            _request(
                query="Who was the mother of the person who directed Polish-Russian War?",
                concepts={"polish-russian war", "xawery zulawski"},
                entities={"polish-russian war", "xawery zulawski"},
                answer_target="person",
                relations={"director", "family"},
            ),
            _candidate(
                query="Who is the mother of the director of film Polish-Russian War?",
                concepts={"polish-russian war", "xawery zulawski"},
                entities={"polish-russian war", "xawery zulawski"},
                answer_target="person",
                relations={"director", "family"},
            ),
        ),
        (
            _request(
                query="Which is taller: the Eiffel Tower or Big Ben?",
                concepts={"eiffel tower", "big ben"},
                entities={"eiffel tower", "big ben"},
                answer_target="entity",
                relations={"comparison"},
            ),
            _candidate(
                query="Is the Eiffel Tower taller than Big Ben?",
                concepts={"eiffel tower", "big ben"},
                entities={"eiffel tower", "big ben"},
                answer_target="entity",
                relations={"comparison"},
            ),
        ),
        (
            _request(
                query="Who came first, Mozart or Beethoven?",
                concepts={"mozart", "beethoven"},
                entities={"mozart", "beethoven"},
                answer_target="person",
                relations={"time_order"},
            ),
            _candidate(
                query="Who was born earlier, Mozart or Beethoven?",
                concepts={"mozart", "beethoven"},
                entities={"mozart", "beethoven"},
                answer_target="person",
                relations={"time_order"},
            ),
        ),
        (
            _request(
                query="Where was the writer of the Harry Potter series born?",
                concepts={"harry potter", "j k rowling"},
                entities={"harry potter", "j k rowling"},
                answer_target="place",
                relations={"author", "birth", "location"},
            ),
            _candidate(
                query="Where was the author of Harry Potter born?",
                concepts={"harry potter", "j k rowling"},
                entities={"harry potter", "j k rowling"},
                answer_target="place",
                relations={"author", "birth", "location"},
            ),
        ),
        (
            _request(
                query="Who founded the company that makes the iPhone?",
                concepts={"iphone", "apple inc"},
                entities={"iphone", "apple inc"},
                answer_target="person",
                relations={"founder", "maker"},
            ),
            _candidate(
                query="Who was the founder of the corporation behind the iPhone?",
                concepts={"iphone", "apple inc"},
                entities={"iphone", "apple inc"},
                answer_target="person",
                relations={"founder", "maker"},
            ),
        ),
    ],
)
def test_expected_patch_drift_probes_are_l1_patch(current, candidate):
    decision = decide_l1_reuse(current, candidate)

    assert decision.decision == "patch"
    assert decision.safe_to_reuse is True


@pytest.mark.parametrize(
    ("current", "candidate", "reason"),
    [
        (
            _request(
                query="When was the creator of Facebook born?",
                concepts={"facebook", "mark zuckerberg"},
                entities={"facebook", "mark zuckerberg"},
                answer_target="time",
                relations={"birth"},
            ),
            _candidate(
                query="Where was the creator of Facebook born?",
                concepts={"facebook", "mark zuckerberg"},
                entities={"facebook", "mark zuckerberg"},
                answer_target="place",
                relations={"birth"},
            ),
            "mismatch:answer_target",
        ),
        (
            _request(
                query="Who was the predecessor of the 44th President of the United States?",
                concepts={"barack obama", "44th president"},
                entities={"barack obama", "44th president"},
                answer_target="person",
                relations={"predecessor"},
            ),
            _candidate(
                query="Who is the wife of the 44th President of the United States?",
                concepts={"barack obama", "44th president"},
                entities={"barack obama", "44th president"},
                answer_target="person",
                relations={"family"},
            ),
            "mismatch:relation_path",
        ),
        (
            _request(
                query="In what year did the founder of Microsoft drop out of college?",
                concepts={"microsoft", "bill gates"},
                entities={"microsoft", "bill gates"},
                answer_target="time",
                relations={"education", "time_order"},
            ),
            _candidate(
                query="What university did the founder of Microsoft attend?",
                concepts={"microsoft", "bill gates"},
                entities={"microsoft", "bill gates"},
                answer_target="entity",
                relations={"education"},
            ),
            "mismatch:answer_target",
        ),
        (
            _request(
                query="Who painted the Mona Lisa?",
                concepts={"mona lisa", "leonardo da vinci"},
                entities={"mona lisa", "leonardo da vinci"},
                answer_target="person",
                relations={"creator"},
                level="A2",
            ),
            _candidate(
                query="Who painted the Mona Lisa?",
                concepts={"mona lisa", "leonardo da vinci"},
                entities={"mona lisa", "leonardo da vinci"},
                answer_target="person",
                relations={"creator"},
                level="B1",
            ),
            "mismatch:level",
        ),
    ],
)
def test_unsafe_drift_probes_are_full(current, candidate, reason):
    decision = decide_l1_reuse(current, candidate)

    assert decision.decision == "full"
    assert decision.safe_to_reuse is False
    assert reason in decision.reasons
