from api.services.trace_cag.benchmark.ranking import _select_diverse_multihop_evidence


def test_diverse_selection_prefers_the_uncovered_hop_over_a_stronger_duplicate():
    """Absolute anchor coverage scores a second passage about an already-covered
    entity the same as the one passage carrying the missing hop, so a tight
    budget fills with the dominant entity and the bridge is cut. Selection must
    reward the anchors a document ADDS."""
    from api.services.trace_cag.benchmark.ranking import _select_diverse_multihop_evidence

    question = "Were Scott Derrickson and Ed Wood of the same nationality?"
    items = [
        {"title": "Scott Derrickson", "text": "Scott Derrickson is an American director.", "fusion_score": 0.90},
        {"title": "Sinister (film)", "text": "Scott Derrickson directed Sinister.", "fusion_score": 0.80},
        {"title": "Ed Wood", "text": "Ed Wood was an American filmmaker.", "fusion_score": 0.55},
    ]

    titles = [
        item["title"]
        for item in _select_diverse_multihop_evidence(items=items, question=question, budget=2)
    ]

    assert "Scott Derrickson" in titles
    assert "Ed Wood" in titles, (
        "the second hop lost its slot to a higher-scoring passage about the hop "
        "already covered — the question is unanswerable without it"
    )


def test_ranker_does_not_train_the_bridge_passage_as_a_negative(monkeypatch):
    """A hop-1 passage names the bridge entity but never the answer, so the
    answer-support score puts it at ~0 and the old rule labelled it 0.0 —
    training the ranker to demote the passage the second hop depends on.
    Anchor-carrying passages must stay unlabelled; anchor-free ones stay
    negative so the ranker still sees distractors."""
    from api.services.trace_cag.benchmark import ranking

    captured: list = []

    class _Ranker:
        def observe(self, payload):
            captured.extend(payload)

    monkeypatch.setattr(ranking, "get_retrieval_ranker", lambda: _Ranker())
    monkeypatch.setattr(ranking, "_ranker_enabled", lambda: True)

    ranking._update_ranker_from_generation(
        question="What city founded the organization that Seed Page mentions?",
        response="Khazan",
        retrieval_trace=[
            {"item_id": "h1", "title": "Seed Page", "text": "Seed Page mentions Bridge Target often."},
            {"item_id": "d1", "title": "Unrelated", "text": "A treatise on marine biology."},
        ],
    )

    labels = {row["item_id"]: row["label"] for row in captured}
    assert labels.get("h1") != 0.0, "the hop-1 bridge passage must not be a negative"
    assert labels.get("d1") == 0.0, "an anchor-free distractor should still train as negative"
