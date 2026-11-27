"""What can honestly be checked about a short written answer.

A free-form answer has many right phrasings, so it is never compared verbatim.
It used to be accepted whenever it was 3+ characters, which let a keyboard
mash ("ádasdasdddd…") pass a "Write in English: 'Xin chào, chào buổi sáng'"
prompt. What is checkable without a model of meaning:

- it is written in the language the prompt asks for (most prompts want
  English; some translate the other way, "Translate into Vietnamese: '…'"),
  and is words rather than mashed keys;
- a translation prompt quotes its source, so the meaning is fixed: the answer
  must carry most of the model answer's words;
- a filler ("ok", "idk") is not an answer.

A gap with one right answer ("lasts {blank} minutes") or a True/False question
is not free writing: it belongs in fill_in_the_blank / true_or_false, and
shape_problems refuses it here so it cannot be saved as one.

Requiring a word the prompt names ("using 'increase'") was tried and dropped:
inflection ("increased", "ran"), "e.g." lists and model answers that ignore
their own prompt made it fail correct answers.

Rewording the structure ("English is spoken by her" for "She speaks English")
falls below the overlap threshold; that is the price of not running a model.
"""

from __future__ import annotations

import re

# A quote opens after a non-letter and closes before one, so the apostrophe in
# "mother's" or "don't" never starts or ends a quoted chunk.
_QUOTED = re.compile(r"(?<!\w)[\"'“‘«]([^\"“”‘’«»]{1,160}?)[\"'”’»](?!\w)")
_VIETNAMESE = re.compile(
    r"[àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ]", re.I
)
# "the Vietnamese sentence" names the source; only a target counts here.
_WANTS_VIETNAMESE = re.compile(
    r"\b(?:in|into|to)\s+vietnamese\b|\bvietnamese\s+translation\b|bằng tiếng việt",
    re.I,
)
_WANTS_ENGLISH = re.compile(r"\b(?:in|into|to)\s+english\b", re.I)
_ENGLISH_TOKEN = re.compile(r"[a-z]+(?:'[a-z]+)?")
_WORD = re.compile(r"[^\W\d_]+", re.UNICODE)
_REPEAT = re.compile(r"(\w)\1{3,}")
_VOWELS = set("aeiouyàáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹ")

# Enough of English's most common words that a real sentence of three or more
# words almost always contains one; a keyboard mash almost never does.
_FUNCTION_WORDS = frozenset(
    """a an the i you he she it we they me him her us them my your his its our their
    is am are was were be been being do does did have has had will would can could
    shall should may might must to of in on at for with from by about as into like
    and or but so if because when that this these those there here not no yes
    what who where why how which very too also just all some any many much more
    go goes went get got make made want like love need know think see say said
    good great nice hello hi thanks thank please today tomorrow yesterday""".split()
)

_CONTRACTIONS = {
    "n't": " not", "'re": " are", "'m": " am", "'ll": " will", "'ve": " have", "'d": " would",
}

# How much of the model translation an answer must carry (token F1).
TRANSLATION_MATCH_THRESHOLD = 0.65


def is_vietnamese(text: str) -> bool:
    return bool(_VIETNAMESE.search(text or ""))


def wants_vietnamese(prompt: str, model_answer: str = "") -> bool:
    """Whether the prompt asks for an answer in Vietnamese rather than English."""
    if _WANTS_ENGLISH.search(prompt or ""):
        return False
    if _WANTS_VIETNAMESE.search(prompt or ""):
        return True
    return is_vietnamese(model_answer)


def _tokens(text: str, vietnamese: bool = False) -> list[str]:
    lowered = (text or "").lower().replace("’", "'")
    if vietnamese:
        return _WORD.findall(lowered)
    for short, full in _CONTRACTIONS.items():
        lowered = lowered.replace(short, full)
    lowered = lowered.replace("'s", "")
    return _ENGLISH_TOKEN.findall(lowered)


def _stem(word: str) -> str:
    for suffix in ("ing", "ies", "ed", "es", "s"):
        if len(word) > len(suffix) + 2 and word.endswith(suffix):
            return word[: -len(suffix)]
    return word


