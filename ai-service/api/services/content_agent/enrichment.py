"""Fills gaps in planned vocabulary from reference snapshots (OEWN, CMUdict, ...).

Reference corpora carry no CEFR level, so they never choose which words a course
teaches. After the planner has picked its words, each reference snapshot is
searched for exactly those words and only fields the seed record lacks are filled.
"""

from __future__ import annotations

from collections import Counter
from collections.abc import Callable, Sequence
from dataclasses import dataclass, field, replace

from api.models.content_agent import (
    NormalizedSourceRecord,
    PartOfSpeech,
    SourceSnapshotDescriptor,
)
from api.services.content_agent.adapters import normalize_etl_records
from api.services.content_agent.phonetics import arpabet_to_ipa
from api.services.content_agent.planner import CurriculumPlan
from api.services.content_etl.storage import SnapshotStorage

# Mirror the backend artifact gate (content_agent_validation._DEF_MIN/MAX_CHARS).
MIN_DEFINITION_CHARS = 10
MAX_DEFINITION_CHARS = 2000
LOW_COVERAGE_RATIO = 0.5

_POS_ORDER = {
    PartOfSpeech.NOUN: 0,
    PartOfSpeech.VERB: 1,
    PartOfSpeech.ADJECTIVE: 2,
    PartOfSpeech.ADVERB: 3,
}

# A reference's `pronunciation` is only trusted in a notation we can convert.
_PRONUNCIATION_CONVERTERS: dict[str, Callable[[str], str | None]] = {
    "cmudict": arpabet_to_ipa,
}


@dataclass
class EnrichmentReport:
    words: int = 0
    matched: Counter[str] = field(default_factory=Counter)
    filled: Counter[tuple[str, str]] = field(default_factory=Counter)
    checksums: list[str] = field(default_factory=list)

    def metrics(self, sources: Sequence[str]) -> dict[str, dict[str, int]]:
        return {
            source: {
                "matched": self.matched[source],
                **{
                    name: count
                    for (src, name), count in sorted(self.filled.items())
                    if src == source
                },
            }
            for source in sources
        }

    def warnings(self, sources: Sequence[str]) -> list[str]:
        out: list[str] = []
        for source in sources:
            matched = self.matched[source]
            if matched == 0:
                out.append(
                    f"{source} matched none of the {self.words} planned words"
                )
            elif matched / self.words < LOW_COVERAGE_RATIO:
                out.append(
                    f"{source} matched {matched} of {self.words} planned words "
                    f"({matched / self.words:.0%})"
                )
        return out


def _word_key(record: NormalizedSourceRecord) -> str:
    return (record.word or "").strip().casefold()


def _pos_compatible(seed: NormalizedSourceRecord, candidate: NormalizedSourceRecord) -> bool:
    # A reference without a part of speech (CMUdict) fits any seed; otherwise a
    # noun's definition must never land on a verb.
    return (
        PartOfSpeech.PHRASE in (seed.part_of_speech, candidate.part_of_speech)
        or seed.part_of_speech == candidate.part_of_speech
    )


def _sense_rank(candidate: NormalizedSourceRecord) -> int | None:
    rank = candidate.metadata.get("sense_rank")
    return rank if isinstance(rank, int) else None


def _usable_definition(candidate: NormalizedSourceRecord) -> bool:
    # Without a rank (a snapshot from before adapter v2) the commonest sense
    # cannot be told apart, and guessing picks "informal term for a man" for dog.
    return (
        MIN_DEFINITION_CHARS <= len(candidate.definition or "") <= MAX_DEFINITION_CHARS
        and _sense_rank(candidate) is not None
    )


def _best_sense(candidates: list[NormalizedSourceRecord]) -> NormalizedSourceRecord:
    # First sense wins (WordNet orders senses by frequency). With no part of
    # speech on the seed, ties across parts of speech go noun, verb, adjective,
    # adverb; the record id only keeps the choice stable.
    return min(
        candidates,
        key=lambda c: (
            _sense_rank(c) or 0,
            _POS_ORDER.get(c.part_of_speech, len(_POS_ORDER)),
            c.record_id,
        ),
    )


