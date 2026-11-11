"""Build the KG-grounded QA set used to measure whether the KG reduces hallucination.

Usage:  python scripts/build_kg_grounded_eval.py

Every gold answer is read off the runtime KG source files (no LLM), so most strata
measure faithfulness to the KG, not world truth. Facts the KG contradicts itself on
are excluded rather than guessed. Four strata:
  single_fact / multi_hop  gold is in the KG
  text_only                gold is an inflection from Wiktionary that the KG lacks, so
                           KG-on should not help; a drop there means the KG distracts
  adversarial              non-words and false premises; a KG can make a model answer
                           what it should refuse
Vietnamese glosses carry gold.external.status: "confirmed" when Wiktionary lists the
same word, else "unchecked". Run crawl_wiktionary_reference.py first for that.

Output: data/eval/kg_grounded_qa.jsonl + kg_grounded_qa.manifest.json
"""
import collections
import gzip
import hashlib
import json
import os
import random
import re
import unicodedata
from typing import Dict, Iterable, List, Set, Tuple

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
OUT_ITEMS = os.path.join(DATA, "eval", "kg_grounded_qa.jsonl")
OUT_MANIFEST = os.path.join(DATA, "eval", "kg_grounded_qa.manifest.json")
SEED = 20261111
BUILDER_VERSION = "2"

# Same order as kg_service_v3._RUNTIME_KG_SOURCE_FILES (legacy file first).
KG_FILES = ["knowledge_extended.json"] + [
    f"kg/{n}"
    for n in (
        "01_grammar_gaps.json", "02_functional_language.json", "03_errors_vietnamese.json",
        "04_writing_phonology.json", "05_vocabulary_advanced.json",
        "06_tracecag_topic_expansion.json", "seed_graph.json", "07_vocabulary_anki.json",
        "08_cefr_sentences.json", "09_grammar_usage.json", "10_collocations.json",
        "11_idioms.json", "12_lexical_relations.json", "13_cefrj_vocabulary.json",
    )
]
# Hand-written curriculum graph: the only part with pedagogical edges.
CURATED_FILES = KG_FILES[:6] + ["kg/seed_graph.json"]
VOCAB_FILE = "kg/07_vocabulary_anki.json"

LEVELS = ["A1", "A2", "B1", "B2", "C1", "C2"]
RANK = {lv: i for i, lv in enumerate(LEVELS)}
VI_CHARS = re.compile(
    r"[àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ]", re.I
)
WORD = re.compile(r"^[a-z]{3,}$")
# Prerequisite direction: (before, after).
PREREQ_RELATIONS = {"prerequisite_of": lambda a, b: (a, b), "builds_on": lambda a, b: (b, a)}
ERROR_RELATIONS = {"related_to", "corrects"}

QUOTAS = {
    "cefr_level": 300, "vi_gloss": 300, "concept_level": 80,
    "cefr_comparison": 200,                                        # plus every prerequisite/error item the KG has
    "text_only": 300,                                              # split by form below
    "nonword_cefr": 100, "nonword_meaning": 100,
    "false_premise_cefr": 150, "false_premise_prereq": 40,
}
WIKT = os.path.join(DATA, "corpora", "wiktionary_reference", "entries.jsonl")
LEXICON = os.path.join(DATA, "lexicon", "cefr_vocabulary.jsonl")
CEFRJ_EXT = {"status": "confirmed", "source": "CEFR-J Wordlist 1.5 / Octanove C1C2 1.0", "license": "free with citation / CC BY-SA 4.0"}
TEXT_ONLY_PER_FORM = {("Noun", "plural"): 100, ("Verb", "simple_past"): 70, ("Verb", "past_participle"): 70, ("Adjective", "comparative"): 60}
FORM_QUESTIONS = {
    ("Noun", "plural"): ("Dạng số nhiều của danh từ '{w}' là gì?", "What is the plural of the noun '{w}'?"),
    ("Verb", "simple_past"): ("Dạng quá khứ đơn của động từ '{w}' là gì?", "What is the simple past of the verb '{w}'?"),
    ("Verb", "past_participle"): ("Dạng phân từ quá khứ (V3) của động từ '{w}' là gì?",
                                  "What is the past participle of the verb '{w}'?"),
    ("Adjective", "comparative"): ("Dạng so sánh hơn của tính từ '{w}' là gì?",
                                   "What is the comparative form of the adjective '{w}'?"),
}
SENSE_STARTS = {
    "Verb": ("to ",),
    "Noun": ("a ", "an ", "the ", "someone", "something", "one who", "one of"),
    "Adjective": ("having", "being", "not ", "very", "relating", "full of", "able to", "causing", "feeling"),
}


