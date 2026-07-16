# Offline Bridge Rerank Probe Design

## Goal

Test whether cheap bridge-aware reranking improves frozen Day 1–2 retrieval before modifying production.

## Design

One stdlib-only script reads validated benchmark reports and their frozen dataset JSONL files. It selects cold `tracecag_rapid` observations, joins them to questions/supporting titles by `source_id`, and reranks only the saved top-six retrieval trace. Gold titles are used only for metrics.

The probe compares the original order with three deterministic scorers: query overlap, bridge linkage between one candidate's title and another candidate's text, and reciprocal-rank fusion of original/query/bridge ranks. It reports Recall@5, MRR, NDCG@5, paired wins/losses/ties, and candidate-pool upper-bound Recall@5.

The script cannot measure candidate expansion because artifacts contain only the final trace. A positive result justifies production reranking work; a flat upper bound indicates candidate expansion must be tested next.

## Safety

No provider calls, production imports, cache writes, KG writes, or threshold changes. Missing joins or malformed reports fail loudly.
