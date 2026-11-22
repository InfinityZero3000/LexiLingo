"""generate_ielts_paper: manifest, passage cleaning, validators, provenance and the
draft write path. No network and no LLM: the chat client is patched with
autospec and answers from a table built out of the fixture passages."""

import argparse
import json
import re
import sys
from pathlib import Path
from unittest.mock import patch

import pytest
from sqlalchemy import select

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND / "scripts"))

import generate_ielts_paper as gip  # noqa: E402
from app.core.content_licenses import passage_license_problem  # noqa: E402
from app.models.ielts import IeltsTest  # noqa: E402
from app.routes.admin_ielts import provenance_problems, validate_test_content  # noqa: E402
from app.services import ielts_paper_builder as b  # noqa: E402
from app.services.ielts_paper_builder import GroupSpec, ManifestError, parse_manifest  # noqa: E402

MANIFEST = json.loads((BACKEND / "scripts" / "ielts_passage_manifest.json").read_text())


# ------------------------------------------------------------ manifest ----

def _entry(**overrides):
    base = {
        "id": "wp-test",
        "kind": "wikipedia",
        "title": "Test page",
        "revision": 123,
        "license_id": "CC-BY-SA-4.0",
    }
    base.update(overrides)
    return {"passages": [base]}


def test_committed_manifest_parses_and_is_pinned():
    sources = parse_manifest(MANIFEST)
    assert len(sources) >= 3
    kinds = {s.kind for s in sources}
    assert kinds == {"wikipedia", "gutenberg", "us_gov"}
    for s in sources:
        if s.kind == "wikipedia":
            assert isinstance(s.revision, int) and "oldid=" in s.source_url
        if s.kind == "gutenberg":
            assert s.ebook_id and s.start_marker
        if s.kind == "us_gov":
            assert s.source_url.startswith("https://") and ".gov" in s.source_url


def test_wikipedia_attribution_text():
    source = parse_manifest(_entry(title="Urban heat island", revision=99))[0]
    assert source.attribution == (
        "From Wikipedia article 'Urban heat island' (rev 99), CC BY-SA 4.0"
    )


@pytest.mark.parametrize(
    "bad",
    [
        {"revision": None},
        {"revision": "latest"},
        {"license_id": "CC0-1.0"},
        {"license_id": "LicenseRef-CEFR-J-Commercial"},
        {"license_id": "LicenseRef-Public-Domain"},
        {"kind": "scraped"},
        {"id": "Has Spaces"},
        {"title": ""},
    ],
)
def test_manifest_rejects(bad):
    with pytest.raises(ManifestError):
        parse_manifest(_entry(**bad))


def test_manifest_rejects_duplicates_and_empty_and_non_gov_url():
    one = _entry()["passages"][0]
    with pytest.raises(ManifestError):
        parse_manifest({"passages": [one, one]})
    with pytest.raises(ManifestError):
        parse_manifest({"passages": []})
    with pytest.raises(ManifestError):
        parse_manifest(
            _entry(
                id="gov-x", kind="us_gov", license_id="LicenseRef-US-Gov-Public-Domain",
                url="https://example.com/a", publisher="Somebody", revision=None,
            )
        )
    with pytest.raises(ManifestError):
        parse_manifest(
            _entry(
                id="gov-x", kind="us_gov", license_id="LicenseRef-US-Gov-Public-Domain",
                url="http://nasa.gov/a", publisher="NASA", revision=None,
            )
        )


# ------------------------------------------------------ passage cleaning ----

FILLER = " ".join(f"word{n}" for n in range(25))

WIKI_HTML = f"""
<html><body><section>
<p>Intro paragraph about the thing <sup class="mw-ref">[1]</sup> (Ancient Greek: αβγ) {FILLER}.</p>
<figure><figcaption>A caption that must not appear {FILLER}</figcaption></figure>
<table><tr><td><p>Table text must not appear {FILLER}</p></td></tr></table>
<ul><li>list item one<li>list item two unclosed</ul>
<div class="hatnote"><p>Hatnote must not appear {FILLER}</p></div>
<p>Short.</p>
<p>Second paragraph with   odd   spacing and a keeper (born 1900) who stayed. {FILLER}</p>
<h2>References</h2>
<p>Reference paragraph must not appear {FILLER}</p>
</section></body></html>
"""