def sense_matches(pos: str, kg_definition: str) -> bool:
    """The KG's English definition names the sense the question is about (verb 'to ...', noun 'a ...')."""
    d = kg_definition.lower().strip()
    return d.startswith(SENSE_STARTS.get(pos, ())) and (pos == "Verb" or not d.startswith("to "))


def is_regular(word: str, form: str) -> bool:
    stem_y = word[:-1] if word.endswith("y") else word
    return form in {word + "s", word + "es", stem_y + "ies", word + "ed", word + "d", stem_y + "ied",
                    word + word[-1] + "ed", word + "er", word + "r", stem_y + "ier", word + word[-1] + "er"}




def load_kg(data_dir: str = DATA) -> Tuple[Dict[str, dict], Dict[str, List[str]], List[tuple]]:
    """Concepts (first file wins, as MERGE does), id → files, edges (s, o, rel, file)."""
    concepts: Dict[str, dict] = {}
    sources: Dict[str, List[str]] = collections.defaultdict(list)
    edges: List[tuple] = []
    for rel in KG_FILES:
        with open(os.path.join(data_dir, rel), encoding="utf-8") as fh:
            doc = json.load(fh)
        for c in doc.get("concepts", []):
            sources[c["id"]].append(rel)
            concepts.setdefault(c["id"], {**c, "_file": rel})
        edges += [(e["from"], e["to"], e.get("relation"), rel) for e in doc.get("edges", [])]
    return concepts, sources, edges


def kg_conflicts(data_dir: str, concepts: Dict[str, dict], edges: List[tuple]) -> Dict[str, str]:
    """Concept ids whose CEFR level the KG states two different ways → reason."""
    out: Dict[str, str] = {}
    levels: Dict[str, Set[str]] = collections.defaultdict(set)
    for rel in KG_FILES:
        with open(os.path.join(data_dir, rel), encoding="utf-8") as fh:
            for c in json.load(fh).get("concepts", []):
                if c.get("level"):
                    levels[c["id"]].add(c["level"])
    for cid, lv in levels.items():
        if len(lv) > 1:
            out[cid] = f"level differs across files: {sorted(lv)}"
    for s, o, rel, f in edges:
        if s.startswith("cefrlevel:") and o in concepts:
            if concepts[o].get("level", "").lower() != s.split(":")[1]:
                out[o] = f"{f}: {s} -[{rel}]-> node whose level is {concepts[o].get('level')}"
    by_title: Dict[str, List[str]] = collections.defaultdict(list)
    for cid, c in concepts.items():
        by_title[c["title"].strip().lower()].append(cid)
    for title, ids in by_title.items():
        # Only single words can make a vocabulary question ambiguous; templated
        # story nodes ("account collocation") repeat per story by design.
        if not WORD.match(title):
            continue
        lv = {concepts[i].get("level") for i in ids if concepts[i].get("level")}
        if len(lv) > 1:
            for i in ids:
                out[i] = f"title '{title}' has levels {sorted(lv)}"
    return out


def split_gloss(keywords: str) -> Tuple[str, List[str]]:
    """'english def,vi1, vi2' → (def, [vi1, vi2]); ([], …) when the split is ambiguous."""
    segs = [s.strip() for s in keywords.split(",") if s.strip()]
    if len(segs) < 2 or VI_CHARS.search(segs[0]):
        return "", []
    vi = segs[1:]
    if not all(VI_CHARS.search(s) for s in vi):
        return "", []  # an English comma leaked into the gloss list
    return segs[0], vi


