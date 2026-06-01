# TraceCAG Bulk Topic Corpus Design

## Goal

Expand LexiLingo topic chat from 8 topics to 68 topics and produce more than 10,000 lines of TraceCAG-ready quadruple/edge data.

## Scope

- Add 60 new UI topics to `ai-service/data/sample_stories.json`.
- Generate a large topic KG corpus:
  - `ai-service/data/kg_output/tracecag_topic_quadruples.jsonl`
  - `ai-service/data/kg_output/tracecag_topic_edges.jsonl`
  - `ai-service/data/kg_output/tracecag_knowledge_prefix.full.txt`
  - `ai-service/data/kg/06_tracecag_topic_expansion.json`
- Keep every generated topic compatible with the existing `Story` schema.
- Use TraceCAG naming in new scripts, docs, reports, and Flutter defaults.

## Data Shape

Each story includes `story_id`, localized title, CEFR level, category, estimated minutes, context, persona, vocabulary, grammar, conversation flow, suggested prompts, tags, and `is_published`.

Each quadruple is one JSONL line:

```json
{"subject":"topic:story_name","predicate":"contains","object":"concept:vocab.topic_term","context":{"evidence":"...","source_id":"TraceCAG_topic_story_name","confidence":0.92,"uncertain":false,"domain":"topic_chat"}}
```

Each edge is one JSONL line:

```json
{"source":"topic:story_name","target":"concept:vocab.topic_term","relation":"contains","confidence":0.92,"source_id":"TraceCAG_topic_story_name","uncertain":false}
```

## Generation Strategy

The generator uses curated topic blueprints and deterministic expansion rules. For each topic it creates vocabulary, grammar, speech functions, phrase concepts, common learner errors, prerequisites, CEFR links, persona links, scenario links, and practice prompts. This produces a large, stable corpus without spending Groq quota for every line.

Existing crawled/Groq-enriched data remains useful as a smaller high-quality supplement. The bulk generator focuses on breadth, UI coverage, and graph density.

## Validation

The script must validate:

- At least 50 new topics.
- More than 10,000 quadruple lines.
- More than 10,000 edge lines.
- No duplicate story IDs.
- No duplicate concept IDs in the generated KG file.
- No dangling edges in the generated KG file.
- Every story parses with the existing Pydantic `Story` schema.

## UI Changes

Flutter topic loading should request enough stories to show the new topic set, not the old default `limit=20`. Topic session defaults should use `tracecag` instead of `graphcag`.
