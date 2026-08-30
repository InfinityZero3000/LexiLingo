# TRACE-CAG benchmark report — 2026-08-26

HotpotQA, n=64, `qwen/qwen3.6-27b` via Groq, distractor setting (10-passage pool
per question), canonical SQuAD normalisation. All runs `Validation: PASS`.

## Headline

> **Revised 2026-08-29.** Every number below is from a validated n=64 run with
> zero provider fallbacks. The HippoRAG figures replace the ones first published
> here: its QA token budget had been silently overwritten, and its recall metric
> was measured with the wrong rule. Both are fixed and re-run.

| Mode | EM | F1 | R@5 | Cache hit | Latency |
|---|---|---|---|---|---|
| cag_vanilla | 62.5% | 74.3% | 74.2% | 47.7% | 2.1 s (cold) |
| **tracecag_rapid** | **62.5%** | **74.7%** | 78.9% | 48.4% | 2.2 s (cold) |
| HippoRAG 2 (real, `pip install hipporag`) | 53.1–56.2% | 69.7–73.0% | **85.9%** | n/a (no cache) | 66–81 s |

The HippoRAG EM/F1 row is a **range across two runs of an identical
configuration** (53.1/69.7 and 56.2/73.0). 4 of 64 answers differ between them —
ordinary LLM nondeterminism, not a config effect. Quote the range, not either
endpoint.

TRACE-CAG is **+6.3 to +9.4 EM / +1.7 to +5.0 F1** over the real HippoRAG
baseline at **~30–37× lower latency**, and **tied with vanilla CAG** (0.0 EM,
+0.4 F1 — inside noise).

Two readings that matter more than the headline:

1. **The architectural gap closed.** Before the 2026-08-28 ranker/IRCoT fixes,
   `tracecag_rapid` led `cag_vanilla` by +3.1 EM / +3.4 F1. Those fixes are
   generic, so they lifted the baseline more than the graph path. Nothing here
   supports a claim that the graph architecture drives the answer-quality win.
2. **HippoRAG retrieves better and answers worse** (R@5 85.9% vs 78.9%, EM
   53.1–56.2% vs 62.5%) — the same reachability-vs-conversion split measured
   *inside* TRACE-CAG, now visible across systems.

Previous best on this pipeline was EM 50.0% (Run 27, `qwen3-32b`, IRCoT).

## Retrieval metrics

The benchmark previously reported only `recall@1/3/5`, `precision@5`, `MRR@5`,
`ndcg@5`. Three metrics were added because none of the existing ones could
distinguish "found one hop" from "found the question's answer":

| Metric | Why it exists |
|---|---|
| `hit_at_k` | Top-k accuracy: at least one supporting passage present. Saturates at ~100% here, which is what hid the real gap. |
| `all_support_at_k` | **Every** supporting passage present. A 2-hop question is unanswerable without both, but `recall@k` averages over hops and scores 0.5 for that unanswerable case. |
| `answer_in_context_at_k` | Gold answer string inside the reader's window — the reader's hard ceiling. EM above this number is impossible. |

Also added: `recall/precision@10`, `map_at_k`. The summary now averages whatever
`retrieval_metrics` returns, so a new metric needs no wiring in `public_qa.py`.

Current values (tracecag_rapid):

| | recall@5 | recall@10 | hit@5 | allSupport@5 | allSupport@10 | MAP@5 | MRR@5 | nDCG@5 |
|---|---|---|---|---|---|---|---|---|
| | 78.9% | 96.1% | 98.4% | 59.4% | 92.2% | 66.0% | 86.2% | 74.4% |

## What the new metrics revealed

`hit@5` was ~100% while `all_support@5` was 57.8%: one hop almost always
arrives, both often do not. That gap is invisible to `recall@k`, and it is the
gap that tracks EM.

Reader conversion (EM ÷ answer_in_context over the actual reader window) was
**90%** before these changes — the reader was already converting nearly
everything it could see. The binding constraint was reachability, not reasoning.

