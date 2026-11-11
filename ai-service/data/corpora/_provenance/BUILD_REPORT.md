# Hugging Face staging build report

Built 2026-08-02 using only public HTTPS endpoints from Hugging Face and the Hugging Face dataset server. No `datasets` package or new dependency was installed. The prior `cefr_sp_en_sample.*` pilot and its companion root-level staging files were not changed.

## 1. KG vocabulary and grammar

Staged 2,000 concepts and no inferred relations:

- **1,000 sentence concepts** from [`UniversalCEFR/cefr_sp_en`](https://huggingface.co/datasets/UniversalCEFR/cefr_sp_en), config `default`, split `train`, row indices 9000–9999. These indices are new relative to the 250-row pilot, whose maximum staged row index is 8490. License: **CC BY-NC-SA 4.0 — non-commercial and share-alike; restrictive for commercial use**.
- **1,000 standalone vocabulary concepts** from [`Alex123321/english_cefr_dataset`](https://huggingface.co/datasets/Alex123321/english_cefr_dataset), config `default`, split `train`, row indices 0–999. Fields used are `ud_word`, `ud_word_level`, and `ud_word_pos`. License: Apache-2.0.

Sentence IDs use `concept:phrase.cefr-sp-...`; vocabulary IDs use `concept:vocab.cefr-word-...`. Both prefixes are accepted by `concept_type()` and `render_knowledge_prefix()`. `nodes.csv` is headerless with `id,title,keywords,level`; `edges.csv` is intentionally empty because neither source supplies verified relations in the rows staged here. `graph.json` uses the repository's `{"concepts": [...], "edges": [...]}` shape.

No Oxford 3000/5000 or English Vocabulary Profile data was staged: no freely usable, verifiable HF dataset published by those rights holders was found. The CEFR vocabulary dataset above is explicitly identified rather than presented as Oxford/EVP data. A newer aggregate, `cstr/grundwortschatz-voc-en`, was verified on the dataset server and references CEFR-J among several upstream sources, but it was not mixed in because the direct standalone word-level dataset already satisfies this review batch and the aggregate includes heterogeneous and partly generated enrichment.

## 2. Grammar error-correction pairs

Staged **1,000 pairs** from [`jhu-clsp/jfleg`](https://huggingface.co/datasets/jhu-clsp/jfleg): all available validation rows followed by test rows until the requested count was reached. The first human reference correction is retained for each original sentence. License: **CC BY-NC-SA 4.0 — non-commercial and share-alike; restrictive for commercial use**.

The requested [`bea2019st/wi_locness`](https://huggingface.co/datasets/bea2019st/wi_locness) repository is public and ungated, but on this build date the dataset server returned HTTP 500 for `/splits` and HTTP 404 for `/rows` for its advertised configs. Therefore **0 W&I+LOCNESS rows were staged**. Its HF metadata labels the license `other`; the source terms are for **non-commercial research**, so it requires legal/license review even when the server becomes usable. No community reformat was silently substituted.

A CoNLL-2014-associated HF repository, [`nusnlp/NUCLE`](https://huggingface.co/datasets/nusnlp/NUCLE), was found, but the dataset server returned `No (supported) data files found`; search did not verify an accessible, row-serving CoNLL-2014 mirror. Therefore **0 CoNLL-2014 rows were staged**.

The chosen minimal JSONL schema is documented in `gec_pairs/README.md`. `error_type` and `cefr_level` remain null because JFLEG does not provide them; they were not inferred or fabricated.

## 3. Dialogue instructions

Staged **1,000 samples** from [`Intel/orca_dpo_pairs`](https://huggingface.co/datasets/Intel/orca_dpo_pairs), config `default`, split `train`, row indices 0–999. The source `system` prompt becomes `instruction` (or a neutral fallback when empty), `question` becomes `input`, and `chosen` becomes `output`; every row uses `strategy: "general"`. License: Apache-2.0.

This is a **generic-instruction substitute, not an ESL-tutoring corpus**. Web and HF searches found University of Memphis publications describing AutoTutor and sample dialogues, but no verifiable freely downloadable AutoTutor Dialogue Corpus dataset or HF row endpoint. The available evidence did not establish a public corpus download, so no AutoTutor data was invented and no stronger license/access claim is made here.

## 4. English–Vietnamese parallel pairs

Fetched the first **2,000** train rows from [`Helsinki-NLP/opus-100`](https://huggingface.co/datasets/Helsinki-NLP/opus-100), verified config `en-vi`. Each source row contains a `translation` object with both `en` and `vi`. After removing 12 exact duplicate pairs, **1,988 pairs** were staged. Hugging Face reports the dataset license as **unknown**, so downstream redistribution and commercial training require an upstream OPUS-source license audit.

## Unavailable named sources

- **Oxford 3000/5000 and EVP:** no verified freely redistributable official HF dataset found.
- **CEFR-J:** no direct official HF dataset was used; only derivative/aggregate datasets were found.
- **AutoTutor Dialogue Corpus:** publications and examples are public, but no freely downloadable corpus package or HF dataset was verified.
- **W&I+LOCNESS:** public HF repository, but no rows were available through the required dataset-server API during this build; non-commercial research terms apply.
- **CoNLL-2014/NUCLE:** a related HF repository exists, but it has no dataset-server-supported data files.
- **EFCAMDAT, TOEFL11, and FCE:** not substituted in this run; their original access/license paths should be handled separately rather than represented by unrelated HF mirrors.

## Realistic scale-up recommendation

For review and pipeline expansion, first validate these 5,988 staged records/concepts and keep provenance plus license gates in the import manifest. Public API sources can readily scale Orca and OPUS, while UniversalCEFR and JFLEG must remain non-commercial unless separate permission is obtained. Reaching the architecture target of 16,700 high-quality training samples needs licensed access to W&I+LOCNESS/FCE, EFCAMDAT/TOEFL11, Oxford/EVP, and a genuine tutoring corpus or a clearly labeled custom ESL collection; generic Orca volume cannot replace tutoring quality.

The 1,000,000-node KG target is not realistic through sentence rows alone. Scale next with openly licensed lexical resources that expose stable concepts and real relations (for example Open English WordNet and appropriately licensed CEFR mappings), deduplicate by canonical lemma/sense, and measure useful connected nodes rather than padding disconnected sentence nodes. At the current 2,000-node review batch size, roughly 500 such batches would reach one million, so automated provenance, license filtering, relation validation, and incremental Kuzu import checks are prerequisites.

## Final counts

| Workstream | Raw rows fetched | Records staged | Notes |
|---|---:|---:|---|
| `kg_vocab_grammar/` | 2,000 | 2,000 concepts | 1,000 sentences + 1,000 vocabulary; 0 edges |
| `gec_pairs/` | 1,000 | 1,000 pairs | JFLEG only; W&I+LOCNESS and CoNLL-2014: 0 |
| `dialogue/` | 1,000 | 1,000 samples | Generic Orca instructions, not ESL tutoring |
| `parallel_en_vi/` | 2,000 | 1,988 pairs | 12 exact duplicates removed |
| **Total** | **6,000** | **5,988** | Concepts and training records combined |
