# Relations and Grammar V2 Report

## Outcome

- Created `grammar_rules_v2/` with **1,000** genuinely English-grammar/usage concepts and zero edges.
- Created `relations/` with **162,694** unique, non-self ConceptNet edges whose two endpoint titles both match existing LexiLingo concepts.
- Left the old `grammar_rules/` and every production/staged input untouched.

## Task 1: English grammar content verification

The live Hugging Face API and datasets-server were searched for `english grammar rules`, `ESL grammar`, `grammar explanation english`, and related terms. Candidate rows were read before selection.

### Rejected candidate

`VGraf/alpaca-eval-grammar-esl` is general instruction data with grammatical errors inserted into prompts. Sample topics included Broadway actors, US state names, kickball, music, and gift wrapping. It is not a collection of English grammar explanations, so it was rejected.

### Selected candidate

- Dataset: `Teravee/1000_english-grammar-dataset`
- Live schema: `instruction`, `question`, `answer`
- Dataset size reported by the card: 71,052 rows
- License: **not declared in the Hugging Face dataset card**. This is recorded rather than guessing a license.
- Output: 1,000 unique rows in `grammar_rules_v2/nodes.csv` and `grammar_rules_v2/graph.json`; `grammar_rules_v2/edges.csv` is empty as requested.

Real rows inspected before use included:

1. **How can I negate or confirm a question tersely using negation?** — explains how English speakers interpret `yes` and `no` after negative questions.
2. **Is there any difference between being ill and sick?** — discusses English word choice and usage.
3. **Is there any difference between “which” and “that”?** — explains restrictive and nonrestrictive relative clauses.
4. **How would a native speaker understand "Time flies like an arrow"?** — analyzes English syntax and ambiguity.
5. **Large, huge or big communities?** — explains English adjective choice and degree.
6. **Dates and times: "on", "in", "at"?** — gives English preposition rules for times, days, and months.
7. **Between two options, which does "former" refer to and which does "latter"?** — explains reference order in English.
8. **Is there a general rule for Verb + Preposition/Particle idioms, such as "come across"?** — explains English phrasal/prepositional verbs.

These samples are about English grammar, syntax, and usage—the language LexiLingo teaches. They are not foreign-language grammar merely explained in English.

## Task 2: real lexical relations

- Dataset: `appledora/conceptnet_en2en_relations`
- Resource: English-to-English ConceptNet 5 relations
- Hugging Face license tag: `cc-by-4.0`
- Total triples fetched across all four datasets-server parquet shards: **3,410,326**
- Triples with both normalized titles matched to known LexiLingo concepts: **185,050**
- Unique non-self `(from_id, to_id, relation)` edges after deduplication: **162,694**
- Existing concepts referenced: **7,474**

Matching used Unicode NFKC normalization, case folding, and underscore/hyphen-to-space normalization. No fuzzy matching or fabricated endpoints were allowed. Full source, mapping, filtering, and 20 examples are in `relations/RELATIONS_REPORT.md`.

## Real renderer verification

The real `render_knowledge_prefix()` was imported from `scripts/crawl_topic_knowledge.py`. Its combined input used all **7,997** concepts from the existing `merged_kg/nodes.csv` plus the new relation edges. It produced relation lines, including:

```text
- (a.m. (Vocabulary)) -[antonym]-> (afternoon (Vocabulary)) [Source: topic_crawl]
- (a.m. (Vocabulary)) -[related_to]-> (before (Vocabulary)) [Source: topic_crawl]
- (a.m. (Vocabulary)) -[related_to]-> (noon (Vocabulary)) [Source: topic_crawl]
- (a.m. (Vocabulary)) -[antonym]-> (p.m. (Vocabulary)) [Source: topic_crawl]
- (abandon (Vocabulary)) -[antonym]-> (acquire (Vocabulary)) [Source: topic_crawl]
- (abandon (Vocabulary)) -[related_to]-> (adhere (Vocabulary)) [Source: topic_crawl]
- (abandon (Vocabulary)) -[related_to]-> (artificial (Vocabulary)) [Source: topic_crawl]
- (abandon (Vocabulary)) -[related_to]-> (constraint (Vocabulary)) [Source: topic_crawl]
- (abandon (Vocabulary)) -[related_to]-> (depart (Vocabulary)) [Source: topic_crawl]
- (abandon (Vocabulary)) -[related_to]-> (desert (Vocabulary)) [Source: topic_crawl]
```

This proves the new data is visible to the renderer rather than producing only the knowledge-base header.

## Fresh Kuzu verification

- Scratch database: `/tmp/lexilingo_relations_test.kuzu` (deleted/recreated before the test)
- Nodes offered/loaded from existing `merged_kg/nodes.csv`: **7,997 / 7,997**
- New relation edges offered: **162,694**
- Edges whose two endpoints exist in the merged-node subset: **148,413**
- Edges loaded: **148,413**
- Errors: **none**

The remaining 14,281 valid edges reference production/topic/collocation/idiom concepts allowed by the requested global lookup but absent from `merged_kg/nodes.csv`; Kuzu correctly did not load relationships without both endpoint nodes in this scratch subset. A review also removed 3,615 self-loops because they add no foundational relation signal.
