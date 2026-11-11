"""What of a KG concept reaches the prompt, and whether the concept a learner names is found at all.

Each case is a defect measured on 2026-11-11: on 150 CEFR questions whose target word is in the graph, the lexical stage had it
in the top 8 for 39, the packer kept it for 5, and none of the 14 prompts inspected carried a CEFR level.
"""
import pytest

from api.services import kg_service_v3 as kg_module
from api.services.trace_cag.kg_utils import _pack_kg_nodes_for_context, kg_concept_text, level_is_reliable
from api.services.trace_cag.retrieve import _merge_duplicate_evidence


def test_a_level_reaches_the_prompt_only_where_the_source_labelled_it():
    assert "(CEFR A1)" in kg_concept_text("about", "prep", "A1", "concept:vocab.word.about")
    assert "(CEFR B2)" in kg_concept_text("Future Perfect", "", "B2", "concept:grammar.future_perfect")
    # file 09 forum answers have no level in the source; the loader stored "B1" for them, which would be a made-up claim
    assert "CEFR" not in kg_concept_text("How do I?", "x", "B1", "concept:grammar.how-do-i-a87a422d3f")
    assert "CEFR" not in kg_concept_text("come on", "x", "B1", "concept:collocation.come-on")
    assert "CEFR" not in kg_concept_text("x", "", "weird", "concept:vocab.word.x")
    assert level_is_reliable("concept:phrase.cefr-sp-09000-ffd0857317") and not level_is_reliable("concept:idiom.for-crying-out-loud")


def test_a_keyword_blob_is_clipped_not_dropped():
    text = kg_concept_text("t", " ".join(["w"] * 5000), "", "concept:grammar.big-a87a422d3f")
    assert len(text.split()) < 70


def test_an_oversize_node_is_skipped_and_the_nodes_after_it_still_count():
    # break instead of continue: the first node alone cost more than the budget, so every node behind it was thrown away
    nodes = [
        {"id": "concept:x.huge", "title": "huge", "keywords": " ".join(["w"] * 400)},
        {"id": "concept:vocab.word.important", "title": "important", "keywords": "of great value", "level": "A1"},
    ]
    packed = _pack_kg_nodes_for_context(nodes, 20)
    assert [n["id"] for n in packed] == ["concept:vocab.word.important"]
    assert packed[0]["context_text"] == kg_concept_text("important", "of great value", "A1", "concept:vocab.word.important")


def test_packing_stops_at_the_budget_and_never_mutates_its_input():
    nodes = [{"id": f"concept:vocab.word.w{i}", "title": f"w{i}", "keywords": "a b c d e", "level": "A1"} for i in range(30)]
    packed = _pack_kg_nodes_for_context(nodes, 40)
    assert 0 < len(packed) < 30 and all("context_text" not in n for n in nodes)
    assert _pack_kg_nodes_for_context(nodes, 0) == []


def test_one_concept_found_by_three_routes_is_one_evidence_item_with_the_best_scores():
    items = [
        {"item_id": "c1", "kg_depth": 1, "vec_sim": 0.4, "text": "a"},
        {"item_id": "c2", "kg_depth": 1, "vec_sim": 0.1, "text": "b"},
        {"item_id": "c1", "kg_depth": 2, "vec_sim": 0.9, "text": "a"},
        {"item_id": "", "kg_depth": 0, "vec_sim": 0.0, "text": "no id"},
        {"item_id": "", "kg_depth": 0, "vec_sim": 0.0, "text": "no id either"},
    ]
    out = _merge_duplicate_evidence(items)
    assert [i["item_id"] for i in out] == ["c1", "c2", "", ""]   # items without an id are never merged
    assert out[0]["kg_depth"] == 1 and out[0]["vec_sim"] == 0.9


@pytest.fixture()
def kg():
    service = kg_module.KnowledgeGraphServiceV3.__new__(kg_module.KnowledgeGraphServiceV3)
    for attr in ("_keyword_index", "_keyword_idf", "_title_tokens", "_title_phrase"):
        setattr(service, attr, {})
    concepts = {
        "concept:vocab.word.important": ("important", "of great value or significance", "A1"),
        "concept:vocab.word.level": ("level", "a position on a scale", "B1"),
        "concept:vocab.word.word": ("word", "a unit of language", "A1"),
        "concept:vocab.word.english": ("English", "the language of England", "A1"),
        "concept:grammar.what-is-the-meaning-of-the-word-geek-a87a422d3f": (
            "What is the meaning of the word geek",
            "the word level of meaning in english is a word about what the word geek is " * 6, "B1"),
    }
    for n in range(60):   # a corpus with common words, so IDF means something
        concepts[f"concept:filler.{n}"] = (f"Filler {n}", "the word level english what is a unit of language scale value", "B1")
    service._concepts_cache = {cid: {"title": t, "keywords": k, "level": lv} for cid, (t, k, lv) in concepts.items()}
    rows = [(cid, m["title"], m["keywords"], m["level"]) for cid, m in service._concepts_cache.items()]

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
    service._build_topic_members = lambda: None
    service._build_concept_cache()
    return service


@pytest.mark.parametrize("question", [
    "What CEFR level is the English word 'important'?",   # quoted: the entity is named outright
    "what cefr level is the english word important?",     # unquoted: the frame words must not crowd it out
    'What CEFR level is the English word "important"?',
])
def test_the_word_a_learner_asks_about_is_the_first_concept_found(kg, question):
    top = kg.query_concepts(question, learner_level="B1", top_k=8)
    assert top[0]["id"] == "concept:vocab.word.important"
    assert top[0]["level"] == "A1"


def test_the_frame_words_of_a_question_are_not_entities_unless_quoted(kg):
    plain = kg.query_concepts("what level is the word important", "B1", 8)
    assert [t["id"] for t in plain[:1]] == ["concept:vocab.word.important"]
    asked = kg.query_concepts("what does 'level' mean", "B1", 8)
    assert asked[0]["id"] == "concept:vocab.word.level"


# ── KG_CONTEXT_V2=false must give back the behaviour the registered results were measured with ─────────────

def test_flag_off_restores_the_old_text_and_the_old_packer(monkeypatch):
    monkeypatch.setenv("KG_CONTEXT_V2", "false")
    assert kg_concept_text("about", "prep", "A1", "concept:vocab.word.about", keywords_always=True) == "Concept: about. Keywords: prep"
    assert kg_concept_text("about", "", "A1", "concept:vocab.word.about", label="Related concept (is_a)") == "Related concept (is_a): about"
    huge = " ".join(["w"] * 400)
    nodes = [{"id": "concept:x.huge", "title": "huge", "keywords": huge},
             {"id": "concept:vocab.word.important", "title": "important", "keywords": "of great value", "level": "A1"}]
    assert _pack_kg_nodes_for_context(nodes, 20) == []   # the old break: the oversize first node ended the list
    nodes[0]["keywords"] = "short"
    assert [n["context_text"] for n in _pack_kg_nodes_for_context(nodes, 40)] == [
        "Concept: huge. Keywords: short", "Concept: important. Keywords: of great value"]


def test_flag_off_leaves_ranking_as_it_was(kg, monkeypatch):
    monkeypatch.setenv("KG_CONTEXT_V2", "false")
    top = kg.query_concepts("What CEFR level is the English word 'important'?", learner_level="B1", top_k=8)
    assert all(t["score"] <= kg_module._TITLE_MATCH_BOOST for t in top)   # no named-entity floor