def test_html_extraction_drops_markup_and_stops_at_references():
    paragraphs = b.extract_html_paragraphs(WIKI_HTML)
    assert len(paragraphs) == 2
    joined = " ".join(paragraphs)
    for banned in ("caption", "Table text", "Hatnote", "Reference paragraph", "[1]", "α"):
        assert banned not in joined
    assert "(born 1900)" in joined
    assert "odd spacing" in joined
    assert "list item" not in joined


def test_unclosed_list_items_do_not_swallow_the_rest():
    html = f"<ul><li>one<li>two</ul><p>{FILLER} {FILLER}</p>"
    assert len(b.extract_html_paragraphs(html)) == 1


GUTENBERG = f"""Title: Something

*** START OF THE PROJECT GUTENBERG EBOOK SOMETHING ***

CONTENTS.

CHAPTER I.
SOME LOUD HEADING

THE FIRST real paragraph starts here {{4a}} and says _many_ things {FILLER}.

[Picture: A cover]

A second paragraph with a footnote{{5}} and enough words {FILLER}.

*** END OF THE PROJECT GUTENBERG EBOOK SOMETHING ***
Licence text that must not appear {FILLER}
"""


def test_gutenberg_extraction_starts_at_marker_and_cleans_footnotes():
    paragraphs = b.extract_gutenberg_paragraphs(GUTENBERG, "THE FIRST real paragraph")
    assert len(paragraphs) == 2
    assert paragraphs[0].startswith("THE FIRST real paragraph")
    joined = " ".join(paragraphs)
    for banned in ("{4a}", "{5}", "_", "Picture", "Licence text"):
        assert banned not in joined


def _paras(n, words_each):
    return [" ".join(f"w{p}x{i}" for i in range(words_each)) for p in range(n)]


def test_trim_keeps_whole_paragraphs_inside_the_range():
    kept = b.trim_to_length(_paras(12, 100))
    total = sum(b.count_words(p) for p in kept)
    assert len(kept) == 9 and 700 <= total <= 900


def test_trim_refuses_a_passage_that_is_too_short():
    with pytest.raises(ValueError):
        b.trim_to_length(_paras(3, 100))


def test_select_heading_paragraphs():
    assert b.select_heading_paragraphs(6) == [0, 1, 2, 3, 4, 5]
    spread = b.select_heading_paragraphs(12)
    assert len(spread) == 6 and spread[0] == 0 and spread[-1] == 11
    with pytest.raises(ValueError):
        b.select_heading_paragraphs(5)


# ----------------------------------------------------------- validators ----

PASSAGE = "The harbour grew. Fishermen landed six tonnes of cod and the council kept a ledger at the quay."


def tf(answer="TRUE", prompt="Fishermen landed cod."):
    return {"prompt": prompt, "answer": answer}


def test_tfng_good_and_bad():
    for label in b.TFNG_LABELS:
        assert b.validate_tfng(tf(label)) == []
    assert b.validate_tfng(tf("YES"))
    assert b.validate_tfng(tf("true!"))
    assert b.validate_tfng(tf("TRUE", ""))


def comp(prompt="The council kept a ______ at the quay.", answer="ledger"):
    return {"prompt": prompt, "answer": answer}


def test_completion_good():
    assert b.validate_completion(comp(), PASSAGE, 1) == []
    assert b.validate_completion(comp(answer="Ledger"), PASSAGE, 1) == []
    assert b.validate_completion(comp("Fishermen landed ______ of cod.", "six tonnes"), PASSAGE, 2) == []


