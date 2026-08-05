# LexiLingo `data/` Audit

## Summary

All ordinary `.json` files parse. For true JSONL artifacts, the first and last 20 records parse and have consistent top-level schemas. The 106 MB `finetune_samples.jsonl` was only endpoint-sampled. No high-confidence API key, private-key, or credential pattern was found. The main risks are weak C2/long-form learning coverage, duplicate or mislabeled generated artifacts, and incomplete Kuzu runtime ignore rules.

## Issues Found

1. **High — C2 and assessable learning content are largely absent.** `kg/06_tracecag_topic_expansion.json` has 4,040 concepts but no C2 entries (A1 203, A2 1,012, B1 1,413, B2 1,008, C1 404). Only `kg/seed_graph.json` contains C2, with 2 concepts. The 68 story records stop at C1 and are role-play blueprints, not complete graded readers or IELTS reading/listening passages.
2. **High — Vietnamese learner errors are labels, not correction examples.** `kg/03_errors_vietnamese.json` has 20 error concepts and relations, but no paired erroneous/correct sentence, explanation, Vietnamese transfer cue, or difficulty metadata suitable for drills or evaluation.
3. **Medium — generated graph outputs contain exact duplicates.** `kg_output/edges.json` has 173 surplus duplicate records across 65 groups; `quadruples.json` has 167 surplus duplicates across 53 groups. Maximum repetition is 27. Deduplicate in the generator before rebuilding downstream artifacts.
4. **Medium — `kg_output/kg_checkpoint_formated.jsonl` is not JSONL.** It is one valid, pretty-printed JSON array, so record-per-line readers fail. The filename also misspells `formatted`. Regenerate as actual JSONL or rename it to `.json`.
5. **Medium — runtime debris and an ignore gap remain.** Two zero-byte `.init.lock` files and a 9.36 MB dated quarantine DB look stale because `lsof` showed no open handles; confirm no Kuzu process uses them before cleanup. `kuzu_runtime.db.wal` is an untracked 0.91 MB file that is not ignored. Synced-file manifests contain machine-specific absolute paths (`/Users/...`, `/app/...`), and the quarantine manifest references missing `kg/benchmark_entities.json`.
6. **Low — stale/redundant snapshots.** `sample_stories.json` and ignored `sample_stories.expanded.json` are byte-identical (68 unique `story_id` values), so “expanded” is currently redundant. `topic_graphs.enriched.json` is not stale: it contains all 8 base concepts plus 103 more, although 6 enriched concepts lack a CEFR level.
7. **Low — graph/schema convention drift.** One concept ID (`concept:grammar.gerund_infinitive`) appears in both `kg/01_grammar_gaps.json` and `kg/seed_graph.json`. Curated edges are valid only when all `kg/*.json` files are loaded together; individual files have cross-file references. Story records have three key shapes: 3 omit `grammar_points`, 5 use `cover_image_url`, and 60 use `suggested_prompts`.

## Gitignore/Convention Check

- Correctly ignored: `*.db`, quarantine DBs, init locks, synced manifests, `.DS_Store`, `sample_stories.expanded.json`, and the large/generated `kg_output` artifacts.
- Missing rule: add `data/*.db.wal` (or the explicit `data/kuzu_runtime.db.wal`); current rules cover `kuzu_db.wal` and `kuzu.wal` only.
- Already tracked despite ignore rules: `kg_output/topic_crawl_report.json` and `kg_output/tracecag_topic_corpus_report.json`. Ignore rules do not untrack existing files; decide whether these small provenance reports are intentional fixtures or generated outputs.
- Largest tracked data is `kg/06_tracecag_topic_expansion.json` at about 3.1 MB; no accidentally tracked 100 MB-class artifact was found.
- Naming is otherwise mostly snake_case, but `kg_checkpoint_formated.jsonl` violates both spelling and file-format conventions.
- High-confidence secret scan found no credential. External source/image URLs are ordinary public references.

## Content Gaps by CEFR/topic