def dictionary_words(data_dir: str = DATA) -> Set[str]:
    words: Set[str] = set()
    if os.path.exists("/usr/share/dict/words"):
        with open("/usr/share/dict/words", encoding="utf-8", errors="ignore") as fh:
            words |= {w.strip().lower() for w in fh}
    etl = os.path.join(os.path.dirname(data_dir), "content_etl_data", "raw")
    for dirpath, _, files in os.walk(os.path.join(etl, "cmudict")):
        for f in files:
            if f.endswith(".dict"):
                with open(os.path.join(dirpath, f), encoding="utf-8", errors="ignore") as fh:
                    words |= {re.sub(r"\(\d+\)$", "", ln.split(" ", 1)[0]).lower() for ln in fh if ln.strip()}
    for dirpath, _, files in os.walk(os.path.join(etl, "oewn")):
        for f in files:
            if f.endswith(".xml.gz"):
                with gzip.open(os.path.join(dirpath, f), "rt", encoding="utf-8") as fh:
                    words |= {m.lower() for m in re.findall(r'writtenForm="([^"]+)"', fh.read())}
    return words


def make_nonwords(n: int, banned: Set[str], rng: random.Random) -> List[str]:
    onsets = ["b", "bl", "br", "d", "dr", "f", "fl", "fr", "g", "gl", "gr", "k", "kl", "m", "n",
              "p", "pl", "pr", "s", "sk", "sl", "sn", "st", "t", "tr", "v", "z"]
    vowels = ["a", "e", "i", "o", "u", "ai", "ee", "oo", "ou"]
    codas = ["", "b", "d", "g", "k", "m", "n", "p", "sh", "nd", "nt", "sk", "st", "x"]
    out: List[str] = []
    while len(out) < n:
        w = "".join(rng.choice(onsets) + rng.choice(vowels) for _ in range(rng.choice((2, 3))))
        w += rng.choice(codas)
        if w not in banned and w not in out and 5 <= len(w) <= 11:
            out.append(w)
    return out


def vocab_pool(concepts: Dict[str, dict], conflicts: Dict[str, str],
               title_count: Dict[str, int], dict_words: Set[str]) -> List[dict]:
    """Words a question may safely be about: single word, unique title, real word, one level."""
    return sorted(
        (c for c in concepts.values()
         if c["_file"] == VOCAB_FILE and c.get("level") in RANK and WORD.match(c["title"])
         and title_count[c["title"].lower()] == 1 and c["id"] not in conflicts
         and (not dict_words or c["title"] in dict_words)),
        key=lambda c: c["id"],
    )


def reference_words(per_level: int, data_dir: str = DATA, seed: int = SEED) -> List[dict]:
    """The words worth an external lookup: same pool the questions draw from, balanced by level."""
    concepts, _, edges = load_kg(data_dir)
    conflicts = kg_conflicts(data_dir, concepts, edges)
    counts = collections.Counter(c["title"].strip().lower() for c in concepts.values())
    pool = vocab_pool(concepts, conflicts, counts, dictionary_words(data_dir))
    rng = random.Random(seed ^ 0x57494B49)
    out: List[dict] = []
    for lv in LEVELS:
        at = [c for c in pool if c["level"] == lv]
        out += sorted(rng.sample(at, min(per_level, len(at))), key=lambda c: c["id"])
    return out


def norm_vi(text: str) -> str:
    return unicodedata.normalize("NFC", text).strip().lower()


KAIKKI = os.path.join(DATA, "corpora", "kaikki_reference", "entries.jsonl")
KAIKKI_POS = {"noun": "Noun", "verb": "Verb", "adj": "Adjective"}
_SKIP_TAGS = {"obsolete", "archaic", "rare", "dialectal", "nonstandard", "dated", "informal", "alternative", "misspelling", "proscribed"}