def test_completion_each_failure():
    assert any("verbatim" in p for p in b.validate_completion(comp(answer="register"), PASSAGE, 1))
    assert any("longer than" in p for p in b.validate_completion(comp("Landed ______ of cod.", "six tonnes"), PASSAGE, 1))
    assert any("gap" in p for p in b.validate_completion(comp("No gap here."), PASSAGE, 1))
    assert any("gap" in p for p in b.validate_completion(comp("Two ______ gaps ______."), PASSAGE, 1))
    assert any("empty" in p for p in b.validate_completion(comp(answer=""), PASSAGE, 1))
    assert any("already appears" in p for p in b.validate_completion(comp("The ledger and a ______."), PASSAGE, 1))
    # a partial-word match is not verbatim
    assert b.validate_completion(comp(answer="ledg"), PASSAGE, 1)


def mc(**overrides):
    q = {"prompt": "What did the council keep?", "options": ["a map", "a ledger", "a net", "a boat"], "answer": "a ledger"}
    q.update(overrides)
    return q


def test_multiple_choice_good_and_bad():
    assert b.validate_multiple_choice(mc()) == []
    assert any("not one of" in p for p in b.validate_multiple_choice(mc(answer="a diary")))
    assert b.validate_multiple_choice(mc(options=["a", "b", "c"]))
    assert any("distinct" in p for p in b.validate_multiple_choice(mc(options=["a", "A", "c", "a ledger"])))
    assert b.validate_multiple_choice(mc(prompt=""))
    assert b.validate_multiple_choice(mc(options="a ledger"))


def test_heading_validation():
    headings = [{"text": f"Heading {i}", "paragraph": ch} for i, ch in enumerate("ABCDEF")]
    headings += [{"text": f"Distractor {i}", "paragraph": None} for i in range(3)]
    targets = list("ABCDEF")
    assert b.validate_headings(headings, targets) == []
    assert b.validate_headings(headings[:-1], targets)
    duplicated = [dict(h) for h in headings]
    duplicated[1]["text"] = duplicated[0]["text"]
    assert any("distinct" in p for p in b.validate_headings(duplicated, targets))
    wrong = [dict(h) for h in headings]
    wrong[0]["paragraph"] = "Z"
    assert any("target paragraph" in p for p in b.validate_headings(wrong, targets))
    long = [dict(h) for h in headings]
    long[0]["text"] = " ".join(["word"] * 13)
    assert any("longer" in p for p in b.validate_headings(long, targets))
    assert b.validate_heading_question({"answer": "i. x", "options": ["i. x"], "paragraph": "A"}) == []
    assert b.validate_heading_question({"answer": "i. y", "options": ["i. x"], "paragraph": "A"})


def test_group_rules():
    spec = GroupSpec("true_false_notgiven", 3)
    same = [tf("TRUE", f"s{i}") for i in range(3)]
    assert any("same answer" in p for p in b.validate_group(same, spec))
    mixed = [tf("TRUE", "a"), tf("FALSE", "b"), tf("NOT GIVEN", "c")]
    assert b.validate_group(mixed, spec) == []
    dup = [tf("TRUE", "a"), tf("FALSE", "a"), tf("NOT GIVEN", "c")]
    assert any("duplicate" in p for p in b.validate_group(dup, spec))


def _paper_content(total=40, start=1):
    questions = [
        {"key": f"R{n}", "number": n, "prompt": "p", "accepted_answers": ["a"]}
        for n in range(start, start + total)
    ]
    return {"sections": [{"skill": "reading", "parts": [{"question_groups": [{"questions": questions}]}]}]}


def test_paper_rules():
    assert b.validate_paper(_paper_content()) == []
    assert any("exactly 40" in p for p in b.validate_paper(_paper_content(39)))
    assert any("exactly 40" in p for p in b.validate_paper(_paper_content(41)))
    assert b.validate_paper(_paper_content(13, start=14), expected_total=None) == []
    gap = _paper_content()
    del gap["sections"][0]["parts"][0]["question_groups"][0]["questions"][10]
    gap["sections"][0]["parts"][0]["question_groups"][0]["questions"].append(
        {"key": "R99", "number": 99, "prompt": "p", "accepted_answers": ["a"]}
    )
    assert any("continuous" in p for p in b.validate_paper(gap))
    dup = _paper_content()
    dup["sections"][0]["parts"][0]["question_groups"][0]["questions"][1]["key"] = "R1"
    assert any("unique" in p for p in b.validate_paper(dup))
    blank = _paper_content()
    blank["sections"][0]["parts"][0]["question_groups"][0]["questions"][0]["accepted_answers"] = []
    assert any("no answer key" in p for p in b.validate_paper(blank))
    late = _paper_content(40, start=2)
    assert any("start at 1" in p for p in b.validate_paper(late))


