# UniversalCEFR Import Verification

## Source and sample

- Dataset: `UniversalCEFR/cefr_sp_en`
- Dataset-server config/split: `default` / `train`
- Dataset-server `/info` columns observed: `title`, `lang`, `source_name`, `format`, `category`, `cefr_level`, `license`, `text`
- Dataset-server size: 10,004 train rows
- Sample fetched and retained: 250 real rows
- Retained level counts: A1 42, A2 42, B1 42, B2 42, C1 41, C2 41
- Sampling: deterministic level-balanced slices. `/rows` was used for schema inspection and the contiguous B2/C1/C2 slices; dataset-server filtering selected the scattered A1 rows and matching A2/B1 slices by their real `row_idx`.
- Rows skipped: 0 (all sampled rows had non-empty `text` and a mappable CEFR level)

**License restriction:** every sampled row reports `CC BY-NC-SA 4.0`. This is a non-commercial, attribution, share-alike license. Do not merge this data into a commercial production corpus without a rights/legal decision confirming that the intended use is permitted, and preserve required attribution and share-alike terms wherever it is used.

## Exact mapping

| Dataset value | Graph/CSV value |
|---|---|
| `row.text` | graph `concept.title`; CSV `title` |
| `row.cefr_level` | trimmed and uppercased CSV `level`; accepted only when one of A1, A2, B1, B2, C1, C2 |
| `row.row_idx` + first 10 hex characters of SHA-256(`text`) | `concept:phrase.cefr-sp-<zero-padded-row-index>-<hash>` |
| first five unique non-trivial split words from `text` | comma-separated CSV `keywords` |
| no source relation | graph `edges: []`; zero-byte `edges.csv` |

`cefr_sp_en_sample.graph.json` contains exactly `{"concepts": [{"id": ..., "title": ...}], "edges": []}`. `nodes.csv` is headerless in `id,title,keywords,level` order. `edges.csv` is headerless and empty because the source sample supplies no real graph relations.

## Prefix convention and renderer live run

The staged JSON was loaded, `scripts.crawl_topic_knowledge.py` was imported as `scripts.crawl_topic_knowledge`, and its real `concept_type()` and `render_knowledge_prefix()` functions were called.

- IDs checked: 250
- IDs matching an allowed convention: 250/250 (`concept:phrase.`)
- `concept_type()` results: 250 `Phrase`, 0 generic `Concept`
- `render_knowledge_prefix()` result: completed without error
- Rendered line count: 1. With zero real edges, the function correctly emits only its header; it renders edge statements rather than standalone concepts.

First up-to-30 rendered lines (the complete output in this edge-free sample):

```text
[LEXILINGO KNOWLEDGE BASE]
```

## Kuzu live import

- Python environment: repository `venv/bin/python`
- Kuzu package: 0.11.3
- Scratch database: `/tmp/lexilingo_hf_import_test.kuzu` (removed first if present)
- DDL executed:

```cypher
CREATE NODE TABLE IF NOT EXISTS Concept(id STRING, title STRING, keywords STRING, level STRING DEFAULT 'B1', PRIMARY KEY(id));
CREATE REL TABLE IF NOT EXISTS Edge(FROM Concept TO Concept, relation STRING);
```

- `COPY Concept FROM '<staged nodes.csv>' (HEADER=false, DELIM=',', IGNORE_ERRORS=true)`: success
- `COPY Edge FROM '<staged edges.csv>' (HEADER=false, DELIM=',', IGNORE_ERRORS=true)`: success on the zero-byte file
- Nodes queried after load: 250
- Edges queried after load: 0
- Loaded levels queried from Kuzu: A1 42, A2 42, B1 42, B2 42, C1 41, C2 41
- Kuzu errors: none

## Recommendation

The staged files are structurally consumable by both checked repository paths: concept typing/rendering and Kuzu bulk import. They should not be merged directly into production data yet. First obtain a legal/product decision for the CC BY-NC-SA 4.0 non-commercial and share-alike restrictions, define provenance/attribution fields outside these minimal schemas, and review sentence quality and level calibration. If approved for an eligible non-commercial use, import the headerless CSV as phrase nodes; leave edges absent until a real relation source or reviewed relation-building process exists.
