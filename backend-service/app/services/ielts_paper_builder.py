"""Pure building blocks for generating an original IELTS Academic Reading paper
from openly licensed passages: manifest parsing, passage cleaning, answer
validators and paper assembly.

No network, no LLM, no database here, so every rule is unit-testable. The
orchestration lives in `scripts/generate_ielts_paper.py`.

The questions are original, written against a passage we are allowed to
redistribute. Nothing is taken from Cambridge, British Council, IDP or any
practice site.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from html.parser import HTMLParser
from typing import Any
from urllib.parse import quote, urlparse

from app.core.content_licenses import (
    ALLOWED_LICENSE_IDS,
    PASSAGE_ONLY_LICENSE_IDS,
    passage_license_problem,
)

TFNG_LABELS = ("TRUE", "FALSE", "NOT GIVEN")
GAP = "______"
TOTAL_QUESTIONS = 40
MIN_PASSAGE_WORDS = 700
MAX_PASSAGE_WORDS = 900
HEADING_COUNT = 6
HEADING_DISTRACTORS = 3

QUESTION_TYPES = (
    "true_false_notgiven",
    "sentence_completion",
    "summary_completion",
    "multiple_choice",
    "matching_headings",
)
COMPLETION_TYPES = ("sentence_completion", "summary_completion")

_NUMBER_WORDS = {1: "ONE", 2: "TWO", 3: "THREE"}
_ROMAN = ["i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x", "xi", "xii"]


@dataclass(frozen=True)
class GroupSpec:
    question_type: str
    count: int
    word_limit: int | None = None


# 13 + 13 + 14 = 40. Passage 2 carries matching headings, so it is the one that
# must have enough paragraphs.
BLUEPRINT: tuple[tuple[GroupSpec, ...], ...] = (
    (
        GroupSpec("true_false_notgiven", 5),
        GroupSpec("sentence_completion", 4, 2),
        GroupSpec("multiple_choice", 4),
    ),
    (
        GroupSpec("matching_headings", HEADING_COUNT),
        GroupSpec("summary_completion", 4, 1),
        GroupSpec("true_false_notgiven", 3),
    ),
    (
        GroupSpec("true_false_notgiven", 5),
        GroupSpec("multiple_choice", 4),
        GroupSpec("sentence_completion", 5, 3),
    ),
)

assert sum(g.count for p in BLUEPRINT for g in p) == TOTAL_QUESTIONS


# ---------------------------------------------------------------- manifest ----

_WIKIPEDIA_TITLE_LICENSES = {"CC-BY-SA-4.0", "CC-BY-SA-3.0"}


class ManifestError(ValueError):
    pass


@dataclass(frozen=True)
class PassageSource:
    id: str
    kind: str
    title: str
    license_id: str
    revision: int | None = None
    ebook_id: int | None = None
    start_marker: str | None = None
    author: str | None = None
    publisher: str | None = None
    url_override: str | None = None

    @property
    def source_url(self) -> str:
        if self.kind == "wikipedia":
            return self.canonical_url
        if self.kind == "gutenberg":
            return f"https://www.gutenberg.org/cache/epub/{self.ebook_id}/pg{self.ebook_id}.txt"
        return self.url_override or ""

    @property
    def canonical_url(self) -> str:
        """The human-facing page, for attribution."""
        if self.kind == "wikipedia":
            slug = quote(self.title.replace(" ", "_"), safe="_(),'")
            return f"https://en.wikipedia.org/wiki/{slug}?oldid={self.revision}"
        if self.kind == "gutenberg":
            return f"https://www.gutenberg.org/ebooks/{self.ebook_id}"
        return self.url_override or ""

    @property
    def attribution(self) -> str:
        if self.kind == "wikipedia":
            return (
                f"From Wikipedia article '{self.title}' (rev {self.revision}), "
                f"{self.license_id.replace('CC-BY-SA-', 'CC BY-SA ')}"
            )
        if self.kind == "gutenberg":
            return (
                f"'{self.title}' by {self.author}, Project Gutenberg ebook #{self.ebook_id}; "
                "public domain in the United States"
            )
        return f"{self.publisher}, '{self.title}'; United States government work, public domain"


def parse_manifest(data: Any) -> list[PassageSource]:
    if not isinstance(data, dict) or not isinstance(data.get("passages"), list):
        raise ManifestError("manifest must be an object with a 'passages' list")
    sources: list[PassageSource] = []
    seen: set[str] = set()
    for index, raw in enumerate(data["passages"]):
        if not isinstance(raw, dict):
            raise ManifestError(f"passages[{index}] is not an object")
        pid = raw.get("id")
        if not isinstance(pid, str) or not re.fullmatch(r"[a-z0-9][a-z0-9-]*", pid):
            raise ManifestError(f"passages[{index}] needs a lowercase slug 'id'")
        if pid in seen:
            raise ManifestError(f"duplicate passage id {pid!r}")
        seen.add(pid)
        kind = raw.get("kind")
        title = raw.get("title")
        license_id = raw.get("license_id")
        if kind not in ("wikipedia", "gutenberg", "us_gov"):
            raise ManifestError(f"{pid}: kind must be wikipedia, gutenberg or us_gov")
        if not isinstance(title, str) or not title.strip():
            raise ManifestError(f"{pid}: missing title")
        if license_id not in ALLOWED_LICENSE_IDS or license_id not in PASSAGE_ONLY_LICENSE_IDS:
            raise ManifestError(f"{pid}: license_id {license_id!r} is not a passage licence")

        source = PassageSource(
            id=pid,
            kind=kind,
            title=title.strip(),
            license_id=license_id,
            revision=raw.get("revision"),
            ebook_id=raw.get("ebook_id"),
            start_marker=raw.get("start_marker"),
            author=raw.get("author"),
            publisher=raw.get("publisher"),
            url_override=raw.get("url"),
        )
        if kind == "wikipedia":
            if license_id not in _WIKIPEDIA_TITLE_LICENSES:
                raise ManifestError(f"{pid}: Wikipedia text is CC-BY-SA, not {license_id}")
            if not isinstance(source.revision, int) or source.revision <= 0:
                raise ManifestError(f"{pid}: a Wikipedia passage must pin an integer 'revision'")
        elif kind == "gutenberg":
            if license_id != "LicenseRef-Public-Domain":
                raise ManifestError(f"{pid}: Gutenberg entries are LicenseRef-Public-Domain")
            if not isinstance(source.ebook_id, int) or not source.start_marker or not source.author:
                raise ManifestError(f"{pid}: Gutenberg needs ebook_id, author and start_marker")
        else:
            if license_id != "LicenseRef-US-Gov-Public-Domain":
                raise ManifestError(f"{pid}: government entries are LicenseRef-US-Gov-Public-Domain")
            parsed = urlparse(source.url_override or "")
            host = parsed.hostname or ""
            if parsed.scheme != "https" or not (
                host.endswith(".gov") or host.endswith(".mil")
            ):
                raise ManifestError(f"{pid}: a government passage needs an https .gov url")
            if not source.publisher:
                raise ManifestError(f"{pid}: a government passage needs a publisher")
        sources.append(source)
    if not sources:
        raise ManifestError("manifest lists no passages")
    return sources


# ----------------------------------------------------------- passage text ----

_STOP_HEADINGS = {
    "see also", "references", "external links", "notes", "further reading",
    "bibliography", "citations", "sources", "footnotes", "gallery",
}
_SKIP_TAGS = {
    "script", "style", "sup", "figure", "table", "math", "nav", "header", "footer",
    "aside", "form", "button", "svg", "noscript", "figcaption", "ul", "ol", "dl",
}
_BLOCK_STOP_CLASSES = frozenset({"hatnote", "navbox", "reflist", "refbegin", "thumb", "infobox"})


class _ParagraphExtractor(HTMLParser):
    """Paragraph text only. Skipped subtrees are tracked by the root tag's own name,
    because real pages leave <li> and <p> unclosed and a plain depth counter
    would then swallow the rest of the document."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.paragraphs: list[str] = []
        self._skip_tag: str | None = None
        self._skip_depth = 0
        self._in_p = False
        self._buf: list[str] = []
        self._in_heading = False
        self._heading_buf: list[str] = []
        self.stopped = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if self.stopped:
            return
        if self._skip_tag:
            if tag == self._skip_tag:
                self._skip_depth += 1
            return
        classes = dict(attrs).get("class") or ""
        if tag in _SKIP_TAGS or _BLOCK_STOP_CLASSES & set(classes.split()):
            self._skip_tag, self._skip_depth = tag, 1
            return
        if tag in ("h2", "h3"):
            self._in_heading = True
            self._heading_buf = []
        elif tag == "p":
            self._in_p = True
            self._buf = []

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag == "br" and self._in_p and not self._skip_tag and not self.stopped:
            self._buf.append(" ")

    def handle_endtag(self, tag: str) -> None:
        if self.stopped:
            return
        if self._skip_tag:
            if tag == self._skip_tag:
                self._skip_depth -= 1
                if self._skip_depth == 0:
                    self._skip_tag = None
            return
        if tag in ("h2", "h3") and self._in_heading:
            self._in_heading = False
            heading = " ".join("".join(self._heading_buf).split()).lower()
            if heading in _STOP_HEADINGS:
                self.stopped = True
        elif tag == "p" and self._in_p:
            self._in_p = False
            text = " ".join("".join(self._buf).split())
            if text:
                self.paragraphs.append(text)

    def handle_data(self, data: str) -> None:
        if self._skip_tag or self.stopped:
            return
        if self._in_p:
            self._buf.append(data)
        elif self._in_heading:
            self._heading_buf.append(data)