def _kaikki_forms(entry: dict, pos: str) -> Dict[str, List[str]]:
    """Inflections a Wiktextract entry states without a caveat: the form's tags must be exactly the ones named."""
    wanted = {"Noun": {"plural": {"plural"}}, "Verb": {"simple_past": {"past"}, "past_participle": {"participle", "past"}},
              "Adjective": {"comparative": {"comparative"}}}[pos]
    out: Dict[str, List[str]] = {}
    for f in entry["forms"]:
        tags, form = set(f["tags"]), f["form"].lower()
        if tags & _SKIP_TAGS or not re.fullmatch(r"[a-z]+(?:[' -][a-z]+)*", form):
            continue
        for name, want in wanted.items():
            if tags == want and form not in out.get(name, []):
                out.setdefault(name, []).append(form)
    return out


def load_wiktionary() -> Dict[str, dict]:
    """word -> {url, license, vi_translations, pos: {Noun|Verb|Adjective: {forms, definitions}}}, merged from the two Wiktionary extractions.

    kaikki.org (Wiktextract, every word) wins for inflections; the Firecrawl pages (a subset) add Vietnamese translations the
    other lacks. Both are English Wiktionary, CC BY-SA 4.0.
    """
    out: Dict[str, dict] = {}
    if os.path.exists(WIKT):
        with open(WIKT, encoding="utf-8") as fh:
            out = {e["word"]: e for e in map(json.loads, fh)}
    if os.path.exists(KAIKKI):
        with open(KAIKKI, encoding="utf-8") as fh:
            for rec in map(json.loads, fh):
                if not rec["found"] or not rec["entries"]:
                    continue
                word = rec["word"]
                base = out.setdefault(word, {"word": word, "url": f"https://en.wiktionary.org/wiki/{word}", "license": "CC BY-SA 4.0 (en.wiktionary.org via kaikki.org)",
                                             "pos": {}, "vi_translations": []})
                for v in (t["word"] for e in rec["entries"] for t in e["vi"]):
                    if unicodedata.normalize("NFC", v) not in base["vi_translations"]:
                        base["vi_translations"].append(unicodedata.normalize("NFC", v))
                pos_map: Dict[str, dict] = {}
                for e in rec["entries"]:
                    name = KAIKKI_POS.get(e["pos"] or "")
                    if name and name not in pos_map:   # the first entry of a part of speech is its commonest sense
                        pos_map[name] = {"forms": _kaikki_forms(e, name), "definitions": e["glosses"]}
                if pos_map:
                    base["pos"] = pos_map
    return out


def load_lexicon() -> Dict[str, Set[str]]:
    """word (any spelling) -> every CEFR level the reference lexicon gives it."""
    if not os.path.exists(LEXICON):
        return {}
    out: Dict[str, Set[str]] = collections.defaultdict(set)
    with open(LEXICON, encoding="utf-8") as fh:
        for line in fh:
            r = json.loads(line)
            for form in r["variants"]:
                out[form.lower()].add(r["cefr"])
    return out


def triple(s: str, p: str, o: str, source: str) -> dict:
    return {"s": s, "p": p, "o": o, "source": source}


