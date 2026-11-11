# CEFR lexicon

Reference data, not a graph. Rebuild with `python scripts/build_cefr_lexicon.py`.

| File | Rows | Source | Terms |
|---|---|---|---|
| `cefr_vocabulary.jsonl` | 9935 | CEFR-J Wordlist 1.5 (A1-B2) + Octanove Vocabulary Profile C1/C2 1.0 | CEFR-J: free for research and commercial use if cited; Octanove: CC BY-SA 4.0 (share alike) |
| `cefrj_grammar_profile.jsonl` | 500 | CEFR-J Grammar Profile 20180315 (partly translated from Japanese) | as CEFR-J, cite |

Cite: The CEFR-J Wordlist Version 1.5, compiled by Yukio Tono, Tokyo University of Foreign Studies (http://www.cefr-j.org/download.html);
The CEFR-J Grammar Profile Version 20180315; Octanove Labs, Octanove Vocabulary Profile C1/C2 1.0.
Distributed through https://github.com/openlanguageprofiles/olp-en-cefrj . The copyright of the CEFR-J data belongs to the
Tono Laboratory at TUFS; neither CEFR-J nor Open Language Profiles is liable for inaccuracies.

`cefr_vocabulary.jsonl`: `word` (first spelling), `variants` (all spellings in the source row), `pos`, `cefr`, `source`.
A word with several parts of speech has one row each, and may carry different levels.
