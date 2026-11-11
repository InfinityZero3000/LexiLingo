# New Hugging Face KG Categories

Generated and verified on 2026-08-02 using only the public Hugging Face Hub and datasets-server HTTP APIs.

## Sources

### Grammar rules and explanations

- Dataset: [`CreativeAlloyYT/French_Grammar_Explanations`](https://huggingface.co/datasets/CreativeAlloyYT/French_Grammar_Explanations)
- License: `apache-2.0` (confirmed from Hub dataset metadata)
- Real size: 1,586 rows in `default/train` (confirmed by datasets-server `/size`)
- Schema and real rows: confirmed by datasets-server `/first-rows`; fields are `instruction` and `response`
- Imported: 893 concepts from the first 1,000 source rows. Blank/duplicate titles and one literal header-like row were excluded.
- Mapping: `concept:grammar.*`; all 893 IDs resolved to `Grammar`
- Level: blank because the source has no CEFR/difficulty field
- Edges: 0 because the source provides no relations

This source explains French grammar in English; it is grammar coverage, not an English-grammar corpus.

### Collocations

- Dataset: [`vladvlasov256/opensubs-collocations`](https://huggingface.co/datasets/vladvlasov256/opensubs-collocations)
- License: `cc-by-4.0` (confirmed from Hub dataset metadata)
- Real size: 15,000 rows in `en/train` (confirmed by datasets-server `/size`)
- Schema and real rows: confirmed by datasets-server `/first-rows`; fields include `bigram`, POS `type`, `count`, `pmi`, `npmi`, and `score`
- Imported: the first 1,000 English collocations, preserving source statistics in `keywords`
- Mapping: `concept:collocation.*`; all 1,000 IDs resolved to `Collocation`
- Level: blank because the source has no CEFR/difficulty field
- Edges: 0 because the source provides no relations

### Idioms

- Dataset: [`adihaviv/idiomem`](https://huggingface.co/datasets/adihaviv/idiomem)
- License: `mit` (confirmed from Hub dataset metadata)
- Real size: 852 rows in `default/train` (confirmed by datasets-server `/size`)
- Schema and real rows: confirmed by datasets-server `/first-rows`; fields include `idiom`, source, and four dataset indicators
- Imported: all 852 idioms, preserving source and indicator fields in `keywords`
- Mapping: `concept:phrase.*`; all 852 IDs resolved to `Phrase`
- Level: blank because the source has no CEFR/difficulty field
- Edges: 0 because the source provides no relations

## Output validation

Each category contains headerless `nodes.csv` in `id,title,keywords,level` order, an empty `edges.csv`, and a `graph.json` with `{"concepts": [...], "edges": []}`. CSV rows and JSON concepts were checked for exact field equality, every CSV row has four columns, and all 2,745 IDs are unique.

The real `concept_type()` from `scripts/crawl_topic_knowledge.py` was imported and called for every ID:

- `Grammar`: 893
- `Collocation`: 1,000
- `Phrase`: 852
- Generic `Concept`: 0

## Overlap with merged KG

Titles were normalized read-only with Unicode NFKC, case-folding, extraction of Unicode word characters, and whitespace joining before comparison with `merged_kg/nodes.csv`.

- Grammar rules: 0 overlaps
- Collocations: 3 overlaps (`set up`/`set-up`, `line up`/`line-up`, and `' re`/`re` after normalization)
- Idioms: 0 overlaps
- Total: 3 overlaps

No records were merged into or removed from `merged_kg`.

## Live Kuzu import

After deleting the prior scratch target, the three `nodes.csv` files were combined in `/tmp` and loaded through the real `scripts/kg_pipeline/importers/kuzu_importer.py` into `/tmp/lexilingo_new_categories_test.kuzu` with the project virtual environment active.

- Import method: `COPY FROM`
- Importer result: 2,745 nodes, 0 edges, 0 errors, 0.3 seconds
- Independent live queries: 2,745 `Concept` nodes and 0 `Edge` relationships

## Final summary

| Category | Verified HF dataset | License | Real source rows | New concepts | `concept_type()` | Merged-title overlaps | Kuzu errors |
|---|---|---:|---:|---:|---|---:|---:|
| Grammar rules | `CreativeAlloyYT/French_Grammar_Explanations` | Apache-2.0 | 1,586 | 893 | Grammar | 0 | 0 |
| Collocations | `vladvlasov256/opensubs-collocations` (`en/train`) | CC-BY-4.0 | 15,000 | 1,000 | Collocation | 3 | 0 |
| Idioms | `adihaviv/idiomem` | MIT | 852 | 852 | Phrase | 0 | 0 |
| **Total** | **3 verified sources** | — | **17,438** | **2,745** | **0 generic** | **3** | **0** |