# --------------------------------------------- fake LLM and fixture passages ----

def _paragraph(i, p):
    filler = " ".join(f"pad{i}{p}{n}" for n in range(60))
    return (
        f"The harbour of town{i} grew during period{p}. Fishermen landed {p + 3} tonnes of "
        f"cod{i}x{p} every morning and the council recorded the figures carefully in a ledger "
        f"kept at the quay for visitors to inspect. {filler}."
    )


def passage_paragraphs(i, n=9):
    return [_paragraph(i, p) for p in range(n)]


def evidence_for(i, p):
    return f"The harbour of town{i} grew during period{p}"


LEDGER_EVIDENCE = "recorded the figures carefully in a ledger kept at the quay"


class FakeLlm:
    """Writes questions for the fixture passages and answers the blind pass from the same table."""

    def __init__(self):
        self.truth: dict[tuple[int, str], tuple[str, str]] = {}
        self.flip: set[str] = set()
        self.bad_evidence: set[str] = set()
        self.calls: list[str] = []
        self.all_true = False

    @staticmethod
    def _town(user):
        return int(re.search(r"town(\d)", user).group(1))

    def __call__(self, chat, *, system, user, label):
        task = user.split("\n", 1)[0]
        self.calls.append(task)
        town = self._town(user)
        if task.startswith("TASK: verify"):
            return self._verify(town, user)
        kind = re.search(r"generate (\w+)", task).group(1)
        if kind == "matching_headings":
            targets = re.search(r"targets=([A-Z,]+)", task).group(1).split(",")
            headings = [
                {"text": f"Heading {k} of town{town}", "paragraph": targets[k] if k < len(targets) else None}
                for k in range(len(targets) + 3)
            ]
            for k, letter in enumerate(targets):
                self.truth[(town, f"Paragraph {letter}")] = (
                    f"Heading {k} of town{town}", evidence_for(town, "ABCDEFGHIJ".index(letter)),
                )
            return {"headings": headings}
        count = int(re.search(r"count=(\d+)", task).group(1))
        questions = []
        for j in range(count):
            if kind == "true_false_notgiven":
                label_ = "TRUE" if self.all_true else ("TRUE", "FALSE", "NOT GIVEN")[j % 3]
                prompt = f"Statement {j} about town{town} ({label_})"
                self.truth[(town, prompt)] = (label_, "" if label_ == "NOT GIVEN" else evidence_for(town, j % 9))
                questions.append({"prompt": prompt, "answer": label_})
            elif kind in ("sentence_completion", "summary_completion"):
                prompt = f"Item {j}: the council of town{town} kept a ______ at the quay."
                self.truth[(town, prompt)] = ("ledger", LEDGER_EVIDENCE)
                questions.append({"prompt": prompt, "answer": "ledger"})
            elif kind == "multiple_choice":
                prompt = f"Question {j} on town{town}?"
                options = [f"alpha{j}", f"beta{j}", f"gamma{j}", f"delta{j}"]
                answer = options[j % 4]
                self.truth[(town, prompt)] = (answer, evidence_for(town, j % 9))
                questions.append({"prompt": prompt, "options": options, "answer": answer})
        return {"questions": questions}

    def _verify(self, town, user):
        results = []
        for line in user.split("QUESTIONS (one JSON object per line):\n", 1)[1].split("\n\nAnswer every")[0].splitlines():
            item = json.loads(line)
            answer, evidence = self.truth[(town, item["prompt"])]
            if item["prompt"] in self.flip:
                answer = "TRUE" if answer != "TRUE" else "FALSE"
            if item["prompt"] in self.bad_evidence:
                evidence = "a sentence the passage never contains"
            results.append({"id": item["id"], "answer": answer, "evidence": evidence})
        return {"results": results}