def _strip_exotic_parentheses(text: str) -> str:
    """Drop pronunciation guides and foreign-script glosses, e.g. '(Ancient Greek: ...)'.

    Works on top-level groups so a gloss with a nested transliteration goes whole.
    """
    out: list[str] = []
    depth = 0
    start = 0
    for i, ch in enumerate(text):
        if ch == "(":
            if depth == 0:
                start = i
            depth += 1
        elif ch == ")" and depth:
            depth -= 1
            if depth == 0:
                inner = text[start + 1 : i]
                exotic = (
                    not inner.strip()
                    or any(ord(c) > 0x024F for c in inner)
                    or re.search(r"\blisten\b|\bpronounced\b|\bAncient Greek\b|\bLatin:", inner)
                )
                if exotic:
                    while out and out[-1] == " ":
                        out.pop()
                else:
                    out.append(text[start : i + 1])
        elif depth == 0:
            out.append(ch)
    if depth:
        out.append(text[start:])
    return "".join(out)


def clean_paragraph(text: str) -> str:
    text = re.sub(r"\[[^\]]{0,40}\]", "", text)
    text = _strip_exotic_parentheses(text)
    text = re.sub(r"\s+([,.;:])", r"\1", text)
    return " ".join(text.split())


def count_words(text: str) -> int:
    return len(text.split())