def _enrich_one(
    seed: NormalizedSourceRecord,
    candidates: list[NormalizedSourceRecord],
    snapshot: SourceSnapshotDescriptor,
    report: EnrichmentReport,
) -> NormalizedSourceRecord:
    compatible = [c for c in candidates if _pos_compatible(seed, c)]
    source = snapshot.source_name
    update: dict[str, object] = {}
    taken: list[tuple[NormalizedSourceRecord, list[str]]] = []

    usable = [c for c in compatible if _usable_definition(c)]
    if not seed.definition and usable:
        sense = _best_sense(usable)
        fields = ["definition"]
        update["definition"] = sense.definition
        # An example only fits the gloss it was written for.
        if not seed.example and sense.example:
            update["example"] = sense.example
            fields.append("example")
        taken.append((sense, fields))

    convert = _PRONUNCIATION_CONVERTERS.get(source)
    voiced = next(
        (c for c in sorted(compatible, key=lambda c: c.record_id) if c.pronunciation),
        None,
    )
    ipa = convert(voiced.pronunciation or "") if convert and voiced else None
    if ipa and voiced and not seed.pronunciation:
        update["pronunciation"] = ipa
        taken.append((voiced, ["pronunciation"]))

    if not taken:
        return seed

    report.matched[source] += 1
    entries = []
    for record, fields in taken:
        for name in fields:
            report.filled[(source, name)] += 1
        report.checksums.append(str(record.checksum))
        entries.append(
            {
                "source_name": source,
                "source_version": snapshot.source_version,
                "snapshot_id": snapshot.snapshot_id,
                "record_id": record.record_id,
                "record_checksum": record.checksum,
                "license_id": snapshot.license_id,
                "license_url": snapshot.license_url,
                "attribution_text": snapshot.attribution_text,
                "fields": fields,
                "candidates": len(compatible),
            }
        )
    lineage = dict(seed.lineage or {})
    lineage["enrichment"] = [*lineage.get("enrichment", []), *entries]
    return seed.model_copy(update={**update, "lineage": lineage})


def _lookup(
    storage: SnapshotStorage,
    snapshot: SourceSnapshotDescriptor,
    words: set[str],
) -> dict[str, list[NormalizedSourceRecord]]:
    found = storage.find_records(snapshot.source_name, snapshot.source_version, words)
    return {
        word: normalize_etl_records(records)
        for word, records in found.items()
    }


def enrich_plan(
    plan: CurriculumPlan,
    *,
    storage: SnapshotStorage,
    references: Sequence[SourceSnapshotDescriptor],
) -> tuple[CurriculumPlan, EnrichmentReport]:
    seeds = {
        record.record_id: record
        for course in plan.courses
        for unit in course.units
        for lesson in unit.lessons
        for record in lesson.vocabulary
    }
    words = {_word_key(record) for record in seeds.values()} - {""}
    report = EnrichmentReport(words=len(words))
    enriched = dict(seeds)

    for snapshot in sorted(references, key=lambda item: item.source_name):
        index = _lookup(storage, snapshot, words)
        for record_id, seed in list(enriched.items()):
            candidates = index.get(_word_key(seed))
            if candidates:
                enriched[record_id] = _enrich_one(seed, candidates, snapshot, report)

    report.checksums.sort()
    courses = tuple(
        replace(
            course,
            units=tuple(
                replace(
                    unit,
                    lessons=tuple(
                        replace(
                            lesson,
                            vocabulary=tuple(
                                enriched[record.record_id]
                                for record in lesson.vocabulary
                            ),
                        )
                        for lesson in unit.lessons
                    ),
                )
                for unit in course.units
            ),
        )
        for course in plan.courses
    )
    return replace(plan, courses=courses), report

