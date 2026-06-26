"""One test per blocking validation gate in content_agent_validation."""

from __future__ import annotations

import copy

from app.services.content_agent_validation import validate_artifact


def _base_artifact() -> dict:
    """Minimal valid artifact that passes all gates."""
    return {
        "schema_version": 2,
        "prompt_version": "cefr-course-v2",
        "generation_key": "a" * 64,
        "source_manifest": [
            {
                "snapshot_id": f"cefr_j:1.0:{'b' * 64}",
                "source_name": "cefr_j",
                "source_version": "1.0",
                "official_url": "https://github.com/openlanguageprofiles/olp-en-cefrj",
                "license_id": "LicenseRef-CEFR-J-Commercial",
                "license_url": "https://lexilingo.me/licenses/cefr-j",
                "attribution_text": "CEFR-J licensed dataset",
                "retrieved_at": "2026-06-15T00:00:00Z",
                "raw_checksum": "b" * 64,
                "normalized_sha256": "c" * 64,
                "normalized_bytes": 128,
                "record_checksum_root": "d" * 64,
                "adapter_version": 1,
                "record_count": 1,
            }
        ],
        "courses": [
            {
                "title": "Test Course A1",
                "language": "en",
                "level": "A1",
                "tags": [],
                "units": [
                    {
                        "title": "Unit 1",
                        "order_index": 0,
                        "lessons": [
                            {
                                "title": "Lesson 1",
                                "order_index": 0,
                                "estimated_minutes": 10,
                                "xp_reward": 20,
                                "vocabulary": [
                                    {
                                        "word": "hello",
                                        "definition": "A common greeting used to begin a conversation.",
                                        "part_of_speech": "interjection",
                                        "difficulty_level": "A1",
                                        "license_mode": "generated",
                                        "source_name": "generated",
                                        "topic": "greetings",
                                    }
                                ],
                                "exercises": [
                                    {
                                        "id": "ex-001",
                                        "type": "multiple_choice",
                                        "ui_type": "multiple_choice",
                                        "question": "What does 'hello' mean?",
                                        "options": ["A greeting", "Goodbye", "Thank you"],
                                        "correct_answer": "A greeting",
                                        "difficulty": 1,
                                        "points": 10,
                                    }
                                ],
                            }
                        ],
                    }
                ],
            }
        ],
        "quality": {"blocking_errors": [], "warnings": [], "metrics": {}},
    }


def _pins(artifact: dict) -> list[dict]:
    return [dict(artifact["source_manifest"][0])]


def test_valid_artifact_passes_all_gates() -> None:
    artifact = _base_artifact()
    report = validate_artifact(artifact, pinned_snapshots=_pins(artifact))
    assert not report.is_blocking
    assert report.metrics["course_count"] == 1
    assert report.metrics["lesson_count"] == 1


# --- schema_version gate ---


def test_wrong_schema_version_is_blocking() -> None:
    art = _base_artifact()
    art["schema_version"] = 1
    report = validate_artifact(art)
    codes = {e.code for e in report.blocking_errors}
    assert "SCHEMA_VERSION" in codes


def test_missing_schema_version_is_blocking() -> None:
    art = _base_artifact()
    del art["schema_version"]
    report = validate_artifact(art)
    codes = {e.code for e in report.blocking_errors}
    assert "SCHEMA_VERSION" in codes


# --- manifest_coverage gate ---


def test_empty_manifest_is_blocking() -> None:
    art = _base_artifact()
    art["source_manifest"] = []
    report = validate_artifact(art)
    codes = {e.code for e in report.blocking_errors}
    assert "MANIFEST_EMPTY" in codes


def test_manifest_non_object_entry_is_blocking() -> None:
    art = _base_artifact()
    art["source_manifest"] = ["not-an-object"]
    report = validate_artifact(art)
    codes = {e.code for e in report.blocking_errors}
    assert "MANIFEST_ENTRY_TYPE" in codes