def extract_html_paragraphs(html: str) -> list[str]:
    parser = _ParagraphExtractor()
    parser.feed(html)
    out = []
    for paragraph in parser.paragraphs:
        cleaned = clean_paragraph(paragraph)
        if count_words(cleaned) >= 15:
            out.append(cleaned)
    return out


def extract_gutenberg_paragraphs(raw: str, start_marker: str) -> list[str]:
    start = re.search(r"\*\*\* START OF (THE|THIS) PROJECT GUTENBERG EBOOK.*?\*\*\*", raw)
    end = re.search(r"\*\*\* END OF (THE|THIS) PROJECT GUTENBERG EBOOK", raw)
    body = raw[start.end() if start else 0 : end.start() if end else len(raw)]
    body = body.replace("\r\n", "\n")
    out: list[str] = []
    started = False
    for block in re.split(r"\n\s*\n", body):
        text = " ".join(block.split())
        if not started:
            if text.startswith(start_marker):
                started = True
            else:
                continue
        text = re.sub(r"\{[^}]{0,12}\}", "", text)
        text = re.sub(r"\[(Picture|Illustration)[^\]]*\]", "", text)
        text = text.replace("_", "")
        letters = [c for c in text if c.isalpha()]
        if not letters or sum(c.isupper() for c in letters) / len(letters) > 0.5:
            continue
        cleaned = clean_paragraph(text)
        if count_words(cleaned) >= 15:
            out.append(cleaned)
    return out