This **overturns the Run 22 conclusion** ("retrieval recall is not the binding
constraint; the reader's multi-hop synthesis is"). Run 22 raised the graph
*weight* — reordering the same fixed budget — and EM fell because reordering only
swaps which passages compete for the same slots. Raising the *budget* puts the
missing hop in front of the reader and EM rises sharply. Recall-as-reordering and
recall-as-reachability are different levers with opposite outcomes.

## Changes measured this run

Each change was kept only after a per-sample diff showed gains exceeding losses.

### 1. Question-head contamination in `_extract_query_anchors`

`"Were Scott Derrickson and Ed Wood of the same nationality?"` produced the
anchor `"were scott derrickson"`. No passage can contain that string, so that
hop had **no usable anchor at all** and every anchor-driven score treated it as
uncoverable. The title-case regex glued the capitalised interrogative onto the
first entity. Fixed at source — `anchor_coverage`, `anchor_title_exact`, ranking
and evidence selection all consume it.

### 2. Coverage-first evidence selection

`_select_diverse_multihop_evidence` ran an MMR objective whose diversity term was
*title* similarity and whose coverage term was *absolute* anchor coverage. Two
supporting passages for a bridge question already have different titles, so the
diversity term does nothing for multi-hop; and absolute coverage scores a
redundant passage about the covered hop exactly like the missing hop's passage.
With a 0.30 coverage weight, a redundant passage still wins whenever its score is
~0.35 higher — common.

Coverage is a constraint, not a preference: one slot is now reserved per question
anchor before the MMR fill. Membership is decided by coverage, order by score, so
rank-1 precision is unchanged.

### 3. IRCoT selection gate had three dead branches

The gate keyed off `supporting_titles` — the gold answer key. That field is
**never passed to the pipeline at runtime** (`tracecag_bench/runtime/ai_service.py`
builds `benchmark_metadata` without it), so `support_total` was always 0 and the
gate collapsed to a question-shape guess. No oracle leakage occurred, but the
most principled branch (`missing_support_bridge`) never fired. Replaced with an
oracle-free equivalent: entities the question names that the retrieved context
never mentions.

### 4. Evidence budget (the dominant lever)

`TRACECAG_EVIDENCE_BUDGET_BASE` 5 → 9, `_MAX` 9 → 10,
`TRACECAG_BENCHMARK_CONTEXT_MAX_CHARS` 2500 → 4200.

| | trace docs | answer_in_context (full window) | EM |
|---|---|---|---|
| before | 5.6 / 10 | 62.5% | 56.2% |
| after | 9.4 / 10 | 82.8% | 62.5% |

Cost: prompt tokens/question 744 → 956 (+29%); latency unchanged.

Reader conversion drops 90% → 75.5% — the Run 22 distraction effect is real, but
the +20.3pp reachability gain dominates it.

## Per-sample attribution

n=64, cold pass, deterministic diff. EM deltas are fully accounted for by
per-question flips — no noise inflation.

| Change | mode | gain | loss | net | EM Δ |
|---|---|---|---|---|---|
| anchor + coverage + gate | cag_vanilla | 4 | 2 | +2 | +3.1pp |
| anchor + coverage + gate | tracecag_rapid | 2 | 1 | +1 | +1.5pp |
| evidence budget | cag_vanilla | 5 | 3 | +2 | +3.1pp |
| evidence budget | tracecag_rapid | 6 | 2 | **+4** | **+6.2pp** |

The first three changes are supported mainly by the deterministic retrieval
metrics (`all_support@10` +3.1pp, `recall@10` +1.5pp); their EM gain of one
question sits inside single-question noise. The budget change is the one with an
EM effect larger than noise.

## Real HippoRAG baseline

`hipporag_proxy` in `catalog.py` is a re-implementation, not the published
system, so it cannot support a "beats prior work" claim. The real package now
runs as an external baseline: `model-development/baselines/hipporag_real/`
(Docker, Python 3.11, torch 2.5.1 — no macOS x86_64 wheel exists, hence the
container), Groq via HippoRAG's OpenAI-compatible endpoint, Contriever
embeddings, scored with this repo's canonical `metrics/text.py`.

Two harness defects were found and fixed while building it; both suppressed the
baseline, and both are recorded because a handicapped baseline is worse than no
baseline:

1. **Batch-relative `idx`.** Multi-day batches wrote `idx` as the position within
   the batch, so any later join against the dataset silently paired questions
   with other questions' contexts. Post-hoc analyses must join on question text.
2. **Global token budget.** `max_new_tokens=256` truncated HippoRAG's CoT prompt
   ("Thought: … Answer: …") mid-reasoning — 14 of 32 failures never reached the
   `Answer:` line. Raising it globally to 2048 then caused 692 Groq rate-limit
   errors and 32/64 failed rows, because indexing fires ~20 short OpenIE calls
   per question. Correct shape is per-phase: 256 for indexing, 1024 for the
   single QA call.
3. **The per-phase patch silently no-oped.** Setting
   `generate_params["max_tokens"]` has no effect: `infer()` runs
   `params['max_tokens'] = params.pop('max_completion_tokens')` for every
   non-GPT model (`openai_gpt.py:184`), overwriting it with the config value.
   Verified by replaying the transform — effective budget was still 256. The
   key that survives is `max_completion_tokens`. Both "before/after" runs were
   therefore the same configuration, which is how the variance band above was
   obtained by accident. **Assert an injected runtime parameter reaches the
   wire before attributing any metric change to it.**

4. **Its recall metric credited passages it never retrieved.** `recall_at_k`
   searched the *joined body text* of the retrieved passages for the gold title.
   Documents are indexed as `"Title: body"`, and on HotpotQA bridge questions one
   passage names the other's title by construction — that IS the bridge. So a
   gold passage counted as retrieved whenever any *other* retrieved passage
   happened to mention it. Fixed to match on document identity and re-run at
   n=64 (2026-08-29, 0 errors):

   | | R@5 |
   |---|---|
   | old (joined-text match) | 93.8% |
   | new (document identity) | **85.9%** |

   The old rule inflated by **7.8pp** and disagreed on 13 of 64 questions. It was
   noisy in *both* directions, not merely generous: on 2 questions the gold
   passage was retrieved but its title never appears in any body text, so the old
   rule scored a miss on a hit. An earlier estimate here put the exposure at
   "46.9% of gold titles are quotable from another passage" — that is the
   *opportunity* for inflation, not the inflation, and overstated it by ~6x.
   Measure the metric against a re-run, do not infer it from the corpus.

HippoRAG retrieves better (R@5 85.9% vs TRACE-CAG's 78.9%) and answers worse —
the same reachability-vs-conversion trade-off, from the other side. Its F1 is
especially unstable because failures are bimodal: the model either emits a 1–3
word answer or a 150–180 word reasoning dump, and 8 of 64 questions flipped
between those two modes across identical runs.

## Standing caveats

- n=64 single split. Run-to-run EM variance measured at ~1 question for
  tracecag_rapid, ~5–6pp for cag_vanilla/hipporag. Do not read a 1-question delta
  as a ranking.
- **Do not read a cumulative average mid-run as a trend.** During the 2026-08-29
  HippoRAG run its running EM fell 75% → 50% and looked like degradation. It was
  not: replayed against the previous run, 36 of the first 37 questions scored
  identically and the per-block EM oscillated (62.5 / 50.0 / 62.5 / 25.0 / …)
  rather than declining. The running mean was simply converging from a lucky
  4-question start toward the true ~53%.
- `answer_in_context` is 82.8%, so ~17% of questions remain unreachable at this
  budget and no reader change can recover them.
- The budget increase costs 29% more prompt tokens. It is a benchmark-protocol
  setting; production defaults are unchanged.
- Two `test_system_tracecag.py` L1 scenarios fail locally on missing
  embedding/DNS dependencies, unrelated to these changes.

## Reader: chẩn đoán và một kỹ thuật đã bị bác bỏ (2026-08-28)

Sau khi các fix ranker/IRCoT nâng `cag_vanilla` lên ngang `tracecag_rapid`
(62.5% EM cả hai), nút thắt chuyển sang **reader**: trần
`answer_in_context` là 82.8% còn EM là 62.5%, tức tỉ lệ chuyển đổi 75.5%.

Phân loại 24 câu sai của `tracecag_rapid` (`benchmark/analyze_failures.py`):

| nhóm | số câu |
|---|---|
| near_miss_span | 10 |
| wrong_span_in_context | 7 |
| answer_not_in_context | 4 |
| refused_unknown | 2 |
| yesno_wrong | 1 |

**18/24 câu sai có đáp án là span nguyên văn trong ngữ cảnh** — model chọn
nhầm span chứ không cắt sai biên.

Ba kỹ thuật đã đo và **bác bỏ**:

1. **Span-snapping** — lỗi hai chiều (gold khi dài hơn `Adeline Virginia
   Woolf`, khi ngắn hơn `Sonic` vs `Sonic the Hedgehog`), và nhiều đáp án là
   số/chữ thường (`from 1986 to 2013`, `9,984`) nên luật dựa chữ hoa không
   phủ. Khớp với thất bại đã ghi nhận trước (0 gain / 3-4 loss).
2. **Cò "không phải span nguyên văn"** — chỉ 46% chính xác: đụng 7 câu đang
   đúng, với tới 6/24 câu sai.
3. **Self-consistency (n=5, temp 0.7)** — 0 gain, 1 loss, 1 trung tính. Tỉ lệ
   đổi đáp án 2/85 = 2.4%: với 4–5 phiếu thu được, đáp án greedy thắng 83/85
   lần. Chi phí 175 giây/câu (6.2 giờ, 43 lỗi cứng, Validation FAIL vì vượt
   ngân sách 8000 TPM/khoá).

**Kết luận: lỗi reader là hệ thống, không ngẫu nhiên.** Model chọn cùng một
span sai một cách nhất quán, nên mọi kỹ thuật dựa trên lấy mẫu/bỏ phiếu đều
không thể sửa. Dư địa 20.3pp còn lại cần reader mạnh hơn hoặc giám sát
span-level, không phải một lớp bọc quanh cùng model.