def _looks_like_words(text: str, vietnamese: bool) -> bool:
    """Real words in the expected language, not mashed keys."""
    text = (text or "").strip()
    if not text:
        return False
    if is_vietnamese(text) and not vietnamese:
        return False  # an English task answered in Vietnamese
    if vietnamese and not is_vietnamese(text) and len(_tokens(text, True)) > 2:
        return False  # a Vietnamese task answered in English (short ones may lack a diacritic)
    letters = sum(ch.isalpha() for ch in text)
    if letters < 2 or letters < 0.6 * len(text.replace(" ", "")):
        return False
    tokens = _tokens(text, vietnamese)
    if not tokens:
        return False
    for token in tokens:
        if len(token) > 20 or _REPEAT.search(token):
            return False
        if len(token) >= 4 and not (_VOWELS & set(token)):  # "Mrs" is a word
            return False
    return True


def looks_like_english(answer: str) -> bool:
    return _looks_like_words(answer, vietnamese=False)


def quoted_source(prompt: str, vietnamese_target: bool = False) -> str | None:
    """The text a translation prompt asks to put into the other language."""
    for match in _QUOTED.finditer(prompt or ""):
        chunk = match.group(1)
        if vietnamese_target:
            # English source: real words, not a one-word instruction cue.
            if not is_vietnamese(chunk) and len(_tokens(chunk)) >= 1:
                return chunk
        elif is_vietnamese(chunk):
            return chunk
    return None


def translation_similarity(answer: str, model_answer: str, vietnamese: bool = False) -> float:
    """Token F1 between an answer and the model translation."""
    norm = (lambda t: t) if vietnamese else _stem
    got = {norm(t) for t in _tokens(answer, vietnamese)}
    want = {norm(t) for t in _tokens(model_answer, vietnamese)}
    overlap = len(got & want)
    if not overlap:
        return 0.0
    precision, recall = overlap / len(got), overlap / len(want)
    return 2 * precision * recall / (precision + recall)


_FILLERS = frozenset({"ok", "okay", "yes", "no", "idk", "dunno", "nothing", "none", "test", "abc"})
# Questions that ask the learner to pick, which free writing cannot grade.
_CHOICE_PROMPT = re.compile(
    r"^\s*(?:match|select|choose)\b|\bwhich\b[^?.]{0,80}\b(?:best|most appropriate|correctly)\b",
    re.I,
)


def grade_free_form(answer: str, model_answer: str, prompt: str) -> bool:
    vietnamese = wants_vietnamese(prompt, model_answer)
    if not _looks_like_words(answer, vietnamese):
        return False
    words = _tokens(answer, vietnamese)
    # "ok" is not a sentence; a one-word model answer ("Hello") allows one word.
    if len(words) < min(2, len(_tokens(model_answer, vietnamese)) or 2):
        return False
    if " ".join(words) in _FILLERS:
        return False
    tokens = set(words)

    if quoted_source(prompt, vietnamese) and model_answer.strip():
        return translation_similarity(answer, model_answer, vietnamese) >= TRANSLATION_MATCH_THRESHOLD
    if vietnamese:
        return True

    if len(tokens) >= 3:
        context = set(_tokens(model_answer)) | set(_tokens(prompt))
        if not (tokens & _FUNCTION_WORDS or tokens & context):
            return False
    return True


def shape_problems(prompt: str, model_answer: str) -> list[str]:
    """Why a short_writing_answer exercise cannot be graded as written."""
    problems = []
    model = (model_answer or "").strip()
    vietnamese = wants_vietnamese(prompt, model)
    if quoted_source(prompt, vietnamese) and not model:
        problems.append("translation prompt has no model answer to grade against")
    if model and not vietnamese and (is_vietnamese(model) or "|" in model):
        problems.append("model answer must be in English, as the prompt asks")
    if model.lower() in ("true", "false") or re.match(r"\s*true or false\b", prompt or "", re.I):
        problems.append("a True/False question belongs in true_or_false")
    elif _CHOICE_PROMPT.search(prompt or ""):
        problems.append("a question that asks to pick an answer needs options (multiple_choice)")
    return problems