def test_manifest_missing_integrity_fields_is_blocking() -> None:
    art = _base_artifact()
    del art["source_manifest"][0]["raw_checksum"]
    report = validate_artifact(art)
    assert "MANIFEST_FIELDS_MISSING" in {
        error.code for error in report.blocking_errors
    }


def test_pinned_snapshot_mismatch_is_blocking() -> None:
    art = _base_artifact()
    pin = dict(art["source_manifest"][0])
    pin["raw_checksum"] = "c" * 64
    report = validate_artifact(art, pinned_snapshots=[pin])
    assert "PINNED_SNAPSHOT_MISMATCH" in {
        error.code for error in report.blocking_errors
    }


# --- course level gate ---


def test_invalid_course_level_is_blocking() -> None:
    art = _base_artifact()
    art["courses"][0]["level"] = "Z9"
    report = validate_artifact(art)
    codes = {e.code for e in report.blocking_errors}
    assert "INVALID_COURSE_LEVEL" in codes


def test_courses_must_be_a_list_without_crashing() -> None:
    art = _base_artifact()
    art["courses"] = "not-a-list"
    report = validate_artifact(art)
    codes = {e.code for e in report.blocking_errors}
    assert "COURSES_TYPE" in codes
    assert report.metrics["course_count"] == 0


def test_course_and_child_entries_must_be_objects_without_crashing() -> None:
    art = _base_artifact()
    art["courses"] = [
        "not-a-course",
        {
            "title": "Broken course",
            "level": "A1",
            "units": [
                "not-a-unit",
                {
                    "title": "Broken unit",
                    "order_index": 0,
                    "lessons": [
                        "not-a-lesson",
                        {
                            "title": "Broken lesson",
                            "order_index": 0,
                            "vocabulary": ["not-vocabulary"],
                            "exercises": ["not-exercise"],
                        },
                    ],
                },
            ],
        },
    ]
    report = validate_artifact(art)
    codes = {e.code for e in report.blocking_errors}
    assert {
        "COURSE_ENTRY_TYPE",
        "UNIT_ENTRY_TYPE",
        "LESSON_ENTRY_TYPE",
        "VOCABULARY_ENTRY_TYPE",
        "EXERCISE_ENTRY_TYPE",
    }.issubset(codes)


def test_empty_units_and_lessons_are_blocking() -> None:
    art = _base_artifact()
    art["courses"][0]["units"] = []
    report = validate_artifact(art)
    assert "NO_UNITS" in {error.code for error in report.blocking_errors}

    art = _base_artifact()
    art["courses"][0]["units"][0]["lessons"] = []
    report = validate_artifact(art)
    assert "NO_LESSONS" in {error.code for error in report.blocking_errors}


# --- license gate ---


def test_unstorable_license_mode_is_blocking() -> None:
    art = _base_artifact()
    art["courses"][0]["units"][0]["lessons"][0]["vocabulary"][0]["license_mode"] = "scraped"
    report = validate_artifact(art)
    codes = {e.code for e in report.blocking_errors}
    assert "INVALID_LICENSE_MODE" in codes


def test_generated_vocab_cannot_claim_imported_license_mode() -> None:
    art = _base_artifact()
    vocab = art["courses"][0]["units"][0]["lessons"][0]["vocabulary"][0]
    vocab["license_mode"] = "approved_dataset"
    report = validate_artifact(art, pinned_snapshots=_pins(art))
    assert "GENERATED_LICENSE_MODE_INVALID" in {
        error.code for error in report.blocking_errors
    }