- **A1:** only 4 of 68 story blueprints; thin survival dialogues for greetings, family, numbers/time, directions, transport, classroom, and basic form-filling. No complete decodable/graded reader text.
- **A2:** relatively strong topic count, but needs complete dialogues, short readings, comprehension questions, pronunciation minimal pairs, and Vietnamese-to-English correction pairs.
- **B1:** strongest representation; still lacks coherent multi-paragraph readers, listening scripts, answer keys, and productive-writing rubrics.
- **B2:** substantial KG coverage but thin IELTS-style reading/listening passages, question types, speaking cue cards, writing samples, band descriptors, and human corrections.
- **C1:** 404 expanded concepts and 7 story blueprints, but generated story language is templated and sometimes generic. Add authentic academic/professional passages, discourse/stance work, and calibrated assessment items.
- **C2:** effectively missing: 2 seed concepts, no expanded concepts, no stories. Add idiomatic nuance, register shifts, advanced collocation, rhetoric, synthesis, inference, and long-form academic/professional texts.
- **Across levels:** no clear corpus of complete graded readers; no robust IELTS reading/listening bank; no explicit error→correction→explanation pairs for Vietnamese learners; limited culture/leisure/media/social coverage (1–2 stories each); no evidence here of spaced-repetition example-sentence difficulty calibration.

## Recommended Hugging Face Datasets

Dataset pages and Hub API records were verified as existing and public on 2026-08-02. Review licenses and source terms before production use, especially entries marked non-commercial, `other`, unknown, or without a license tag.

- [`UniversalCEFR/cambridge_exams_en`](https://huggingface.co/datasets/UniversalCEFR/cambridge_exams_en) — CEFR-labelled Cambridge exam English for level calibration; CC BY-NC-SA 4.0.
- [`UniversalCEFR/elg_cefr_en`](https://huggingface.co/datasets/UniversalCEFR/elg_cefr_en) — CEFR-labelled English learner material that can broaden level classification; CC BY-NC 4.0.
- [`UniversalCEFR/cefr_sp_en`](https://huggingface.co/datasets/UniversalCEFR/cefr_sp_en) — sentence-level CEFR difficulty annotations for calibrating examples and passages; CC BY-NC-SA 4.0.
- [`bea2019st/wi_locness`](https://huggingface.co/datasets/bea2019st/wi_locness) — learner essays with grammatical-error annotations for correction pairs; license is tagged `other`.
- [`jhu-clsp/jfleg`](https://huggingface.co/datasets/jhu-clsp/jfleg) — fluency-oriented grammatical correction references; useful for natural rewrites and evaluation; CC BY-NC-SA 4.0.
- [`grammarly/coedit`](https://huggingface.co/datasets/grammarly/coedit) — diverse English text-editing instructions and revisions; useful for correction/explanation tasks; Apache 2.0.
- [`Helsinki-NLP/opus-100`](https://huggingface.co/datasets/Helsinki-NLP/opus-100) — includes English–Vietnamese parallel text for bilingual examples; Hub license tag is unknown, so verify OPUS source licenses by subset.
- [`chillies/IELTS_essay_human_feedback`](https://huggingface.co/datasets/chillies/IELTS_essay_human_feedback) — IELTS essays with human feedback for writing practice; no Hub license tag, so do not ingest until rights are confirmed.
- [`roneneldan/TinyStories`](https://huggingface.co/datasets/roneneldan/TinyStories) — simple synthetic English stories that can seed A1–A2 reader generation after CEFR filtering and human review; CDLA-Sharing 1.0.
- [`knkarthick/dialogsum`](https://huggingface.co/datasets/knkarthick/dialogsum) — everyday dialogues useful for dialogue structure and summarization exercises; CC BY-NC-SA 4.0.
- [`testliai/english-exam-vietnamese-national-hs-graduation`](https://huggingface.co/datasets/testliai/english-exam-vietnamese-national-hs-graduation) — Vietnamese national English-exam items for local learner alignment; small/low-adoption dataset, so manually validate quality; MIT.

## Suggested Next Steps

1. Add the Kuzu WAL ignore rule and decide whether the two tracked crawl reports are fixtures or should be untracked.
2. Fix the generation pipeline once: emit true JSONL, deduplicate edges/quadruples, enforce unique concept IDs, validate story required fields, and fail on missing CEFR levels.
3. Treat `sample_stories.json` as blueprints; build reviewed content packs in priority order: Vietnamese error-correction pairs, A1/A2 complete readers/dialogues, B2/C1 IELTS material, then C2.
4. Before removing any lock/quarantine/synced artifact, confirm Kuzu is stopped and preserve the quarantine DB until the current runtime DB is backed up and verified.
5. Pilot only datasets with compatible licenses; keep source ID, license, split, and transformation provenance on every imported record.