def trim_to_length(
    paragraphs: list[str],
    min_words: int = MIN_PASSAGE_WORDS,
    max_words: int = MAX_PASSAGE_WORDS,
) -> list[str]:
    """Whole paragraphs from the start, as many as fit under max_words."""
    kept: list[str] = []
    total = 0
    for paragraph in paragraphs:
        words = count_words(paragraph)
        if total + words > max_words:
            break
        kept.append(paragraph)
        total += words
    if total < min_words:
        raise ValueError(
            f"only {total} words fit under {max_words} (need at least {min_words})"
        )
    return kept


def paragraph_letters(n: int) -> list[str]:
    return [chr(ord("A") + i) for i in range(n)]


def labelled_passage_text(paragraphs: list[str], labelled: bool) -> str:
    if not labelled:
        return "\n\n".join(paragraphs)
    return "\n\n".join(f"{letter}\n{p}" for letter, p in zip(paragraph_letters(len(paragraphs)), paragraphs))


def select_heading_paragraphs(paragraph_count: int, wanted: int = HEADING_COUNT) -> list[int]:
    """Evenly spread paragraph indexes; the caller has checked there are enough."""
    if paragraph_count < wanted:
        raise ValueError(
            f"matching headings needs {wanted} paragraphs, passage has {paragraph_count}"
        )
    if paragraph_count == wanted:
        return list(range(wanted))
    return sorted({round(i * (paragraph_count - 1) / (wanted - 1)) for i in range(wanted)})


# -------------------------------------------------------------- validators ----

def normalize_text(text: str) -> str:
    text = (
        text.replace("’", "'").replace("‘", "'")
        .replace("“", '"').replace("”", '"')
        .replace("–", "-").replace("—", "-")
    )
    return " ".join(text.lower().split())


def answer_word_count(answer: str) -> int:
    return len(answer.split())


def appears_verbatim(answer: str, passage: str) -> bool:
    needle = normalize_text(answer).strip(" .,;:!?\"'")
    if not needle:
        return False
    pattern = r"(?<![\w])" + re.escape(needle) + r"(?![\w])"
    return re.search(pattern, normalize_text(passage)) is not None


def word_limit_text(limit: int) -> str:
    if limit == 1:
        return "ONE WORD ONLY"
    return f"NO MORE THAN {_NUMBER_WORDS[limit]} WORDS"


def validate_tfng(question: dict) -> list[str]:
    answer = str(question.get("answer") or "").strip().upper()
    problems = []
    if answer not in TFNG_LABELS:
        problems.append(f"answer {question.get('answer')!r} is not TRUE, FALSE or NOT GIVEN")
    if not str(question.get("prompt") or "").strip():
        problems.append("statement is empty")
    return problems


def validate_completion(question: dict, passage: str, word_limit: int) -> list[str]:
    problems = []
    prompt = str(question.get("prompt") or "")
    answer = str(question.get("answer") or "").strip()
    if prompt.count(GAP) != 1:
        problems.append("prompt must contain exactly one gap")
    if not answer:
        problems.append("answer is empty")
        return problems
    if answer_word_count(answer) > word_limit:
        problems.append(f"answer {answer!r} is longer than {word_limit} word(s)")
    if not appears_verbatim(answer, passage):
        problems.append(f"answer {answer!r} does not appear verbatim in the passage")
    if prompt and answer and normalize_text(answer) in normalize_text(prompt.replace(GAP, "")):
        problems.append("answer already appears in the sentence")
    return problems


