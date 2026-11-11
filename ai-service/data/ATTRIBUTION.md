# Data sources and terms

LexiLingo is a non-commercial graduation project. Several sources below forbid commercial use (NC) or require share-alike
(SA); that is acceptable for the thesis and must be re-examined before any commercial release. Counts and hashes: `MANIFEST.json`.

| Data | Source | Licence | Used in the running app |
|---|---|---|---|
| `lexicon/cefr_vocabulary.jsonl`, `lexicon/cefrj_grammar_profile.jsonl` | CEFR-J Wordlist 1.5 and Grammar Profile (Tono Laboratory, Tokyo University of Foreign Studies); Octanove Vocabulary Profile C1/C2 1.0 (Octanove Labs); distributed by github.com/openlanguageprofiles/olp-en-cefrj | CEFR-J: free for research and commercial use with citation; Octanove: CC BY-SA 4.0 | yes |
| `kg/07_vocabulary_anki.json` | LexiLingo Anki deck + Alex123321/english_cefr_dataset | Apache-2.0 | yes |
| `kg/08_cefr_sentences.json` | UniversalCEFR/cefr_sp_en | CC BY-NC-SA 4.0 | yes |
| `kg/09_grammar_usage.json` | Teravee/1000_english-grammar-dataset | not declared | yes |
| `kg/10_collocations.json` | vladvlasov256/opensubs-collocations | CC-BY-4.0 | yes |
| `kg/11_idioms.json` | adihaviv/idiomem | MIT | yes |
| `kg/12_lexical_relations.json` | ConceptNet 5 English relations, via appledora/conceptnet_en2en_relations | CC BY 4.0 | yes |
| `kg/13_cefrj_vocabulary.json` | CEFR-J and Octanove word levels; definitions and Vietnamese from English Wiktionary via kaikki.org (Wiktextract) | CEFR-J: free with citation; Octanove, Wiktionary: CC BY-SA 4.0 | yes |
| `kg/01-06, seed_graph, knowledge_extended` | written by the project | project-owned | yes |
| `corpora/wiktionary_reference/` | en.wiktionary.org (retrieved with Firecrawl) | CC BY-SA 4.0; authors in each page's history | no (evaluation only) |
| `corpora/kaikki_reference/` | English Wiktionary structured extraction, kaikki.org | CC BY-SA 4.0 | no (evaluation and build input) |
| `corpora/gec_pairs/` | jhu-clsp/jfleg | CC BY-NC-SA 4.0 | no (not in the Docker image) |
| `corpora/parallel_en_vi/` | Helsinki-NLP/opus-100 (en-vi) | not stated by the host; OPUS subtitle sources | no (not in the Docker image) |
| `corpora/cefr_profiles/` | unmodified copy of the CEFR-J / Octanove files above | as above | no (provenance copy) |