@pytest.fixture
def llm():
    fake = FakeLlm()
    with patch.object(gip.GroqChat, "complete_json", autospec=True, side_effect=fake):
        yield fake


def _chat():
    return gip.GroqChat(None, ["k"], "test-model", concurrency=2, delay=0)


def _passages(ids=("wp-antikythera", "wp-mycorrhiza", "wp-urban-heat-island")):
    manifest = {s.id: s for s in gip.load_manifest()}
    out = []
    for i, pid in enumerate(ids, start=1):
        out.append(
            gip.passage_from_paragraphs(manifest[pid], passage_paragraphs(i, 9), "2026-11-16T00:00:00Z")
        )
    return out


async def _build_paper(passages=None, first_position=1):
    passages = passages or _passages()
    chat = _chat()
    built = [
        await gip.build_passage_groups(chat, p, first_position + k) for k, p in enumerate(passages)
    ]
    return gip.assemble_paper(passages, built, first_position, "test-model", partial=len(passages) != 3)


# ------------------------------------------------------------ pipeline ----

async def test_full_paper_has_forty_verified_questions_and_passes_the_publish_gate(llm):
    paper = await _build_paper()
    content = paper["content"]
    assert b.validate_paper(content) == []
    questions = [
        q for part in content["sections"][0]["parts"]
        for g in part["question_groups"] for q in g["questions"]
    ]
    assert [q["number"] for q in questions] == list(range(1, 41))
    assert [len(list(g["questions"])) for part in content["sections"][0]["parts"] for g in part["question_groups"]] == [
        5, 4, 4, 6, 4, 3, 5, 4, 5,
    ]
    assert paper["skill_scope"] == "reading" and "is_published" not in paper
    assert validate_test_content(content, "reading") == []
    assert provenance_problems(content, paper["provenance"]) == []
    for entry in paper["provenance"]["passages"]:
        assert passage_license_problem(entry) is None
    assert [e["section"] for e in paper["provenance"]["passages"]] == ["reading:1", "reading:2", "reading:3"]


async def test_provenance_shape_per_passage(llm):
    paper = await _build_paper()
    wiki = paper["provenance"]["passages"][0]
    assert wiki["license_id"] == "CC-BY-SA-4.0"
    assert wiki["attribution"].startswith("From Wikipedia article 'Antikythera mechanism' (rev ")
    assert wiki["source_url"].startswith("https://en.wikipedia.org/wiki/Antikythera_mechanism?oldid=")
    assert wiki["adapted"] is True and wiki["revision"] and wiki["retrieved_at"]
    assert paper["provenance"]["generator"]["model"] == "test-model"


async def test_gate_rejects_provenance_without_a_licence(llm):
    paper = await _build_paper()
    del paper["provenance"]["passages"][1]["license_id"]
    assert any("Reading passage" in p for p in provenance_problems(paper["content"], paper["provenance"]))
    paper["provenance"]["passages"][1]["license_id"] = "LicenseRef-CEFR-J-Commercial"
    assert provenance_problems(paper["content"], paper["provenance"])


async def test_every_stored_answer_obeys_the_validators(llm):
    paper = await _build_paper()
    for part, text in zip(
        paper["content"]["sections"][0]["parts"], ("\n\n".join(p["paragraphs"]) for p in _passages())
    ):
        for g in part["question_groups"]:
            for q in g["questions"]:
                answer = q["accepted_answers"][0]
                if g["question_type"] == "true_false_notgiven":
                    assert answer in b.TFNG_LABELS
                if g["question_type"] in b.COMPLETION_TYPES:
                    assert b.appears_verbatim(answer, text) and b.answer_word_count(answer) <= 3
                if g["question_type"] in ("multiple_choice", "matching_headings"):
                    assert answer in q["options"]


