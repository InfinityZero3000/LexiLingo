"""Write data/MANIFEST.json: what every dataset under ai-service/data is, where it came from, how big, and what may be done with it.

Usage:  python scripts/build_data_manifest.py
Counts and hashes are measured; licence and gate text is the one hand-kept part, so a new dataset must be added to SOURCES.
"""
import hashlib
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")

SOURCES = {
    "kg/07_vocabulary_anki.json": ("runtime KG", "Alex123321/english_cefr_dataset + LexiLingo Anki deck", "Apache-2.0", "ok"),
    "kg/08_cefr_sentences.json": ("runtime KG", "UniversalCEFR/cefr_sp_en", "CC BY-NC-SA 4.0", "thesis: ok (non-commercial). Before any commercial release: remove or relicense"),
    "kg/09_grammar_usage.json": ("runtime KG", "Teravee/1000_english-grammar-dataset", "undeclared", "thesis: ok (non-commercial). Before any commercial release: get the licence or remove"),
    "kg/10_collocations.json": ("runtime KG", "vladvlasov256/opensubs-collocations", "CC-BY-4.0", "ok, attribute"),
    "kg/11_idioms.json": ("runtime KG", "adihaviv/idiomem", "MIT", "ok"),
    "kg/12_lexical_relations.json": ("runtime KG", "ConceptNet 5 via appledora/conceptnet_en2en_relations", "CC BY 4.0", "ok, attribute"),
    "kg/06_tracecag_topic_expansion.json": ("runtime KG", "scripts/generate_tracecag_topic_corpus.py (deterministic)", "project-owned", "ok"),
    "kg/seed_graph.json": ("runtime KG", "hand-written curriculum", "project-owned", "ok"),
    "kg/01_grammar_gaps.json": ("runtime KG", "hand-written curriculum", "project-owned", "ok"),
    "kg/02_functional_language.json": ("runtime KG", "hand-written curriculum", "project-owned", "ok"),
    "kg/03_errors_vietnamese.json": ("runtime KG", "hand-written Vietnamese-learner error taxonomy", "project-owned", "ok"),
    "kg/04_writing_phonology.json": ("runtime KG", "hand-written curriculum", "project-owned", "ok"),
    "kg/05_vocabulary_advanced.json": ("runtime KG", "hand-written curriculum", "project-owned", "ok"),
    "kg/13_cefrj_vocabulary.json": ("runtime KG", "CEFR-J 1.5 / Octanove C1C2 1.0 words absent from the other files; definitions and Vietnamese from en.wiktionary.org via kaikki.org", "CEFR-J: free with citation; Octanove and Wiktionary: CC BY-SA 4.0", "ok; cite and share alike (see data/ATTRIBUTION.md)"),
    "corpora/kaikki_reference/entries.jsonl": ("corpus", "en.wiktionary.org structured extraction (Wiktextract) from kaikki.org, 9,997 words", "CC BY-SA 4.0", "reference for eval and for file 13; excluded from the Docker image"),
    "knowledge_extended.json": ("runtime KG", "hand-written curriculum (legacy file)", "project-owned", "ok"),
    "corpora/gec_pairs/gec_pairs.jsonl": ("corpus", "jhu-clsp/jfleg (validation + test, 4 references each)", "CC BY-NC-SA 4.0", "research only; excluded from the Docker image (.dockerignore)"),
    "corpora/parallel_en_vi/pairs.jsonl": ("corpus", "Helsinki-NLP/opus-100 en-vi, first 20,000 train rows, noise-filtered", "unknown (OPUS subtitles)", "research only; excluded from the Docker image (.dockerignore)"),
    "corpora/wiktionary_reference/entries.jsonl": ("corpus", "en.wiktionary.org via Firecrawl (scripts/crawl_wiktionary_reference.py)", "CC BY-SA 4.0", "attribute Wiktionary contributors; share-alike"),
    "lexicon/cefr_vocabulary.jsonl": ("lexicon", "CEFR-J Wordlist 1.5 (A1-B2) + Octanove Vocabulary Profile C1/C2 1.0, via openlanguageprofiles/olp-en-cefrj", "CEFR-J: free with citation; Octanove: CC BY-SA 4.0", "ok for app use; cite (see data/lexicon/README.md)"),
    "lexicon/cefrj_grammar_profile.jsonl": ("lexicon", "CEFR-J Grammar Profile 20180315", "free with citation", "ok for app use; cite (see data/lexicon/README.md)"),
    "eval/kg_grounded_qa.jsonl": ("eval", "scripts/build_kg_grounded_eval.py from the runtime KG + Wiktionary", "derived", "see kg_grounded_qa.manifest.json"),
    "eval/topic_paraphrases.json": ("eval", "LLM-written learner phrasings of 60 topics", "project-owned", "ok"),
}


def measure(path: str) -> dict:
    full = os.path.join(DATA, path)
    with open(full, "rb") as fh:
        raw = fh.read()
    out = {"bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()}
    if path.endswith(".jsonl"):
        out["records"] = raw.count(b"\n")
    elif path.endswith(".json"):
        doc = json.loads(raw)
        if isinstance(doc, dict) and ("concepts" in doc or "edges" in doc):
            out["concepts"], out["edges"] = len(doc.get("concepts", [])), len(doc.get("edges", []))
        elif isinstance(doc, list):
            out["records"] = len(doc)
    return out


def main() -> None:
    manifest = {"generated_by": "scripts/build_data_manifest.py", "datasets": {}}
    for path, (kind, source, licence, gate) in SOURCES.items():
        if os.path.exists(os.path.join(DATA, path)):
            manifest["datasets"][path] = {"kind": kind, "source": source, "licence": licence, "gate": gate, **measure(path)}
    with open(os.path.join(DATA, "MANIFEST.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, ensure_ascii=False, indent=2)
    print(f"{len(manifest['datasets'])} datasets recorded")


if __name__ == "__main__":
    main()