def test_admin_upload_manifest_must_match_attested_upload() -> None:
    art = _base_artifact()
    manifest = {
        "snapshot_id": f"admin_upload:job:test:{'d' * 64}",
        "source_name": "admin_upload",
        "source_version": "job-upload-v1",
        "official_url": "https://lexilingo.me/admin/content-agent/uploads",
        "license_id": "LicenseRef-Admin-Owned",
        "license_url": "https://lexilingo.me/legal/content-upload-rights",
        "attribution_text": "Administrator-owned or licensed upload",
        "retrieved_at": "2026-06-15T00:00:00Z",
        "raw_checksum": "b" * 64,
        "normalized_sha256": "c" * 64,
        "normalized_bytes": 128,
        "record_checksum_root": "d" * 64,
        "adapter_version": 1,
        "record_count": 1,
    }
    art["source_manifest"] = [manifest]
    vocab = art["courses"][0]["units"][0]["lessons"][0]["vocabulary"][0]
    vocab.update(
        {
            "source_name": "admin_upload",
            "license_mode": "admin_owned",
            "source_version": "job-upload-v1",
            "source_record_id": "admin_upload:1:hello",
            "license_id": "LicenseRef-Admin-Owned",
            "license_url": "https://lexilingo.me/legal/content-upload-rights",
            "attribution_text": "Administrator-owned or licensed upload",
            "raw_checksum": "b" * 64,
            "record_checksum": "1" * 64,
            "lineage": {
                "adapter": "admin_upload",
                "adapter_version": 1,
                "raw_path": "content-agent-upload/test",
            },
            "content_usage": "full_text",
        }
    )
    report = validate_artifact(
        art,
        admin_upload={"checksum": "e" * 64, "row_count": 1},
    )
    assert "ADMIN_UPLOAD_CHECKSUM_MISMATCH" in {
        error.code for error in report.blocking_errors
    }


# --- unique lesson orders gate ---


def test_duplicate_lesson_order_is_blocking() -> None:
    art = _base_artifact()
    lesson = art["courses"][0]["units"][0]["lessons"][0]
    second = copy.deepcopy(lesson)
    second["title"] = "Lesson 2 (duplicate order)"
    art["courses"][0]["units"][0]["lessons"].append(second)
    report = validate_artifact(art)
    codes = {e.code for e in report.blocking_errors}
    assert "DUPLICATE_LESSON_ORDER" in codes


# --- definition length gate ---


def test_definition_too_short_is_blocking() -> None:
    art = _base_artifact()
    art["courses"][0]["units"][0]["lessons"][0]["vocabulary"][0]["definition"] = "short"
    report = validate_artifact(art)
    codes = {e.code for e in report.blocking_errors}
    assert "DEFINITION_TOO_SHORT" in codes


def test_definition_empty_is_blocking() -> None:
    art = _base_artifact()
    art["courses"][0]["units"][0]["lessons"][0]["vocabulary"][0]["definition"] = ""
    report = validate_artifact(art)
    codes = {e.code for e in report.blocking_errors}
    assert "DEFINITION_TOO_SHORT" in codes


# --- POS enum gate ---


def test_invalid_pos_is_blocking() -> None:
    art = _base_artifact()
    art["courses"][0]["units"][0]["lessons"][0]["vocabulary"][0]["part_of_speech"] = "gerund"
    report = validate_artifact(art)
    codes = {e.code for e in report.blocking_errors}
    assert "INVALID_POS" in codes


# --- CEFR enum gate ---


def test_invalid_vocab_cefr_is_blocking() -> None:
    art = _base_artifact()
    art["courses"][0]["units"][0]["lessons"][0]["vocabulary"][0]["difficulty_level"] = "X1"
    report = validate_artifact(art)
    codes = {e.code for e in report.blocking_errors}
    assert "INVALID_VOCAB_CEFR" in codes


# --- URL gate ---


def test_invalid_source_url_is_blocking() -> None:
    art = _base_artifact()
    art["courses"][0]["units"][0]["lessons"][0]["vocabulary"][0]["source_url"] = "not-a-url"
    report = validate_artifact(art)
    codes = {e.code for e in report.blocking_errors}
    assert "INVALID_SOURCE_URL" in codes


def test_valid_source_url_passes() -> None:
    art = _base_artifact()
    art["courses"][0]["units"][0]["lessons"][0]["vocabulary"][0]["source_url"] = (
        "https://example.com/word"
    )
    report = validate_artifact(art)
    assert "INVALID_SOURCE_URL" not in {e.code for e in report.blocking_errors}


# --- exercise id gate ---