async def test_headings_are_labelled_and_numbered_in_the_passage(llm):
    paper = await _build_paper()
    part2 = paper["content"]["sections"][0]["parts"][1]
    assert part2["passage_text"].startswith("A\n") and "\n\nB\n" in part2["passage_text"]
    assert not paper["content"]["sections"][0]["parts"][0]["passage_text"].startswith("A\n")
    options = part2["question_groups"][0]["questions"][0]["options"]
    assert len(options) == 9 and options[0].startswith("i. ") and options[8].startswith("ix. ")


async def test_a_question_the_blind_pass_answers_differently_is_dropped_and_replaced(llm):
    llm.flip.add("Statement 0 about town1 (TRUE)")
    passages = _passages()
    built = await gip.build_passage_groups(_chat(), passages[0], 1)
    prompts = [q["prompt"] for q in built["groups"][0]["questions"]]
    assert len(prompts) == 5
    assert "Statement 0 about town1 (TRUE)" not in prompts


async def test_evidence_that_is_not_in_the_passage_is_dropped(llm):
    llm.bad_evidence.add("Statement 1 about town1 (FALSE)")
    built = await gip.build_passage_groups(_chat(), _passages()[0], 1)
    assert "Statement 1 about town1 (FALSE)" not in [q["prompt"] for q in built["groups"][0]["questions"]]


async def test_paper_is_refused_when_a_group_cannot_be_verified(llm):
    for j in range(20):
        llm.flip.add(f"Item {j}: the council of town1 kept a ______ at the quay.")
    llm.flip |= {f"Statement {j} about town1 ({l})" for j in range(10) for l in b.TFNG_LABELS}
    with pytest.raises(gip.PaperRefused):
        await gip.build_passage_groups(_chat(), _passages()[0], 1)
    assert len(llm.calls) <= 2 * gip.MAX_ROUNDS + 2


async def test_a_group_with_one_repeated_answer_is_rejected(llm):
    llm.all_true = True
    with pytest.raises(gip.PaperRefused):
        await gip.build_passage_groups(_chat(), _passages()[0], 1)


async def test_chat_is_called_with_autospecced_signature(llm):
    await gip.build_passage_groups(_chat(), _passages()[0], 1)
    assert llm.calls and all(c.startswith("TASK:") for c in llm.calls)


# ------------------------------------------------------------ llm client ----

async def test_groq_request_keeps_reasoning_on_and_pins_json():
    sent = {}

    class Client:
        async def post(self, url, json=None, headers=None, timeout=None):
            sent.update(json=json, headers=headers, url=url)

            class R:
                status_code = 200
                text = ""

                def json(self_inner):
                    return {"choices": [{"message": {"content": '{"ok": true}'}}]}

            return R()

    chat = gip.GroqChat(Client(), ["secret"], "qwen/qwen3.8-27b", concurrency=1, delay=0)
    assert await chat.complete_json(system="s", user="u", label="t") == {"ok": True}
    assert sent["json"]["response_format"] == {"type": "json_object"}
    assert sent["json"]["reasoning_effort"] in ("low", "medium", "high")
    assert sent["json"]["model"] == "qwen/qwen3.8-27b"
    assert sent["headers"]["Authorization"] == "Bearer secret"


def test_defaults_match_the_free_tier_pacing():
    args = gip.parse_args([])
    assert (args.concurrency, args.delay) == (2, 6.0)
    assert args.dry_run is False and args.first_position == 1


def test_gap_markers_are_normalised_with_spaces():
    spec = GroupSpec("sentence_completion", 1, 2)
    cleaned = gip._clean_question({"prompt": "Landed at______than noon, a ____ later.", "answer": "x."}, spec)
    assert cleaned["prompt"].count("______") == 2 and "at ______ than" in cleaned["prompt"]
    cleaned = gip._clean_question({"prompt": "It ends with a ______ .", "answer": "x"}, spec)
    assert cleaned["prompt"] == "It ends with a ______."


# --------------------------------------------------------- run and save ----

def _fake_fetch(client, source):
    index = [s.id for s in gip.load_manifest()].index(source.id) + 1
    return gip.passage_from_paragraphs(source, passage_paragraphs(index, 9), "2026-11-16T00:00:00Z")


