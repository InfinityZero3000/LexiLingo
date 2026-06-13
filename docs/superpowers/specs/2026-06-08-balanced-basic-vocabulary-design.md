# Balanced Basic Vocabulary Design

## Goal

Provide exactly 200 valid starter vocabulary items, distribute them nearly
equally across the six system topics, and prevent placeholder content such as
`#N/A yet` from reaching vocabulary lists or review sessions.

## Diagnosis

The current starter catalog is defined indirectly by the `basic_200` tag.
`tag_basic_words.py` assigns that tag to the first 200 rows of an import file
without validating definitions or balancing topics.

The historical categorized dataset contains 964 placeholder definitions. It
also distributes its first 200 entries unevenly: 102 are `general`, while
`travel` has 3, `technology` has 5, and `science` has none. Topic queries are
ordered alphabetically, which makes unusual capitalized entries such as
`AIDS` appear near the beginning of a session when their tag is selected.

## Selection Policy

The six canonical starter topics are:

- `general`: 34 words
- `travel`: 34 words
- `business`: 33 words
- `daily`: 33 words
- `science`: 33 words
- `technology`: 33 words

Selection is deterministic. Within each topic, valid candidates are ordered by
descending `usage_frequency`, then normalized word and ID. A vocabulary item
may fill only one starter-topic quota, so the selected set always contains 200
unique items.

`daily_life` is accepted as a legacy alias for `daily`. Selected items receive
both `basic_200` and their canonical topic tag. Existing unrelated tags remain
unchanged.

An item is invalid for starter or study results when its definition is blank
or is a placeholder after trimming and case normalization. Placeholder values
include `#N/A`, `#N/A yet`, `N/A`, `N/A yet`, `not available`, and equivalent
empty punctuation/whitespace variants.

## Runtime Protection

A focused vocabulary catalog policy module owns:

- canonical topic names and quotas;
- legacy topic aliases;
- placeholder-definition detection;
- deterministic balanced selection.

The vocabulary CRUD layer applies the policy in two places:

- master-list/topic queries exclude invalid definitions;
- starter seeding only uses the validated `basic_200` catalog.

This keeps malformed records out of Flutter even if a future import or a
partially migrated database introduces them again.

## Data Migration

An Alembic data migration will:

1. Load vocabulary candidates and normalize list/string tag payloads.
2. Select the balanced 200-item starter set with the shared policy.
3. Remove `basic_200` from records outside the new set.
4. Add `basic_200` and the selected canonical topic tag to records in the set.
5. Remove unreviewed placeholder items from user collections.
6. For users already marked as seeded, remove unreviewed old starter entries
   that are outside the new set and add missing new starter entries.
7. Preserve reviewed vocabulary and custom-deck references.

The migration fails with a clear error when any topic lacks enough valid
candidates. It must never silently create an undersized or unbalanced starter
catalog.

## API Behavior

The existing API contract remains unchanged. System topic cards continue to
request their current tags and receive up to 20 items. The `daily` topic also
matches legacy `daily_life` data during the transition.

Topic ordering changes from alphabetical order to frequency-first ordering,
with normalized word as the deterministic tie-breaker. This makes sessions
start with useful common vocabulary rather than whichever word sorts first.

## Verification

- Unit tests cover placeholder normalization and exact topic quotas.
- CRUD tests prove invalid records are excluded and `daily_life` maps to
  `daily`.
- Seeding tests assert exactly 200 unique valid starter words.
- Migration-focused tests cover tag normalization and existing-user
  reconciliation where practical.
- Focused backend tests and the complete vocabulary test suite pass.

