"""The KG-grounded QA set must still agree with the sources it was read from.

If a KG source file or the Wiktionary reference changes, a gold answer can silently
stop being what its source says — and every hallucination number computed against it
is then wrong. Rebuild with `python scripts/build_kg_grounded_eval.py` when this fails.
"""
import collections
import hashlib
import importlib.util
import json
import os

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ITEMS = os.path.join(ROOT, "data", "eval", "kg_grounded_qa.jsonl")
MANIFEST = os.path.join(ROOT, "data", "eval", "kg_grounded_qa.manifest.json")

_spec = importlib.util.spec_from_file_location(
    "build_kg_grounded_eval", os.path.join(ROOT, "scripts", "build_kg_grounded_eval.py"))
builder = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(builder)


@pytest.fixture(scope="module")
def data():
    with open(ITEMS, encoding="utf-8") as fh:
        items = [json.loads(line) for line in fh]
    with open(MANIFEST, encoding="utf-8") as fh:
        manifest = json.load(fh)
    concepts, _, edges = builder.load_kg()
    edge_set = {(s, o, r, f) for s, o, r, f in edges}
    return items, manifest, concepts, edge_set, builder.load_wiktionary()


def test_file_is_what_the_builder_wrote(data):
    _, manifest, *_ = data
    with open(ITEMS, "rb") as fh:
        assert hashlib.sha256(fh.read()).hexdigest() == manifest["items_sha256"]


def test_strata_and_uniqueness(data):
    items, manifest, *_ = data
    counts = collections.Counter(it["stratum"] for it in items)
    assert dict(counts) == manifest["counts"]
    assert set(counts) == {"single_fact", "multi_hop", "text_only", "adversarial"}
    assert len(items) >= 1000
    assert len({it["id"] for it in items}) == len(items)
    assert len({it["question"] for it in items}) == len(items)


def test_every_gold_triple_still_holds_in_the_kg(data):
    items, manifest, concepts, edge_set, _ = data
    excluded = set(manifest["kg_conflicts_excluded"])
    for it in items:
        if it["expected_behavior"] != "abstain" and it["stratum"] != "text_only":
            assert it["gold_triples"], it["id"]
        for t in it["gold_triples"]:
            if t["p"] == "has_cefr_level":
                # a level the KG states two ways is never gold
                assert t["s"] not in excluded, (it["id"], t)
                assert concepts[t["s"]]["level"] == t["o"], (it["id"], t)
            elif t["p"] == "translates_to":
                assert t["o"] in builder.split_gloss(concepts[t["s"]]["keywords"])[1], (it["id"], t)
            else:
                assert (t["s"], t["o"], t["p"], t["source"]) in edge_set, (it["id"], t)
                assert f"{t['s']} -[{t['p']}]-> {t['o']}" not in excluded, (it["id"], t)


def test_unanswerable_words_are_absent_from_the_kg(data):
    items, _, concepts, *_ = data
    titles = {c["title"].strip().lower() for c in concepts.values()}
    nonwords = [it["gold"]["nonword"] for it in items if it["expected_behavior"] == "abstain"]
    assert len(nonwords) == len(set(nonwords)) >= 100
    assert not titles & set(nonwords)


def test_confirmed_glosses_are_really_in_wiktionary(data):
    items, _, concepts, _, wikt = data
    confirmed = [it for it in items if it["type"] == "vi_gloss" and it["gold"]["external"]["status"] == "confirmed"]
    assert confirmed, "no externally confirmed glosses: run scripts/crawl_wiktionary_reference.py"
    for it in confirmed:
        word = concepts[it["gold_triples"][0]["s"]]["title"]
        ref = {builder.norm_vi(v) for v in wikt[word]["vi_translations"]}
        assert {builder.norm_vi(a) for a in it["gold"]["aliases"]} & ref, it["id"]


def test_text_only_answers_come_from_wiktionary_and_not_from_the_kg(data):
    items, _, concepts, _, wikt = data
    text_only = [it for it in items if it["stratum"] == "text_only"]
    assert len(text_only) >= 100
    kg_text = {c["title"]: (c["title"] + " " + c.get("keywords", "")).lower() for c in concepts.values()}
    for it in text_only:
        assert not it["answerable_from_kg"] and it["gold_triples"] == []
        word = it["question_en"].split("'")[1]
        pos, form = it["type"].split("_", 1)
        forms = wikt[word]["pos"][pos.capitalize()]["forms"][form]
        assert it["gold"]["aliases"] == forms, it["id"]
        assert all(a not in kg_text[word].split() for a in forms), it["id"]


def test_every_cefr_gold_is_confirmed_by_the_independent_lexicon(data):
    items, _, concepts, _, _ = data
    lexicon = builder.load_lexicon()
    assert lexicon, "run scripts/build_cefr_lexicon.py"
    cefr_types = {"cefr_level", "cefr_comparison", "false_premise_cefr"}
    checked = 0
    for it in items:
        if it["type"] not in cefr_types:
            continue
        for t in it["gold_triples"]:
            word = concepts[t["s"]]["title"].lower()
            assert lexicon.get(word) == {t["o"]}, (it["id"], word, t["o"], lexicon.get(word))
            checked += 1
    assert checked >= 600


def test_the_kg_has_no_backwards_prerequisite_edge_or_cross_file_level_conflict(data):
    _, _, concepts, edge_set, _ = data
    conflicts = builder.kg_conflicts(builder.DATA, concepts, [(s, o, r, f) for s, o, r, f in edge_set])
    assert not {k: v for k, v in conflicts.items() if not v.startswith("title")}
    for s, o, r, f in edge_set:
        if r in builder.PREREQ_RELATIONS and f in builder.CURATED_FILES:
            before, after = builder.PREREQ_RELATIONS[r](s, o)
            assert builder.RANK.get(concepts[before].get("level"), 0) <= builder.RANK.get(concepts[after].get("level"), 9), (s, r, o)