def test_missing_exercise_id_is_blocking() -> None:
    art = _base_artifact()
    art["courses"][0]["units"][0]["lessons"][0]["exercises"][0]["id"] = ""
    report = validate_artifact(art)
    codes = {e.code for e in report.blocking_errors}
    assert "EXERCISE_MISSING_ID" in codes


def test_duplicate_exercise_id_is_blocking() -> None:
    art = _base_artifact()
    lesson = art["courses"][0]["units"][0]["lessons"][0]
    second_ex = copy.deepcopy(lesson["exercises"][0])
    second_ex["question"] = "A different question?"
    lesson["exercises"].append(second_ex)
    report = validate_artifact(art)
    codes = {e.code for e in report.blocking_errors}
    assert "DUPLICATE_EXERCISE_ID" in codes


# --- type/ui_type gate ---


def test_invalid_exercise_type_is_blocking() -> None:
    art = _base_artifact()
    art["courses"][0]["units"][0]["lessons"][0]["exercises"][0]["type"] = "drag_drop"
    report = validate_artifact(art)
    codes = {e.code for e in report.blocking_errors}
    assert "INVALID_EXERCISE_TYPE" in codes


def test_missing_ui_type_is_blocking() -> None:
    art = _base_artifact()
    art["courses"][0]["units"][0]["lessons"][0]["exercises"][0]["ui_type"] = ""
    report = validate_artifact(art)
    codes = {e.code for e in report.blocking_errors}
    assert "MISSING_UI_TYPE" in codes


def test_ui_type_must_match_base_exercise_type() -> None:
    art = _base_artifact()
    art["courses"][0]["units"][0]["lessons"][0]["exercises"][0][
        "ui_type"
    ] = "dictation"
    report = validate_artifact(art)
    assert "EXERCISE_UI_TYPE_MISMATCH" in {
        error.code for error in report.blocking_errors
    }


# --- options gate ---


def test_mc_with_only_one_option_is_blocking() -> None:
    art = _base_artifact()
    art["courses"][0]["units"][0]["lessons"][0]["exercises"][0]["options"] = ["Only one"]
    report = validate_artifact(art)
    codes = {e.code for e in report.blocking_errors}
    assert "MC_INSUFFICIENT_OPTIONS" in codes


# --- audio question gate ---


def test_audio_exercise_without_question_is_blocking() -> None:
    art = _base_artifact()
    ex = art["courses"][0]["units"][0]["lessons"][0]["exercises"][0]
    ex["audio_url"] = "https://cdn.example.com/audio.mp3"
    ex["question"] = ""
    report = validate_artifact(art)
    codes = {e.code for e in report.blocking_errors}
    assert "MISSING_AUDIO_QUESTION" in codes


# --- counts gate ---


def test_lesson_with_no_vocabulary_is_blocking() -> None:
    art = _base_artifact()
    art["courses"][0]["units"][0]["lessons"][0]["vocabulary"] = []
    report = validate_artifact(art)
    codes = {e.code for e in report.blocking_errors}
    assert "NO_VOCABULARY" in codes


def test_lesson_with_no_exercises_is_blocking() -> None:
    art = _base_artifact()
    art["courses"][0]["units"][0]["lessons"][0]["exercises"] = []
    report = validate_artifact(art)
    codes = {e.code for e in report.blocking_errors}
    assert "NO_EXERCISES" in codes


# --- translation shape (warning only) ---


def test_empty_translation_vi_is_warning_not_blocking() -> None:
    art = _base_artifact()
    art["courses"][0]["units"][0]["lessons"][0]["vocabulary"][0]["translation_vi"] = ""
    report = validate_artifact(art, pinned_snapshots=_pins(art))
    warn_codes = {w.code for w in report.warnings}
    assert "EMPTY_TRANSLATION_VI" in warn_codes
    assert not report.is_blocking


# --- metrics ---


def test_metrics_counts_are_accurate() -> None:
    art = _base_artifact()
    report = validate_artifact(art, pinned_snapshots=_pins(art))
    assert report.metrics["vocabulary_count"] == 1
    assert report.metrics["exercise_count"] == 1
    assert report.metrics["unit_count"] == 1
