# Lexical Relations Report

## Source

- Dataset: `appledora/conceptnet_en2en_relations`
- Upstream resource: ConceptNet 5 English-to-English relations
- Hugging Face dataset license tag: `cc-by-4.0`
- Live datasets-server verification: schema included `rel`, `concept1`, and `concept2`; sampled rows contained genuine labeled ConceptNet relations such as `/r/RelatedTo`.

## Filtering

- Total candidate triples fetched: **3,410,326**
- Candidate triples where both normalized endpoint titles matched known LexiLingo concepts: **185,050**
- Unique matched, non-self edges written after exact `(from_id, to_id, relation)` deduplication: **162,694**
- Known concept IDs scanned: **14,158**
- Concepts referenced by output edges: **7,474**
- Matching: Unicode NFKC + case-folding + underscore/hyphen-to-space normalization; no fuzzy or fabricated matches.
- Self-loops are excluded because they add no useful relational structure.
- Ambiguous normalized titles resolve deterministically to the first source in this order: production `data/kg/*.json`, `data/topic_graphs*.json`, then merged/collocation/idiom CSVs.

## Relation mapping

- `IsA` -> `is_a`
- `RelatedTo`, `Synonym`, `SimilarTo` -> `related_to`
- `PartOf` -> `part_of`
- Other real ConceptNet labels are preserved in lower snake case (for example `Antonym` -> `antonym`).

## 20 matched examples

1. `concept:vocab.cefr-word-00739-e42932b7a7` (blur) -[`related_to`]-> `concept:vocab.confusion` (confusion)
2. `concept:vocab.cefr-word-00739-e42932b7a7` (blur) -[`related_to`]-> `concept:vocab.doubt` (doubt)
3. `concept:vocab.cefr-word-00739-e42932b7a7` (blur) -[`related_to`]-> `concept:vocab.moral` (moral)
4. `concept:vocab.cefr-word-00739-e42932b7a7` (blur) -[`related_to`]-> `concept:vocab.stain` (stain)
5. `concept:vocab.cefr-word-00739-e42932b7a7` (blur) -[`related_to`]-> `concept:vocab.dim` (dim)
6. `concept:vocab.cefr-word-00739-e42932b7a7` (blur) -[`related_to`]-> `concept:vocab.focus` (focus)
7. `concept:vocab.cefr-word-00739-e42932b7a7` (blur) -[`related_to`]-> `concept:vocab.input` (input)
8. `concept:vocab.cefr-word-00739-e42932b7a7` (blur) -[`related_to`]-> `concept:vocab.obscure` (obscure)
9. `concept:vocab.cefr-word-00740-4625e7ac04` (blurt) -[`related_to`]-> `concept:vocab.outburst` (outburst)
10. `concept:vocab.cefr-word-00740-4625e7ac04` (blurt) -[`related_to`]-> `concept:vocab.out` (out)
11. `concept:vocab.cefr-word-00740-4625e7ac04` (blurt) -[`related_to`]-> `concept:vocab.quickly` (quickly)
12. `concept:vocab.cefr-word-00740-4625e7ac04` (blurt) -[`related_to`]-> `concept:vocab.suddenly` (suddenly)
13. `concept:vocab.cefr-word-00740-4625e7ac04` (blurt) -[`related_to`]-> `concept:vocab.thought` (thought)
14. `concept:vocab.cefr-word-00740-4625e7ac04` (blurt) -[`related_to`]-> `concept:vocab.utter` (utter)
15. `concept:collocation.blurt-out` (blurt out) -[`related_to`]-> `concept:vocab.say` (say)
16. `concept:collocation.blurt-out` (blurt out) -[`related_to`]-> `concept:vocab.suddenly` (suddenly)
17. `concept:collocation.blurt-out` (blurt out) -[`related_to`]-> `concept:vocab.thinking` (thinking)
18. `concept:vocab.cefr-word-00741-13de8a510f` (blush) -[`related_to`]-> `concept:vocab.cheek` (cheek)
19. `concept:vocab.cefr-word-00741-13de8a510f` (blush) -[`related_to`]-> `concept:vocab.color` (color)
20. `concept:vocab.cefr-word-00741-13de8a510f` (blush) -[`related_to`]-> `concept:vocab.embarrassed` (embarrassed)
