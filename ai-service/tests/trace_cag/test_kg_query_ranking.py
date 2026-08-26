"""query_concepts ranking — the three failures measured against the prod graph.

Uses a synthetic graph shaped like the real one: a topic whose children repeat
its words, and a long question-style concept that repeats common words.
"""
import pytest

from api.services import kg_service_v3 as kg_module


@pytest.fixture()
def kg():
    service = kg_module.KnowledgeGraphServiceV3.__new__(kg_module.KnowledgeGraphServiceV3)
    service._keyword_index = {}
    service._keyword_idf = {}
    service._title_tokens = {}
    service._concepts_cache = {
        "topic:hotel_check_in": {
            "title": "Hotel Check In",
            "keywords": "hotel check in conversation travel",
            "level": "A2",
        },
        "function:hotel_check_in_asking": {
            "title": "Asking For Information",
            "keywords": "asking for information hotel check in conversation travel",
            "level": "A2",
        },
        "function:hotel_check_in_confirm": {
            "title": "Confirming Details",
            "keywords": "confirming details hotel check in conversation travel",
            "level": "A2",
        },
        "concept:grammar.long_question": {
            # the shape that used to win everything: common words, many times
            "title": "When converting a statement to a question",
            "keywords": " ".join(["the a in of to and is that it for"] * 40),
            "level": "A2",
        },
        "concept:idiom.hit_the_books": {
            "title": "Hit the Books",
            "keywords": "hit the books study hard idiom",
            "level": "B1",
        },
    }
    # Filler so common words are actually common — IDF is a property of the
    # corpus, and a five-node corpus has no common words to discount.
    for n in range(40):
        service._concepts_cache[f"concept:filler.{n}"] = {
            "title": f"Filler {n}",
            "keywords": "the a in of to and is that it for",
            "level": "B1",
        }
    # exercise the real index builder against that cache
    rows = [
        (cid, m["title"], m["keywords"], m["level"])
        for cid, m in service._concepts_cache.items()
    ]

    class _Result:
        def __init__(self, items):
            self._items = list(items)

        def has_next(self):
            return bool(self._items)

        def get_next(self):
            return list(self._items.pop(0))

    class _Conn:
        def execute(self, *_a, **_k):
            return _Result(rows)

    service._conn = _Conn()
    service._build_tfidf_index = lambda: None
    service._build_concept_cache()
    return service


def test_posting_lists_hold_each_concept_once(kg):
    ids = kg._keyword_index["the"]
    assert len(ids) == len(set(ids))


def test_exact_title_query_returns_that_topic_first(kg):
    top = kg.query_concepts("Hotel Check In", learner_level="A2", top_k=8)
    assert top[0]["id"] == "topic:hotel_check_in"


def test_long_common_word_concept_does_not_win_unrelated_query(kg):
    top = kg.query_concepts("what does hit the books mean?", learner_level="B1", top_k=5)
    assert top[0]["id"] == "concept:idiom.hit_the_books"
    assert "concept:grammar.long_question" not in [t["id"] for t in top[:3]]


def test_scores_stay_within_their_documented_range(kg):
    for node in kg.query_concepts("hotel check in travel", learner_level="A2", top_k=8):
        assert 0.0 <= node["score"] <= kg_module._TITLE_MATCH_BOOST