def build(data_dir: str = DATA, seed: int = SEED, dict_words: Iterable[str] = ()) -> Tuple[List[dict], dict]:
    rng = random.Random(seed)
    concepts, sources, edges = load_kg(data_dir)
    conflicts = kg_conflicts(data_dir, concepts, edges)
    dict_words = set(dict_words)
    title_count = collections.Counter(c["title"].strip().lower() for c in concepts.values())
    items: List[dict] = []

    def add(stratum: str, qtype: str, q_vi: str, q_en: str, behavior: str, gold: dict, triples: List[dict],
            from_kg: bool = True) -> None:
        items.append({
            "stratum": stratum, "type": qtype, "question": q_vi, "question_en": q_en,
            "answerable_from_kg": behavior != "abstain" and from_kg, "expected_behavior": behavior,
            "gold": gold, "gold_triples": triples,
        })

    vocab = vocab_pool(concepts, conflicts, title_count, dict_words)
    lexicon = load_lexicon()
    # CEFR questions use only words the KG and an independent lexicon place at the same level
    cefr_vocab = [c for c in vocab if lexicon.get(c["title"].lower()) == {c["level"]}] if lexicon else vocab
    by_level: Dict[str, List[dict]] = collections.defaultdict(list)
    for c in cefr_vocab:
        by_level[c["level"]].append(c)
    refs = load_wiktionary()
    used: Dict[str, Set[str]] = collections.defaultdict(set)

    def draw(pool: List[dict], k: int, kind: str) -> List[dict]:
        """Sample without repeating a word inside one question type (types may share words)."""
        free = [c for c in pool if c["id"] not in used[kind]]
        picked = rng.sample(free, min(k, len(free)))
        used[kind].update(c["id"] for c in picked)
        return picked

    # single_fact: CEFR level, balanced across levels (C2 is small, gives what it has)
    per = QUOTAS["cefr_level"] // len(LEVELS)
    cefr_pick: List[dict] = []
    for lv in LEVELS:
        cefr_pick += draw(by_level[lv], per, "cefr")
    cefr_pick += draw(cefr_vocab, QUOTAS["cefr_level"] - len(cefr_pick), "cefr")
    for c in cefr_pick:
        add("single_fact", "cefr_level",
            f"Từ tiếng Anh '{c['title']}' thuộc trình độ CEFR nào?",
            f"What CEFR level is the English word '{c['title']}'?",
            "answer", {"answer": c["level"], "match": "exact_label", "external": CEFRJ_EXT if lexicon else {"status": "unchecked"}},
            [triple(c["id"], "has_cefr_level", c["level"], VOCAB_FILE)])

    glossable = [c for c in vocab if split_gloss(c["keywords"])[1]]
    gloss_status: Dict[str, str] = {}
    disagree: List[str] = []
    for c in glossable:
        entry = refs.get(c["title"])
        vi = split_gloss(c["keywords"])[1]
        if not entry or not entry["vi_translations"]:
            gloss_status[c["id"]] = "unchecked"
        elif {norm_vi(v) for v in vi} & {norm_vi(v) for v in entry["vi_translations"]}:
            gloss_status[c["id"]] = "confirmed"
        else:
            gloss_status[c["id"]] = "not_confirmed"  # Wiktionary is incomplete or on another sense: it cannot refute the KG
            disagree.append(c["title"])
    confirmed = [c for c in glossable if gloss_status[c["id"]] == "confirmed"]
    unchecked = [c for c in glossable if gloss_status[c["id"]] == "unchecked"]
    gloss_pick = draw(confirmed, QUOTAS["vi_gloss"], "gloss")
    gloss_pick += draw(unchecked, QUOTAS["vi_gloss"] - len(gloss_pick), "gloss")
    for c in gloss_pick:
        _, vi = split_gloss(c["keywords"])
        ext = {"status": gloss_status[c["id"]]}
        if ext["status"] == "confirmed":
            ext.update(source=refs[c["title"]]["url"], license=refs[c["title"]]["license"])
        add("single_fact", "vi_gloss",
            f"Từ '{c['title']}' trong tiếng Việt nghĩa là gì?",
            f"What does the English word '{c['title']}' mean in Vietnamese?",
            "answer", {"answer": vi[0], "aliases": vi, "match": "any_alias", "external": ext},
            [triple(c["id"], "translates_to", v, VOCAB_FILE) for v in vi])

    # text_only: the answer is a headword-line inflection; check the KG really lacks it
    kg_text = {c["title"]: (c["title"] + " " + c.get("keywords", "")).lower() for c in vocab}
    kg_def = {c["title"]: split_gloss(c["keywords"])[0] or c["keywords"] for c in vocab}
    form_items = []
    for word in sorted(refs):
        if word not in kg_text:
            continue
        if not refs[word]["pos"]:
            continue   # an adverb or particle: no noun, verb or adjective inflection to ask about
        primary = next(iter(refs[word]["pos"]))  # a secondary part of speech makes odd questions ("plural of the noun hey")
        for pos, data in refs[word]["pos"].items():
            if pos != primary:
                continue
            for form, alts in data["forms"].items():
                q = FORM_QUESTIONS.get((pos, form))
                if (not q or not sense_matches(pos, kg_def[word])
                        or any(re.search(rf"\b{re.escape(a)}\b", kg_text[word]) for a in alts)):
                    continue
                if any(a.startswith(("more ", "most ")) for a in alts):
                    continue   # "more contagious": regular and uninformative
                irregular = not any(is_regular(word, a) for a in alts)
                form_items.append((word, pos, form, alts, q, irregular, refs[word]))
    rng.shuffle(form_items)
    chosen_forms: List[tuple] = []
    for bucket, quota in TEXT_ONLY_PER_FORM.items():
        mine = sorted((t for t in form_items if (t[1], t[2]) == bucket), key=lambda t: not t[5])   # irregular first: -s/-ed is too easy to guess
        chosen_forms += mine[:quota]
    for word, pos, form, alts, q, irregular, ref in chosen_forms:
        add("text_only", f"{pos.lower()}_{form}", q[0].format(w=word), q[1].format(w=word),
            "answer", {"answer": alts[0], "aliases": alts, "match": "any_alias", "irregular": irregular,
                       "external": {"status": "reference_only", "source": ref["url"], "license": ref["license"]}},
            [], from_kg=False)

    curated_ids = {cid for cid, c in concepts.items() if c["_file"] in CURATED_FILES}
    curated_lv = sorted(
        (concepts[i] for i in curated_ids
         if concepts[i].get("level") in RANK and i not in conflicts and len(sources[i]) == 1
         and i.split(":")[1].startswith(("grammar.", "function."))),
        key=lambda c: c["id"],
    )
    for c in rng.sample(curated_lv, min(QUOTAS["concept_level"], len(curated_lv))):
        add("single_fact", "concept_level",
            f"Chủ điểm '{c['title']}' thường được dạy ở trình độ CEFR nào?",
            f"At what CEFR level is '{c['title']}' usually taught?",
            "answer", {"answer": c["level"], "match": "exact_label"},
            [triple(c["id"], "has_cefr_level", c["level"], c["_file"])])

    # ── multi_hop ──
    curated_edges = {(s, o, r, f) for s, o, r, f in edges if f in CURATED_FILES}
    before: Dict[str, Dict[str, tuple]] = collections.defaultdict(dict)  # after → {before: edge}
    for s, o, r, f in sorted(curated_edges):
        if r in PREREQ_RELATIONS and s in concepts and o in concepts:
            b, a = PREREQ_RELATIONS[r](s, o)
            if RANK.get(concepts[b].get("level"), 0) > RANK.get(concepts[a].get("level"), 9):
                # Harder topic "before" an easier one: the edge was most likely
                # written backwards, so the gold order is not trustworthy.
                conflicts[f"{s} -[{r}]-> {o}"] = (
                    f"{f}: puts {concepts[b].get('level')} before {concepts[a].get('level')}")
                continue
            before[a].setdefault(b, (s, r, o, f))
    for a in sorted(before):
        prs = before[a]
        add("multi_hop", "prereq_direct",
            f"Trước khi học '{concepts[a]['title']}', người học nên nắm vững chủ điểm nào?",
            f"What should a learner master before studying '{concepts[a]['title']}'?",
            "answer", {"answer_set": sorted(concepts[b]["title"] for b in prs),
                       "answer_ids": sorted(prs), "match": "any_of_set"},
            [triple(s, r, o, f) for s, r, o, f in prs.values()])
    for a in sorted(before):
        hops = {(b, bb) for b in before[a] for bb in before.get(b, {}) if bb != a}
        if not hops:
            continue
        add("multi_hop", "prereq_2hop",
            f"'{concepts[a]['title']}' cần một chủ điểm nền tảng, và chủ điểm đó lại cần một chủ điểm "
            f"nền tảng khác. Chủ điểm ở hai bậc trước '{concepts[a]['title']}' là gì?",
            f"'{concepts[a]['title']}' builds on a topic that itself builds on another. "
            f"What is a topic two steps before '{concepts[a]['title']}'?",
            "answer", {"answer_set": sorted({concepts[bb]["title"] for _, bb in hops}),
                       "answer_ids": sorted({bb for _, bb in hops}), "match": "any_of_set"},
            [triple(*before[a][b][:3], before[a][b][3]) for b, _ in sorted(hops)]
            + [triple(*before[b][bb][:3], before[b][bb][3]) for b, bb in sorted(hops)])
    err_links: Dict[str, Dict[str, tuple]] = collections.defaultdict(dict)
    for s, o, r, f in sorted(curated_edges):
        if (r in ERROR_RELATIONS and s.startswith("concept:error.") and o.startswith("concept:grammar.")
                and s in concepts and o in concepts):
            err_links[s].setdefault(o, (s, r, o, f))
    for e in sorted(err_links):
        links = err_links[e]
        add("multi_hop", "error_concept",
            f"Lỗi '{concepts[e]['title']}' của người học Việt Nam liên quan tới chủ điểm ngữ pháp nào?",
            f"Which grammar topic is the Vietnamese-learner error '{concepts[e]['title']}' linked to?",
            "answer", {"answer_set": sorted(concepts[o]["title"] for o in links),
                       "answer_ids": sorted(links), "match": "any_of_set"},
            [triple(s, r, o, f) for s, r, o, f in links.values()])
    made, tries, seen_pairs = 0, 0, set()
    while made < QUOTAS["cefr_comparison"] and tries < 50 * QUOTAS["cefr_comparison"]:
        tries += 1
        x, y = rng.sample(cefr_vocab, 2)
        key = tuple(sorted((x["id"], y["id"])))
        if abs(RANK[x["level"]] - RANK[y["level"]]) < 2 or key in seen_pairs:  # skip borderline pairs
            continue
        seen_pairs.add(key)
        harder = max((x, y), key=lambda c: RANK[c["level"]])
        add("multi_hop", "cefr_comparison",
            f"Theo khung CEFR, từ nào khó hơn: '{x['title']}' hay '{y['title']}'?",
            f"By CEFR level, which word is harder: '{x['title']}' or '{y['title']}'?",
            "answer", {"answer": harder["title"], "match": "exact_label"},
            [triple(c["id"], "has_cefr_level", c["level"], VOCAB_FILE) for c in (x, y)])
        made += 1

    # ── adversarial ──
    banned = dict_words | set(title_count)
    nonwords = make_nonwords(QUOTAS["nonword_cefr"] + QUOTAS["nonword_meaning"], banned, rng)
    for w in nonwords[: QUOTAS["nonword_cefr"]]:
        add("adversarial", "nonword_cefr",
            f"Từ tiếng Anh '{w}' thuộc trình độ CEFR nào?",
            f"What CEFR level is the English word '{w}'?",
            "abstain", {"answer": None, "match": "abstain", "nonword": w}, [])
    for w in nonwords[QUOTAS["nonword_cefr"]:]:
        add("adversarial", "nonword_meaning",
            f"Từ '{w}' trong tiếng Việt nghĩa là gì?",
            f"What does the English word '{w}' mean in Vietnamese?",
            "abstain", {"answer": None, "match": "abstain", "nonword": w}, [])
    fp_pool = [c for c in cefr_vocab if c["level"] in ("A1", "A2", "C1", "C2")]
    for c in draw(fp_pool, QUOTAS["false_premise_cefr"], "false_premise"):
        claimed = "C2" if RANK[c["level"]] <= 1 else "A1"
        add("adversarial", "false_premise_cefr",
            f"Vì sao từ '{c['title']}' được xếp ở trình độ {claimed}?",
            f"Why is the word '{c['title']}' classified as {claimed}?",
            "correct_premise", {"answer": c["level"], "false_claim": claimed, "match": "exact_label"},
            [triple(c["id"], "has_cefr_level", c["level"], VOCAB_FILE)])
    pairs = sorted((b, a) for a in before for b in before[a])
    for b, a in rng.sample(pairs, min(QUOTAS["false_premise_prereq"], len(pairs))):
        s, r, o, f = before[a][b]
        add("adversarial", "false_premise_prereq",
            f"Vì sao phải học '{concepts[a]['title']}' trước rồi mới học '{concepts[b]['title']}'?",
            f"Why must '{concepts[a]['title']}' be learned before '{concepts[b]['title']}'?",
            "correct_premise",
            {"answer": f"{concepts[b]['title']} → {concepts[a]['title']}",
             "correct_order_ids": [b, a], "match": "order"},
            [triple(s, r, o, f)])

    for i, it in enumerate(items, 1):
        it["id"] = f"kgqa-{i:04d}"
    hashes = {}
    for rel in KG_FILES:
        with open(os.path.join(data_dir, rel), "rb") as fh:
            hashes[rel] = hashlib.sha256(fh.read()).hexdigest()
    manifest = {
        "name": "kg_grounded_qa", "builder": "scripts/build_kg_grounded_eval.py",
        "builder_version": BUILDER_VERSION, "seed": seed,
        "gold_source": "runtime KG source files (single_fact, multi_hop, adversarial); "
                       "en.wiktionary.org inflections for text_only. Measures faithfulness to the KG, not world truth",
        "external_reference": {
            "file": os.path.relpath(WIKT, DATA) if refs else None, "entries": len(refs),
            "vi_gloss_status": dict(collections.Counter(it["gold"]["external"]["status"]
                                                        for it in items if it["type"] == "vi_gloss")),
            "kg_gloss_vs_wiktionary": dict(collections.Counter(gloss_status.values())),
            "not_confirmed_words": sorted(disagree),
        },
        "cefr_reference": {
            "file": os.path.relpath(LEXICON, DATA) if lexicon else None,
            "kg_words_in_lexicon": sum(1 for c in vocab if c["title"].lower() in lexicon),
            "kg_and_lexicon_agree": len(cefr_vocab) if lexicon else None,
            "agreeing_words_per_level": dict(sorted(collections.Counter(c["level"] for c in cefr_vocab).items())),
        },
        "cefr_level_by_gold": dict(sorted(collections.Counter(
            it["gold"]["answer"] for it in items if it["type"] == "cefr_level").items())),
        "counts": dict(collections.Counter(it["stratum"] for it in items)),
        "type_counts": dict(collections.Counter(it["type"] for it in items)),
        "nonwords_checked_against": {"dictionary_words": len(dict_words), "kg_titles": len(title_count)},
        "kg_conflicts_excluded": dict(sorted(conflicts.items())),
        "kg_sha256": hashes,
        "match_rules": {
            "exact_label": "normalised answer equals gold.answer",
            "any_alias": "answer contains any gold.aliases entry; a miss needs a judge (valid synonyms exist)",
            "any_of_set": "answer names at least one gold.answer_set entry; report recall over the set too",
            "abstain": "answer declines or flags the word as unknown; any CEFR label or gloss is a hallucination",
            "order": "answer rejects the stated order and gives correct_order_ids order",
        },
    }
    return items, manifest


def main() -> None:
    words = dictionary_words()
    items, manifest = build(dict_words=words)
    with open(OUT_ITEMS, "w", encoding="utf-8") as fh:
        for it in items:
            fh.write(json.dumps(it, ensure_ascii=False) + "\n")
    with open(OUT_ITEMS, "rb") as fh:
        manifest["items_sha256"] = hashlib.sha256(fh.read()).hexdigest()
    with open(OUT_MANIFEST, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, ensure_ascii=False, indent=2)
    print(json.dumps({k: manifest[k] for k in ("counts", "type_counts")}, indent=2))
    print(f"excluded {len(manifest['kg_conflicts_excluded'])} conflicting KG facts; "
          f"dictionary size {len(words)}")


if __name__ == "__main__":
    main()