def _args(**overrides):
    base = dict(
        passages=None, first_position=1, dry_run=False, out=None, replace=False,
        concurrency=2, delay=0.0,
    )
    base.update(overrides)
    return argparse.Namespace(**base)


async def test_run_builds_a_paper_from_the_first_three_manifest_entries(llm):
    with patch.object(gip, "fetch_passage", autospec=True, side_effect=_fake_fetch):
        paper = await gip.run(_args())
    assert [e["source_id"] for e in paper["provenance"]["passages"]] == [
        "wp-antikythera", "wp-mycorrhiza", "wp-urban-heat-island",
    ]
    assert gip.draft_problems(paper) == []


async def test_run_refuses_fewer_than_three_passages_unless_dry_run(llm):
    with patch.object(gip, "fetch_passage", autospec=True, side_effect=_fake_fetch):
        with pytest.raises(gip.PaperRefused):
            await gip.run(_args(passages="wp-mycorrhiza"))
        paper = await gip.run(_args(passages="wp-mycorrhiza", first_position=2, dry_run=True))
    numbers = [
        q["number"] for g in paper["content"]["sections"][0]["parts"][0]["question_groups"]
        for q in g["questions"]
    ]
    assert numbers == list(range(14, 27))
    assert paper["provenance"]["passages"][0]["section"] == "reading:2"


async def test_run_rejects_unknown_ids(llm):
    with pytest.raises(gip.PaperRefused):
        await gip.run(_args(passages="nope,wp-mycorrhiza,wp-printing-press"))


async def test_draft_row_is_created_unpublished_with_provenance(llm, db_session):
    with patch.object(gip, "fetch_passage", autospec=True, side_effect=_fake_fetch):
        paper = await gip.run(_args())
    action, test_id = await gip.save_draft(db_session, paper)
    assert action == "created"
    row = (await db_session.execute(select(IeltsTest).where(IeltsTest.slug == paper["slug"]))).scalar_one()
    assert str(row.id) == test_id
    assert row.is_published is False
    assert row.skill_scope == "reading" and row.test_type == "academic"
    assert row.provenance["passages"][0]["license_id"] == "CC-BY-SA-4.0"
    assert provenance_problems(row.content, row.provenance) == []
    assert validate_test_content(row.content, row.skill_scope) == []


async def test_save_refuses_to_overwrite_without_replace_and_never_a_published_row(llm, db_session):
    with patch.object(gip, "fetch_passage", autospec=True, side_effect=_fake_fetch):
        paper = await gip.run(_args())
    await gip.save_draft(db_session, paper)
    with pytest.raises(gip.PaperRefused, match="--replace"):
        await gip.save_draft(db_session, paper)
    action, _ = await gip.save_draft(db_session, paper, replace=True)
    assert action == "replaced"
    row = (await db_session.execute(select(IeltsTest).where(IeltsTest.slug == paper["slug"]))).scalar_one()
    row.is_published = True
    await db_session.commit()
    with pytest.raises(gip.PaperRefused, match="published"):
        await gip.save_draft(db_session, paper, replace=True)


async def test_main_dry_run_writes_json_and_touches_no_database(llm, tmp_path):
    out = tmp_path / "paper.json"
    with patch.object(gip, "fetch_passage", autospec=True, side_effect=_fake_fetch):
        code = await gip.main(_args(dry_run=True, out=str(out)))
    assert code == 0
    written = json.loads(out.read_text())
    assert written["skill_scope"] == "reading" and len(written["provenance"]["passages"]) == 3


async def test_main_returns_one_and_writes_nothing_when_refused(llm, tmp_path):
    out = tmp_path / "paper.json"
    for j in range(30):
        llm.flip.add(f"Item {j}: the council of town1 kept a ______ at the quay.")
    with patch.object(gip, "fetch_passage", autospec=True, side_effect=_fake_fetch):
        code = await gip.main(_args(dry_run=True, out=str(out)))
    assert code == 1 and not out.exists()
