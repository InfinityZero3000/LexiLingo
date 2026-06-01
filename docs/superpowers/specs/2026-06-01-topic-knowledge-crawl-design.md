# Topic Knowledge Crawl Design

## Goal

Build a repeatable offline script that crawls topic-focused English learning sources, uses Groq keys from the existing provider quota state, and generates enriched topic knowledge data for LexiLingo topic chat.

## Inputs

- `ai-service/data/sample_stories.json` supplies the topic list, story IDs, levels, vocabulary, grammar, objectives, and categories.
- `ai-service/data/topic_graphs.json` supplies existing topic concepts and edges to preserve and deduplicate.
- `ai-service/model-development/reports/provider_quota_state.json` supplies the Groq key pool and persisted per-key quota state.
- `crawl4ai` collects markdown content from configured public URLs per topic.

## Outputs

- Default output is non-destructive:
  - `ai-service/data/topic_graphs.enriched.json`
  - `ai-service/data/kg_output/topic_knowledge_prefix.txt`
  - `ai-service/data/kg_output/topic_crawl_report.json`
- `--merge` updates `ai-service/data/topic_graphs.json` after validation.
- `--update-prefix` can also refresh `ai-service/data/kg_output/knowledge_prefix.txt` with the topic prefix.

## Script Behavior

The script loads stories, maps each topic to curated source URLs, crawls each URL with `crawl4ai`, and sends compacted crawl text plus story context to Groq. Groq must return strict JSON containing topic concepts, vocabulary concepts, grammar/function concepts, edges, and short source notes. The script validates IDs, CEFR levels, required fields, duplicate concepts, duplicate edges, and dangling edges before writing outputs.

The quota state is treated as a key pool. Keys are rotated round-robin, success counts are persisted, and temporary failures set a cooldown. Keys are never printed in logs.

## Data Contract

Each concept uses:

```json
{"id": "topic:story_airport_checkin", "title": "Airport Check-In Adventure", "level": "A2", "keywords": "boarding pass luggage gate"}
```

Each edge uses:

```json
{"from": "topic:story_airport_checkin", "to": "concept:vocab.airport_checkin", "relation": "contains"}
```

Allowed ID prefixes are `topic:`, `entity:`, `concept:vocab.`, `concept:grammar.`, `concept:function.`, `concept:collocation.`, and `concept:phrase.`. Relations stay simple and compatible with the current KG importer: `contains`, `requires`, `related_to`, `builds_on`, `specialization_of`, `practices`, `corrects`, and `includes_cost`.

## Error Handling

If a crawl fails, the script records it in the report and continues with the story's local context. If Groq returns malformed JSON, the script retries once with a repair prompt. If no Groq key is available, the script exits without writing partial enriched outputs unless `--allow-local-fallback` is used.

## Testing

Unit tests cover quota state key rotation, JSON extraction/validation, merge deduplication, topic prefix rendering, and local fallback behavior without network calls.
