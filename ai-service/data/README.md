# ai-service/data

What is here, what reads it, and how to rebuild it. Sizes, hashes, licences and usage gates are in `MANIFEST.json`
(`python scripts/build_data_manifest.py`).

| Path | What | Read by | Rebuild |
|---|---|---|---|
| `kg/*.json`, `knowledge_extended.json` | Runtime knowledge graph sources (18,320 concepts incl. file 13's 3,191 CEFR-J words; 55.5k edges after the noise filter) | `KnowledgeGraphServiceV3` at startup | hand-written + imports; `06_*` from `scripts/generate_tracecag_topic_corpus.py` |
| `kuzu_runtime.db*` | Kuzu database built from the sources above | ai-service | `scripts/rebuild_runtime_kg.py` — **editing `kg/` does not update it**, rebuild first |
| `sample_stories.json`, `topic_graphs*.json` | Topic stories and graphs | `seed_stories.py`, `import_knowledge.py`, tests | — |
| `external_docs/` | Documents the document-intelligence service ingests | `Dockerfile`, `document_intelligence.py` | — |
| `eval/kg_grounded_qa.jsonl` (+`.manifest.json`) | 1,641 questions with gold from the KG / Wiktionary: does the KG reduce hallucination | experiments, `tests/test_kg_grounded_eval_set.py` | `scripts/build_kg_grounded_eval.py` |
| `eval/topic_paraphrases.json` | 60 topics x learner phrasings, for retrieval/answer-quality evals | `scripts/eval_*.py` | — |
| `corpora/gec_pairs/` | Full JFLEG, 4 references per sentence, `has_error` flag | GEC / false-flag tests | `scripts/fetch_hf_corpora.py` |
| `corpora/parallel_en_vi/` | OPUS-100 en-vi, noise-filtered | translation evals | `scripts/fetch_hf_corpora.py` |
| `corpora/wiktionary_reference/` | Independent reference: Vietnamese translations, inflections, definitions | eval builder | `scripts/crawl_wiktionary_reference.py` (Firecrawl, ~1 credit/word) |
| `lexicon/` | CEFR reference lexicon (9,935 word rows A1-C2) and CEFR-J grammar profile (500 rows, 170 with a level) | eval builder; available to the app | `scripts/build_cefr_lexicon.py --fetch` |
| `corpora/kaikki_reference/` | Structured English Wiktionary entries for 9,997 words (definitions, Vietnamese, inflections, IPA) | eval builder, `kg/13` builder | `scripts/crawl_kaikki_reference.py` (resumes) |
| `corpora/cefr_profiles/` | Unmodified CEFR-J / Octanove CSVs behind `lexicon/` | provenance | same script |
| `corpora/_provenance/` | Reports from the original Hugging Face staging builds (licences, row ranges) | humans | — |
| `kg_output/*/*_report.json` | Generator reports | tests | — |

## Order to rebuild the eval set

```
python scripts/crawl_wiktionary_reference.py crawl --per-level 80   # skips cached pages; parse re-extracts for free
python scripts/build_kg_grounded_eval.py
python scripts/build_data_manifest.py
venv/bin/python -m pytest tests/test_kg_grounded_eval_set.py
```

## Licences that limit use

The app is a non-commercial thesis, so NC data is fine to use; see `ATTRIBUTION.md` for the credits and for what to remove before any commercial release.
The Docker image excludes `corpora/`, `eval/` and the docs (`.dockerignore`); `kg/` and `lexicon/` ship.

`gec_pairs` and `kg/08_cefr_sentences.json` are CC BY-NC-SA 4.0; `parallel_en_vi` is unaudited; `kg/09_grammar_usage.json`
has no declared licence; Wiktionary text is CC BY-SA 4.0 (attribute, share alike). Research use is fine; check
`MANIFEST.json` before shipping any of it inside the app.

## What the eval set measures, and what it does not

Gold for `single_fact`, `multi_hop` and `adversarial` is what the KG says, so a high score means "faithful to the KG",
not "true". `text_only` gold comes from Wiktionary and is absent from the KG: KG-on should not change it, so a drop there
means the KG is distracting the model. A wrong fact the KG and the model both repeat scores as correct. Only 6 of the 271 `text_only` items are irregular forms, so that stratum is a weak distraction test; read it as a sanity control.

Known KG defects found while building it are in `eval/kg_grounded_qa.manifest.json` under `kg_conflicts_excluded`
(499 words whose title appears at several CEFR levels, 4 concepts with different levels across files, 3 prerequisite
edges written backwards, 2 CEFR edges that contradict the node). They are excluded from the eval, not fixed in `kg/`:
changing those files without rebuilding the Kuzu database would leave the two inconsistent and change the KG version
that earlier results were measured against.
