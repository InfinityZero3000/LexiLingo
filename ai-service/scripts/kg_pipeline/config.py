"""Pipeline configuration — paths, URLs, rate limits."""

from pathlib import Path

# ── Paths ──────────────────────────────────────────────────────────────────
PIPELINE_DIR = Path(__file__).parent
AI_SERVICE_DIR = PIPELINE_DIR.parent.parent          # ai-service/
KG_DOMAIN_DIR = AI_SERVICE_DIR / "data" / "kg"      # existing domain JSON files
KG_RAW_DIR = AI_SERVICE_DIR / "data" / "kg_raw"     # pipeline output (CSV chunks)
KUZU_DB_PATH = AI_SERVICE_DIR / "models" / "kuzu_db"

# Intermediate CSV paths (written by crawlers, read by importer)
NODES_CSV = KG_RAW_DIR / "nodes.csv"
EDGES_CSV = KG_RAW_DIR / "edges.csv"

# Progress / checkpoint files
PROGRESS_DIR = KG_RAW_DIR / "progress"

# ── Wiktionary Kaikki dump ─────────────────────────────────────────────────
# Pre-extracted English Wiktionary JSON by kaikki.org (saves 8h of API calls)
# File: ~450 MB compressed, ~1.8 GB uncompressed, ~1.3M English entries
KAIKKI_DUMP_URL = "https://kaikki.org/dictionary/English/kaikki.org-dictionary-English.jsonl.gz"
KAIKKI_LOCAL = KG_RAW_DIR / "kaikki-english.jsonl.gz"

# ── CEFR word lists ────────────────────────────────────────────────────────
# CEFR-J from Tokyo University of Technology (CC BY-SA 4.0)
CEFR_J_URL = "https://raw.githubusercontent.com/leomauro/cefr-j/master/CEFRJ-level-master.csv"
CEFR_J_LOCAL = KG_RAW_DIR / "cefr_j.csv"

# Oxford 3000 + 5000 (JSON scraped from OUP open data)
OXFORD_LISTS_URL = "https://raw.githubusercontent.com/tyyppi77/oxford-learner-word-lists/main/oxford-5000.json"
OXFORD_LISTS_LOCAL = KG_RAW_DIR / "oxford_5000.json"

# ── Web crawler targets (Crawl4AI) ─────────────────────────────────────────
WEB_SOURCES = [
    {
        "name": "englishclub_phrasal_verbs",
        "url": "https://www.englishclub.com/vocabulary/phrasal-verbs-list.php",
        "type": "phrasal_verbs",
    },
    {
        "name": "englishclub_idioms_a",
        "url": "https://www.englishclub.com/ref/Idioms/",
        "type": "idioms",
    },
    {
        "name": "grammar_monster_index",
        "url": "https://www.grammar-monster.com/glossary/",
        "type": "grammar_glossary",
    },
    {
        "name": "bc_grammar_a1",
        "url": "https://learnenglish.britishcouncil.org/grammar/a1-a2-grammar",
        "type": "grammar_lessons",
    },
    {
        "name": "bc_grammar_b1",
        "url": "https://learnenglish.britishcouncil.org/grammar/b1-b2-grammar",
        "type": "grammar_lessons",
    },
    {
        "name": "englishclub_common_collocations",
        "url": "https://www.englishclub.com/vocabulary/collocations-list.php",
        "type": "collocations",
    },
    {
        "name": "perfect_english_grammar",
        "url": "https://www.perfect-english-grammar.com/",
        "type": "grammar",
    },
    {
        "name": "ielts_liz_vocabulary",
        "url": "https://ieltsliz.com/ielts-vocabulary/",
        "type": "ielts_vocab",
    },
    {
        "name": "voa_learning_words",
        "url": "https://learningenglish.voanews.com/",
        "type": "news_vocab",
    },
]

# ── Rate limits ────────────────────────────────────────────────────────────
WIKIMEDIA_RPS = 50          # requests per second (Wikimedia allows ~200)
CRAWL4AI_CONCURRENCY = 3    # parallel browser contexts (keep low on 4GB RAM)
CRAWL4AI_DELAY = 1.5        # seconds between requests to same domain

# ── Processing ─────────────────────────────────────────────────────────────
CSV_FLUSH_EVERY = 5_000     # flush writers every N rows (memory safety)
TARGET_NODES = 1_000_000

# ── WordNet POS codes ──────────────────────────────────────────────────────
WN_POS = {"n": "noun", "v": "verb", "a": "adj", "s": "adj_satellite", "r": "adv"}