def validate_multiple_choice(question: dict) -> list[str]:
    options = question.get("options")
    answer = question.get("answer")
    problems = []
    if not isinstance(options, list) or len(options) != 4:
        return ["needs exactly four options"]
    if not all(isinstance(o, str) and o.strip() for o in options):
        problems.append("options must be non-empty strings")
    if len({normalize_text(str(o)) for o in options}) != 4:
        problems.append("options must be distinct")
    if answer not in options:
        problems.append("answer is not one of the options")
    elif sum(1 for o in options if o == answer) != 1:
        problems.append("answer must match exactly one option")
    if not str(question.get("prompt") or "").strip():
        problems.append("stem is empty")
    return problems


def validate_question(question: dict, spec: GroupSpec, passage: str) -> list[str]:
    kind = spec.question_type
    if kind == "true_false_notgiven":
        return validate_tfng(question)
    if kind in COMPLETION_TYPES:
        return validate_completion(question, passage, spec.word_limit or 1)
    if kind == "multiple_choice":
        return validate_multiple_choice(question)
    if kind == "matching_headings":
        return validate_heading_question(question)
    return [f"unknown question type {kind}"]


def validate_heading_question(question: dict) -> list[str]:
    options = question.get("options") or []
    if question.get("answer") not in options:
        return ["heading answer is not one of the headings"]
    if not str(question.get("paragraph") or "").strip():
        return ["heading question names no paragraph"]
    return []


def validate_group(questions: list[dict], spec: GroupSpec) -> list[str]:
    """Rules about a group as a whole, after each question has passed alone."""
    problems = []
    if spec.question_type == "true_false_notgiven" and len(questions) >= 3:
        labels = {str(q.get("answer")).upper() for q in questions}
        if len(labels) < 2:
            problems.append("every statement has the same answer")
    prompts = [normalize_text(str(q.get("prompt"))) for q in questions]
    if len(set(prompts)) != len(prompts):
        problems.append("duplicate prompts")
    return problems


def validate_headings(
    headings: list[dict], target_paragraphs: list[str]
) -> list[str]:
    """Headings list: one correct heading per target paragraph plus distractors."""
    problems = []
    texts = [normalize_text(str(h.get("text") or "")) for h in headings]
    if any(not t for t in texts):
        problems.append("a heading is empty")
    if len(set(texts)) != len(texts):
        problems.append("headings must be distinct")
    if len(headings) != len(target_paragraphs) + HEADING_DISTRACTORS:
        problems.append(
            f"need {len(target_paragraphs) + HEADING_DISTRACTORS} headings, got {len(headings)}"
        )
    mapped = [h.get("paragraph") for h in headings if h.get("paragraph")]
    if sorted(str(p) for p in mapped) != sorted(target_paragraphs):
        problems.append("each target paragraph needs exactly one correct heading")
    for h in headings:
        if count_words(str(h.get("text") or "")) > 12:
            problems.append("a heading is longer than 12 words")
            break
    return problems


def validate_paper(content: dict, expected_total: int | None = TOTAL_QUESTIONS) -> list[str]:
    """Whole-paper rules: count, continuous numbering, unique keys, an answer on each."""
    problems = []
    questions = [
        q
        for section in content.get("sections") or []
        for part in section.get("parts") or []
        for group in part.get("question_groups") or []
        for q in group.get("questions") or []
    ]
    if expected_total is not None and len(questions) != expected_total:
        problems.append(f"paper has {len(questions)} questions, needs exactly {expected_total}")
    numbers = [q.get("number") for q in questions]
    if numbers and numbers != list(range(numbers[0], numbers[0] + len(numbers))):
        problems.append("question numbering is not continuous")
    if expected_total is not None and numbers and numbers[0] != 1:
        problems.append("question numbering must start at 1")
    keys = [q.get("key") for q in questions]
    if len(set(keys)) != len(keys) or not all(keys):
        problems.append("question keys must be unique and present")
    for q in questions:
        if not q.get("accepted_answers"):
            problems.append(f"question {q.get('number')} has no answer key")
    return problems


