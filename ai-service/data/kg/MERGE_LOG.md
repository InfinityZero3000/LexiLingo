# Hugging Face KG Production Merge Log

Date: 2026-08-03

## Namespace remap and collision proof

The staged CSV files under `data/kg_output/hf_import_staging/` were read without modification. All 6,747 individual dictionary-word IDs from `merged_kg/nodes.csv` were remapped from `concept:vocab.<word>` to `concept:vocab.word.<word>`. The 1,250 `concept:phrase.*` sentence IDs were left unchanged. The same 6,747-entry old-to-new mapping was applied to both endpoints of every row in `relations/edges.csv`.

Before remapping, 26 staged dictionary-word IDs collided with IDs in the original seven `data/kg/*.json` runtime files and `data/topic_graphs*.json`: six curated seed buckets and 20 enriched topic concepts. After remapping, the exact overlap between all 10,849 new concept IDs and the 4,335 existing IDs was **0**.

## Production files

| File | Concepts | Edges | Source and license |
|---|---:|---:|---|
| `07_vocabulary_anki.json` | 6,747 | 0 | LexiLingo production Anki deck; Alex123321/english_cefr_dataset, Apache-2.0 |
| `08_cefr_sentences.json` | 1,250 | 0 | UniversalCEFR/cefr_sp_en, CC BY-NC-SA 4.0 (non-commercial/share-alike restrictions apply) |
| `09_grammar_usage.json` | 1,000 | 0 | Teravee/1000_english-grammar-dataset, license undeclared |
| `10_collocations.json` | 1,000 | 0 | vladvlasov256/opensubs-collocations, CC-BY-4.0 |
| `11_idioms.json` | 852 | 0 | adihaviv/idiomem, MIT |
| `12_lexical_relations.json` | 0 | 162,694 | appledora/conceptnet_en2en_relations, CC-BY-4.0 |
| **Total new payload** | **10,849** | **162,694** | |

All files use production fields `id/title/keywords/level` and `from/to/relation`. Unknown concept levels are stored as `""`. The relation rows are unchanged apart from endpoint remapping and stable grouping of unresolved runtime endpoints at the end, reducing Kuzu's record-by-record fallback from 78 batches to two.

## Runtime ingestion order

`api/services/kg_service_v3.py::_RUNTIME_KG_SOURCE_FILES` retains its original seven entries and appends, in order:

1. `07_vocabulary_anki.json`
2. `08_cefr_sentences.json`
3. `09_grammar_usage.json`
4. `10_collocations.json`
5. `11_idioms.json`
6. `12_lexical_relations.json`

The edge-only file is last, after every concept file in the runtime tuple.

## Real production-path verification

A fresh `/tmp/lexilingo_real_sync_test.kuzu` database was created using the exact four DDL statements from `KnowledgeGraphServiceV3._ensure_schema()`. With the repository virtual environment active, `api.services.kg_data_loader.sync_knowledge_files()` loaded all 13 real `data/kg/` paths in `_RUNTIME_KG_SOURCE_FILES` order with the production forbidden-prefix check.

| Result | Count |
|---|---:|
| `sync_knowledge_files()` concept merges | 15,078 |
| Unique concepts queried from fresh Kuzu DB | 15,077 |
| `sync_knowledge_files()` edge merges | 177,270 |
| Unique edges queried from fresh Kuzu DB | 177,263 |
| New lexical relation rows loaded | 162,490 / 162,694 |
| Warning/error log records | 13 warnings / 0 errors |

The merge counters include one repeated concept ID and seven repeated edges that Kuzu `MERGE` stored idempotently. Of the new lexical relations, 204 rows (206 endpoint references) do not have both endpoints in the 13 runtime files and were skipped by the real loader. Those endpoints exist only outside the runtime tuple (for example in topic graph data), so the lexical file hash was intentionally not persisted. The existing files `01` through `05` likewise logged their pre-existing incomplete-edge warnings. Warning summary: seven batch-fallback warnings and six incomplete-sync/hash-not-persisted warnings (`01` through `05`, plus `12`); no errors were logged.

### Proof that curated seed concepts were not overwritten

| ID | Title after full sync |
|---|---|
| `concept:vocab.academic` | Academic Vocabulary |
| `concept:vocab.health` | Health & Medicine |
| `concept:vocab.shopping` | Shopping & Money |
| `concept:vocab.technology` | Technology & Gadgets |
| `concept:vocab.transport` | Transport & Commuting |
| `concept:vocab.travel` | Travel & Tourism |

Every queried title exactly matched `seed_graph.json` after all 13 files were processed.

### Ten lines rendered by the real `render_knowledge_prefix()`

The graph was queried back from the scratch Kuzu DB into `{"concepts": [...], "edges": [...]}` and passed directly to `scripts.crawl_topic_knowledge.render_knowledge_prefix(..., max_edges=10)`:

```text
- (A1 (Concept)) -[related_to]-> (paper (Vocabulary)) [Source: topic_crawl]
- (A1 (Concept)) -[related_to]-> (protein (Vocabulary)) [Source: topic_crawl]
- (A1 (Concept)) -[has_context]-> (ship (Vocabulary)) [Source: topic_crawl]
- (A2 (Concept)) -[related_to]-> (paper (Vocabulary)) [Source: topic_crawl]
- (B1 (Concept)) -[related_to]-> (paper (Vocabulary)) [Source: topic_crawl]
- (Account Collocation (Concept)) -[related_to]-> (Account (Concept)) [Source: topic_crawl]
- (Bug Collocation (Concept)) -[related_to]-> (Bug (Concept)) [Source: topic_crawl]
- (Device Collocation (Concept)) -[related_to]-> (Device (Concept)) [Source: topic_crawl]
- (Integration Collocation (Concept)) -[related_to]-> (Integration (Concept)) [Source: topic_crawl]
- (Model Output Collocation (Concept)) -[related_to]-> (Model Output (Concept)) [Source: topic_crawl]
```

Note: the `(Concept)` labels above (e.g. `A1`, `Account Collocation`) come from pre-existing `data/kg/06_tracecag_topic_expansion.json` concepts using id prefixes (`cefrlevel:`, `collocation:`) that `concept_type()` does not recognize, so they fall into the generic bucket. This predates this merge and was not introduced by it — flagged here for a future cleanup pass.

## Follow-up fix: sync completeness for 12_lexical_relations.json

The initial `12_lexical_relations.json` included 204 edges (out of 162,694) whose endpoints only exist in `data/topic_graphs*.json` — outside the 13-file `_RUNTIME_KG_SOURCE_FILES` runtime set. `sync_knowledge_files()` correctly loaded everything else but logged the file as incomplete and never persisted its content hash, meaning every service restart re-ran the full ~162k-edge merge (measured at ~3.5 minutes) with no caching benefit.

Fix applied: the 204 edges with unresolvable endpoints were filtered out (204/162,694 = 0.13%, negligible loss), leaving exactly the 162,490 edges that were already loading successfully. Re-verified against the real `sync_knowledge_files()` path:

| Run | Result |
|---|---|
| Cold sync (fresh scratch DB) | 15,078 concepts, 177,270 edges merged; `12_lexical_relations.json` hash **cached** (previously never cached) |
| Second sync (same DB, unchanged files) | 0.89s (down from ~3.5 minutes); residual 97 concepts/109 edges come from pre-existing `01_grammar_gaps.json`–`05_vocabulary_advanced.json` incomplete-sync warnings that predate this merge |

`data/kg/12_lexical_relations.json` now ships with 162,490 edges (was 162,694).
