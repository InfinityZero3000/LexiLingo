# TRACE-CAG multi-hop improvement against HippoRAG

## Evidence and diagnosis

- Day 1 HotpotQA: TRACE-CAG rapid F1 `64.47%`, R@5 `78.13%`; HippoRAG proxy F1 `63.73%`, R@5 `82.81%`.
- Day 2 2Wiki: TRACE-CAG rapid F1 `65.57%`, R@5 `87.89%`; HippoRAG proxy F1 `68.59%`, R@5 `89.84%`.
- Therefore the gap is dataset-dependent and concentrated in multi-hop evidence coverage/ranking, not exact-cache routing. It is not valid to promise universal superiority before paired evaluation.

## Research-backed change

HippoRAG uses graph indexing plus Personalized PageRank for associative retrieval; HippoRAG 2 improves passage integration and online LLM use. Recent bridge-conditioned retrieval work reports that later-hop candidates should be scored conditioned on a retrieved bridge, not only on the original query. TRACE-CAG already has graph expansion and IRCoT, but IRCoT currently adds bridge passages mainly at generation time; it does not consistently feed a bridge-conditioned score back into the final retrieval order.

## Minimal implementation slice

1. Add a `bridge_coverage` signal to the existing retrieval feature vector. It measures whether a candidate shares an entity/anchor with a selected bridge and whether it completes a query-side relation.
2. Run bridge-conditioned reranking only when the existing multi-hop gate is true, candidate ambiguity is high, and the retrieval budget has at least 120 ms remaining. Single-hop and low-ambiguity queries keep the current path.
3. Use the current candidate pool and KG snapshot; do not add a new vector database or retrain online during evaluation.
4. Keep IRCoT's contract validation and fail-closed behavior. A rejected bridge must leave the original ranking unchanged.
5. Freeze the ranker snapshot per benchmark run. Online updates are disabled for final test evaluation to prevent test leakage.

## Acceptance criteria

- Primary: paired 2Wiki R@5 and answer F1 improve over the current TRACE-CAG run and close the HippoRAG gap; superiority is claimed only if the paired interval excludes zero.
- Safety: HotpotQA F1 must not regress by more than 1 percentage point; unsafe-serving and certificate metrics must remain unchanged.
- Cost: bridge reranking overhead is reported separately; no hidden extra provider calls on single-hop queries.
- Ablations: current TRACE-CAG, bridge signal only, bridge reranking, bridge reranking + IRCoT, and HippoRAG proxy under identical provider/model/KG/input splits.

## Required experiments before paper claims

- Run the complete Day 3–4 chain first.
- Run controller ablations and the locked DriftBench route gate.
- Compute paired bootstrap/Wilson intervals by item and cluster.
- Report both retrieval completeness (R@5/support coverage) and answer quality; never select per-dataset “best” cells from different runs.
- If the gap remains, position the contribution as state-certified routing with competitive multi-hop retrieval, not as a universal HippoRAG replacement.

## Offline probe result (2026-07-16)

The artifact-only probe rejected the initial simple-reranking hypothesis:

| Dataset | Original R@5 | Query overlap | Bridge link | RRF | Saved-pool upper bound |
|---|---:|---:|---:|---:|---:|
| HotpotQA | 78.13% | 78.13% | 75.00% | 78.13% | 80.47% |
| 2Wiki | 87.89% | 86.72% | 84.77% | 87.11% | 89.45% |

Simple lexical bridge scoring regresses both datasets. On 2Wiki, even an oracle reordering of the saved top-six pool cannot reach the HippoRAG proxy R@5 of 89.84%. Therefore production must not adopt these heuristics. The next probe must expand the candidate pool using a deterministic second hop before reranking; otherwise the target is mathematically unreachable from the stored trace.

The deterministic second-hop probe then expanded from the top-three seed passages by following titles explicitly mentioned in seed text. Top-three was selected on Day 1 and checked unchanged on Day 2:

| Dataset | Original R@5 | Second-hop R@5 | Paired delta | Bootstrap 95% interval | Wins / losses |
|---|---:|---:|---:|---:|---:|
| HotpotQA (development) | 78.13% | 87.50% | +9.38 pp | [+3.91, +14.84] pp | 13 / 1 |
| 2Wiki (cross-check) | 87.89% | 98.44% | +10.55 pp | [+6.25, +15.23] pp | 18 / 0 |

MRR decreases slightly (HotpotQA `0.854→0.837`; 2Wiki `1.000→0.974`) while NDCG@5 improves. This supports candidate expansion but not the current score ordering. The production experiment should add second-hop candidates and retain the original first relevant seed near rank one, then measure end-answer F1 before adoption.

An interleaving probe preserved the original top-one item before second-hop candidates. It retained the same R@5 gains while removing the ordering regression:

| Dataset | Interleaved R@5 | Interleaved MRR | Interleaved NDCG@5 |
|---|---:|---:|---:|
| HotpotQA | 87.50% | 0.861 | 0.812 |
| 2Wiki | 98.44% | 1.000 | 0.975 |

This is the production candidate: preserve top-one, follow explicit title links from the top-three seeds, deduplicate, then apply the existing evidence budget. It must first be added behind a benchmark-only flag in `_select_diverse_multihop_evidence`; end-answer EM/F1, latency, and IRCoT contract behavior remain unverified.