# ---------------------------------------------------------------- assembly ----

def heading_label(index: int, text: str) -> str:
    return f"{_ROMAN[index]}. {text}"


def group_instructions(spec: GroupSpec, first: int, last: int) -> str:
    span = f"Questions {first}-{last}." if last > first else f"Question {first}."
    kind = spec.question_type
    if kind == "true_false_notgiven":
        return (
            f"{span} Do the following statements agree with the information given in "
            "the passage? Write TRUE if the statement agrees with the information, "
            "FALSE if the statement contradicts the information, or NOT GIVEN if "
            "there is no information on this."
        )
    if kind == "sentence_completion":
        return f"{span} Complete the sentences. Write {word_limit_text(spec.word_limit or 1)} from the passage for each answer."
    if kind == "summary_completion":
        return f"{span} Complete the summary. Write {word_limit_text(spec.word_limit or 1)} from the passage for each answer."
    if kind == "multiple_choice":
        return f"{span} Choose the correct letter, A, B, C or D. Write your answer as the full option."
    if kind == "matching_headings":
        return f"{span} The passage has paragraphs labelled A onwards. Choose the correct heading for each paragraph from the list of headings."
    raise ValueError(kind)


def build_reading_section(passages: list[dict], first_position: int = 1) -> dict:
    """`passages`: dicts with title, text, groups ([{spec, questions}]), source_note."""
    parts = []
    number = 1 if first_position == 1 else sum(
        g.count for p in BLUEPRINT[: first_position - 1] for g in p
    ) + 1
    for offset, passage in enumerate(passages):
        position = first_position + offset
        first_in_part = number
        groups = []
        for group in passage["groups"]:
            spec: GroupSpec = group["spec"]
            first = number
            built = []
            for q in group["questions"]:
                item: dict[str, Any] = {
                    "key": f"R{number}",
                    "number": number,
                    "prompt": q["prompt"],
                    "accepted_answers": [q["answer"]],
                }
                if q.get("options"):
                    item["options"] = list(q["options"])
                built.append(item)
                number += 1
            groups.append(
                {
                    "question_type": spec.question_type,
                    "instructions": group_instructions(spec, first, number - 1),
                    "questions": built,
                }
            )
        parts.append(
            {
                "order": position,
                "part_key": f"reading_passage_{position}",
                "title": f"Passage {position} - {passage['title']}",
                "passage_title": passage["title"],
                "passage_text": passage["text"],
                "source_note": passage["source_note"],
                "instructions": (
                    f"Questions {first_in_part}-{number - 1}. You should spend about "
                    "20 minutes on this passage."
                ),
                "question_groups": groups,
            }
        )
    return {"skill": "reading", "duration_minutes": 60, "parts": parts}


def build_provenance(
    entries: list[dict], generator: dict, first_position: int = 1
) -> dict:
    passages = []
    for offset, entry in enumerate(entries):
        passages.append({"section": f"reading:{first_position + offset}", **entry})
    return {"passages": passages, "generator": generator}


def provenance_entry(
    source: PassageSource, retrieved_at: str, words: int, trimmed: bool
) -> dict:
    note = (
        f"Adapted: {'shortened to whole paragraphs (' + str(words) + ' words); ' if trimmed else ''}"
        "citations, footnote markers and markup removed."
    )
    entry = {
        "title": source.title,
        "source_id": source.id,
        "source_url": source.canonical_url,
        "fetched_url": source.source_url,
        "license_id": source.license_id,
        "attribution": source.attribution,
        "retrieved_at": retrieved_at,
        "adapted": True,
        "adaptation_note": note,
        "word_count": words,
    }
    if source.revision:
        entry["revision"] = source.revision
    if source.ebook_id:
        entry["ebook_id"] = source.ebook_id
    problem = passage_license_problem(entry)
    if problem:
        raise ValueError(f"{source.id} {problem}")
    return entry


def slug_for(source_ids: list[str], digest: str) -> str:
    return "ielts-academic-reading-" + "-".join(source_ids)[:120] + f"-{digest[:8]}"
