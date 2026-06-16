import React, { useEffect, useState } from "react";
import { ShieldCheck, Sparkles, Upload, X } from "lucide-react";

import {
  CEFR_LEVELS,
  createContentAgentJob,
  getSourceCatalog,
  uploadContentAgentFile,
  type CefrLevel,
  type ContentAgentJob,
  type ContentAgentJobCreate,
  type ContentAgentSource,
  type SourceSnapshot,
} from "../../lib/contentAgentApi";
import { useI18n } from "../../lib/i18n";

const MAX_UPLOAD_BYTES = 5 * 1024 * 1024;

const CORE_LEXICAL_SOURCES: readonly string[] = ["oewn", "cmudict", "cefr_j", "wikidata"];

export type ContentAgentFormState = {
  levels: CefrLevel[];
  sources: string[];
  courseTitle: string;
  topicFocus: string;
  unitsPerCourse: number;
  lessonsPerUnit: number;
  vocabularyPerLesson: number;
  exerciseCount: number;
  speakingExerciseCount: number;
  listeningExerciseCount: number;
  confidenceThreshold: number;
  previewOnly: true;
  acknowledgedDraft: boolean;
  revision: boolean;
  uploadAttestation: boolean;
};

export const createDefaultContentAgentForm = (): ContentAgentFormState => ({
  levels: [...CEFR_LEVELS],
  sources: [],
  courseTitle: "",
  topicFocus: "",
  unitsPerCourse: 3,
  lessonsPerUnit: 4,
  vocabularyPerLesson: 10,
  exerciseCount: 10,
  speakingExerciseCount: 2,
  listeningExerciseCount: 2,
  confidenceThreshold: 0.75,
  previewOnly: true,
  acknowledgedDraft: false,
  revision: false,
  uploadAttestation: false,
});

export const validateContentAgentUpload = (file: File): string | null => {
  const extension = file.name.toLowerCase().split(".").pop();
  if (extension !== "csv" && extension !== "json") {
    return "Upload must be a CSV or JSON file.";
  }
  if (file.size > MAX_UPLOAD_BYTES) {
    return "Upload must be 5 MB or smaller.";
  }
  if (file.size === 0) {
    return "Upload cannot be empty.";
  }
  return null;
};

export const validateContentAgentForm = (
  form: ContentAgentFormState,
  hasUpload = false,
): string | null => {
  if (form.levels.length === 0) return "Select at least one CEFR level.";
  if (form.sources.length === 0 && !hasUpload) {
    return "Select at least one approved source or upload a file.";
  }
  if (hasUpload && !form.uploadAttestation) {
    return "You must confirm rights before uploading";
  }
  if (
    form.vocabularyPerLesson < 8 ||
    form.vocabularyPerLesson > 12
  ) {
    return "Vocabulary per lesson must be between 8 and 12.";
  }
  if (form.unitsPerCourse < 1 || form.unitsPerCourse > 10) {
    return "Units per course must be between 1 and 10.";
  }
  if (form.lessonsPerUnit < 1 || form.lessonsPerUnit > 20) {
    return "Lessons per unit must be between 1 and 20.";
  }
  if (
    form.exerciseCount < 4 ||
    form.speakingExerciseCount < 0 ||
    form.listeningExerciseCount < 0 ||
    form.speakingExerciseCount + form.listeningExerciseCount >
      form.exerciseCount
  ) {
    return "Exercise mix must fit inside the total exercise count.";
  }
  if (
    form.confidenceThreshold < 0.5 ||
    form.confidenceThreshold > 0.99
  ) {
    return "Confidence threshold must be between 0.50 and 0.99.";
  }
  if (!form.acknowledgedDraft) {
    return "Acknowledge that generated courses remain drafts.";
  }
  return null;
};

type ContentAgentModalProps = {
  onClose: () => void;
  onJobCreated: (job: ContentAgentJob) => void;
};

export function ContentAgentModal({
  onClose,
  onJobCreated,
}: ContentAgentModalProps) {
  const { t } = useI18n();
  const [form, setForm] = useState<ContentAgentFormState>(
    createDefaultContentAgentForm,
  );
  const [upload, setUpload] = useState<File | null>(null);
  const [uploadError, setUploadError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const [catalog, setCatalog] = useState<SourceSnapshot[]>([]);
  const [catalogLoading, setCatalogLoading] = useState(true);
  const [catalogError, setCatalogError] = useState<string | null>(null);

  useEffect(() => {
    let disposed = false;
    setCatalogLoading(true);
    setCatalogError(null);

    getSourceCatalog()
      .then((snapshots) => {
        if (disposed) return;
        setCatalog(snapshots);
        const preselected = snapshots
          .filter(
            (s) =>
              s.status === "active" &&
              s.enabled &&
              CORE_LEXICAL_SOURCES.includes(s.source_id),
          )
          .map((s) => s.source_id);
        setForm((current) => ({ ...current, sources: preselected }));
      })
      .catch((err) => {
        if (!disposed) {
          setCatalogError(
            err instanceof Error ? err.message : t.contentAgent.sourceError,
          );
        }
      })
      .finally(() => {
        if (!disposed) setCatalogLoading(false);
      });

    return () => {
      disposed = true;
    };
  }, [t.contentAgent.sourceError]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape" && !submitting) onClose();
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [onClose, submitting]);

  const toggleLevel = (level: CefrLevel) => {
    setForm((current) => ({
      ...current,
      levels: current.levels.includes(level)
        ? current.levels.filter((item) => item !== level)
        : [...current.levels, level],
    }));
  };

  const toggleSource = (sourceId: string) => {
    setForm((current) => ({
      ...current,
      sources: current.sources.includes(sourceId)
        ? current.sources.filter((item) => item !== sourceId)
        : [...current.sources, sourceId],
    }));
  };

  const handleUpload = (file: File | null) => {
    setUpload(file);
    const nextError = file ? validateContentAgentUpload(file) : null;
    setUploadError(nextError);
  };

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    const validationError = validateContentAgentForm(form, Boolean(upload));
    const fileError = upload ? validateContentAgentUpload(upload) : null;
    if (validationError || fileError) {
      setError(validationError);
      setUploadError(fileError);
      return;
    }

    setSubmitting(true);
    setError(null);
    try {
      const uploaded = upload
        ? await uploadContentAgentFile(upload, form.uploadAttestation)
        : null;
      const sources: ContentAgentSource[] = form.sources as ContentAgentSource[];
      if (uploaded && !sources.includes("admin_upload")) {
        sources.push("admin_upload");
      }

      const payload: ContentAgentJobCreate = {
        levels: form.levels,
        sources,
        ...(uploaded ? { upload_id: uploaded.id } : {}),
        ...(form.courseTitle.trim()
          ? { title_focus: form.courseTitle.trim() }
          : {}),
        topic_focus: form.topicFocus
          .split(",")
          .map((topic) => topic.trim())
          .filter(Boolean),
        units_per_course: form.unitsPerCourse,
        lessons_per_unit: form.lessonsPerUnit,
        words_per_lesson: form.vocabularyPerLesson,
        exercises_per_lesson: form.exerciseCount,
        exercise_mix: {
          speaking: form.speakingExerciseCount,
          listening: form.listeningExerciseCount,
        },
        confidence_threshold: form.confidenceThreshold,
        revision: form.revision,
        apply_on_success: false,
      };

      const job = await createContentAgentJob(payload);
      onJobCreated(job);
    } catch (requestError) {
      setError(
        requestError instanceof Error
          ? requestError.message
          : t.contentAgent.createFailed,
      );
    } finally {
      setSubmitting(false);
    }
  };

  const formatLastSync = (lastSyncAt: string | null): string => {
    if (!lastSyncAt) return t.common.never;
    try {
      return new Date(lastSyncAt).toLocaleDateString();
    } catch {
      return lastSyncAt;
    }
  };

  return (
    <div
      className="modal-overlay content-agent-modal-overlay"
      onMouseDown={() => !submitting && onClose()}
    >
      <section
        aria-labelledby="content-agent-modal-title"
        aria-modal="true"
        className="modal-content content-agent-modal"
        onMouseDown={(event) => event.stopPropagation()}
        role="dialog"
      >
        <header className="content-agent-modal__header">
          <div className="content-agent-title-lockup">
            <span className="content-agent-title-icon" aria-hidden="true">
              <Sparkles size={19} />
            </span>
            <div>
              <h3 id="content-agent-modal-title">
                {t.contentAgent.configureTitle}
              </h3>
              <p>{t.contentAgent.configureDescription}</p>
            </div>
          </div>
          <button
            aria-label={t.common.close}
            className="icon-button"
            disabled={submitting}
            onClick={onClose}
            type="button"
          >
            <X size={18} />
          </button>
        </header>

        <form className="content-agent-form" onSubmit={handleSubmit}>
          <section className="content-agent-form__section">
            <div className="content-agent-section-heading">
              <div>
                <h4>{t.contentAgent.cefrLevels}</h4>
                <p>{t.contentAgent.cefrHelp}</p>
              </div>
              <span className="content-agent-selection-count">
                {form.levels.length}/6
              </span>
            </div>
            <div className="content-agent-levels">
              {CEFR_LEVELS.map((level) => (
                <label
                  className={`content-agent-level ${
                    form.levels.includes(level) ? "selected" : ""
                  }`}
                  key={level}
                >
                  <input
                    checked={form.levels.includes(level)}
                    onChange={() => toggleLevel(level)}
                    type="checkbox"
                  />
                  <span>{level}</span>
                </label>
              ))}
            </div>
          </section>

          <section className="content-agent-form__section">
            <div className="content-agent-section-heading">
              <div>
                <h4>{t.contentAgent.sourceCatalog}</h4>
                <p>{t.contentAgent.sourcesHelp}</p>
              </div>
              <ShieldCheck aria-hidden="true" size={18} />
            </div>
            <div className="content-agent-sources">
              {catalogLoading && (
                <div className="content-agent-source-status">
                  <span className="spinner" aria-hidden="true" />
                  {t.contentAgent.sourceLoading}
                </div>
              )}
              {!catalogLoading && catalogError && (
                <div className="form-error">{catalogError}</div>
              )}
              {!catalogLoading && !catalogError && catalog.length === 0 && (
                <div className="content-agent-source-status">
                  {t.contentAgent.sourceEmpty}
                </div>
              )}
              {!catalogLoading &&
                !catalogError &&
                catalog.map((snapshot) => {
                  const selectable =
                    snapshot.status === "active" && snapshot.enabled;
                  const checked = form.sources.includes(snapshot.source_id);
                  return (
                    <label
                      className={`content-agent-source ${checked ? "selected" : ""} ${!selectable ? "disabled" : ""}`}
                      key={snapshot.source_id}
                      title={
                        !selectable
                          ? t.contentAgent.snapshotNotApproved
                          : undefined
                      }
                    >
                      <input
                        checked={checked}
                        disabled={!selectable}
                        onChange={() => toggleSource(snapshot.source_id)}
                        type="checkbox"
                      />
                      <span className="content-agent-source__copy">
                        <strong>{snapshot.source_name}</strong>
                        <small>
                          {t.contentAgent.snapshotVersion}{" "}
                          {snapshot.source_version}
                          {" · "}
                          {t.contentAgent.snapshotLicense}: {snapshot.license_id}
                          {" · "}
                          {snapshot.record_count.toLocaleString()}{" "}
                          {t.contentAgent.snapshotRecords}
                          {" · "}
                          {t.contentAgent.snapshotLastSync}:{" "}
                          {formatLastSync(snapshot.retrieved_at)}
                        </small>
                      </span>
                      <span
                        className={`content-agent-policy-badge ${snapshot.status}`}
                      >
                        {snapshot.status}
                      </span>
                    </label>
                  );
                })}
            </div>
          </section>

          <section className="content-agent-form__section">
            <div className="content-agent-section-heading">
              <div>
                <h4>{t.contentAgent.uploadTitle}</h4>
                <p>{t.contentAgent.uploadHelp}</p>
              </div>
            </div>
            <label className="content-agent-upload">
              <Upload aria-hidden="true" size={20} />
              <span>
                <strong>
                  {upload ? upload.name : t.contentAgent.chooseFile}
                </strong>
                <small>
                  {upload
                    ? `${(upload.size / 1024).toFixed(1)} KB`
                    : t.contentAgent.fileRequirements}
                </small>
              </span>
              <input
                accept=".csv,.json,text/csv,application/json"
                onChange={(event) =>
                  handleUpload(event.target.files?.[0] ?? null)
                }
                type="file"
              />
            </label>
            {uploadError && <div className="form-error">{uploadError}</div>}
            {upload && (
              <label className="content-agent-acknowledgement">
                <input
                  checked={form.uploadAttestation}
                  onChange={(event) =>
                    setForm((current) => ({
                      ...current,
                      uploadAttestation: event.target.checked,
                    }))
                  }
                  type="checkbox"
                />
                <span>{t.contentAgent.uploadAttestation}</span>
              </label>
            )}
          </section>

          <section className="content-agent-form__section">
            <div className="content-agent-section-heading">
              <div>
                <h4>{t.contentAgent.curriculum}</h4>
                <p>{t.contentAgent.curriculumHelp}</p>
              </div>
            </div>
            <div className="content-agent-fields">
              <label className="content-agent-field content-agent-field--wide">
                {t.contentAgent.courseTitle}
                <input
                  onChange={(event) =>
                    setForm((current) => ({
                      ...current,
                      courseTitle: event.target.value,
                    }))
                  }
                  placeholder={t.contentAgent.courseTitlePlaceholder}
                  value={form.courseTitle}
                />
              </label>
              <label className="content-agent-field content-agent-field--wide">
                {t.contentAgent.topicFocus}
                <input
                  onChange={(event) =>
                    setForm((current) => ({
                      ...current,
                      topicFocus: event.target.value,
                    }))
                  }
                  placeholder={t.contentAgent.topicPlaceholder}
                  value={form.topicFocus}
                />
              </label>
              <NumberField
                label={t.contentAgent.unitsPerCourse}
                max={10}
                min={1}
                onChange={(value) =>
                  setForm((current) => ({
                    ...current,
                    unitsPerCourse: value,
                  }))
                }
                value={form.unitsPerCourse}
              />
              <NumberField
                label={t.contentAgent.lessonsPerUnit}
                max={20}
                min={1}
                onChange={(value) =>
                  setForm((current) => ({
                    ...current,
                    lessonsPerUnit: value,
                  }))
                }
                value={form.lessonsPerUnit}
              />
              <NumberField
                label={t.contentAgent.vocabularyPerLesson}
                max={12}
                min={8}
                onChange={(value) =>
                  setForm((current) => ({
                    ...current,
                    vocabularyPerLesson: value,
                  }))
                }
                value={form.vocabularyPerLesson}
              />
              <NumberField
                label={t.contentAgent.exercisesPerLesson}
                max={20}
                min={4}
                onChange={(value) =>
                  setForm((current) => ({
                    ...current,
                    exerciseCount: value,
                  }))
                }
                value={form.exerciseCount}
              />
              <NumberField
                label={t.contentAgent.speakingExercises}
                max={form.exerciseCount}
                min={0}
                onChange={(value) =>
                  setForm((current) => ({
                    ...current,
                    speakingExerciseCount: value,
                  }))
                }
                value={form.speakingExerciseCount}
                disabled
              />
              <NumberField
                label={t.contentAgent.listeningExercises}
                max={form.exerciseCount}
                min={0}
                onChange={(value) =>
                  setForm((current) => ({
                    ...current,
                    listeningExerciseCount: value,
                  }))
                }
                value={form.listeningExerciseCount}
                disabled
              />
              <label className="content-agent-field content-agent-field--wide">
                <span>
                  {t.contentAgent.confidenceThreshold}:{" "}
                  <strong>{form.confidenceThreshold.toFixed(2)}</strong>
                </span>
                <input
                  max="0.99"
                  min="0.5"
                  onChange={(event) =>
                    setForm((current) => ({
                      ...current,
                      confidenceThreshold: Number(event.target.value),
                    }))
                  }
                  step="0.01"
                  type="range"
                  value={form.confidenceThreshold}
                />
              </label>
            </div>
          </section>

          <section className="content-agent-review-note">
            <div>
              <span>{t.contentAgent.previewOnly}</span>
              <strong>{t.contentAgent.previewLocked}</strong>
            </div>
            <input checked disabled readOnly type="checkbox" />
          </section>

          <label className="content-agent-acknowledgement">
            <input
              checked={form.acknowledgedDraft}
              onChange={(event) =>
                setForm((current) => ({
                  ...current,
                  acknowledgedDraft: event.target.checked,
                }))
              }
              type="checkbox"
            />
            <span>{t.contentAgent.draftAcknowledgement}</span>
          </label>

          <label className="content-agent-acknowledgement secondary">
            <input
              checked={form.revision}
              onChange={(event) =>
                setForm((current) => ({
                  ...current,
                  revision: event.target.checked,
                }))
              }
              type="checkbox"
            />
            <span>{t.contentAgent.newRevision}</span>
          </label>

          {error && <div className="form-error">{error}</div>}

          <footer className="content-agent-modal__footer">
            <button
              className="ghost-button"
              disabled={submitting}
              onClick={onClose}
              type="button"
            >
              {t.common.cancel}
            </button>
            <button
              className="primary-button content-agent-generate-button"
              disabled={submitting}
              type="submit"
            >
              <Sparkles aria-hidden="true" size={17} />
              {submitting
                ? t.contentAgent.starting
                : t.contentAgent.generatePreview}
            </button>
          </footer>
        </form>
      </section>
    </div>
  );
}

type NumberFieldProps = {
  label: string;
  min: number;
  max: number;
  value: number;
  onChange: (value: number) => void;
  disabled?: boolean;
};

function NumberField({
  label,
  min,
  max,
  value,
  onChange,
  disabled = false,
}: NumberFieldProps) {
  return (
    <label className="content-agent-field">
      {label}
      <input
        max={max}
        min={min}
        disabled={disabled}
        onChange={(event) => onChange(Number(event.target.value))}
        type="number"
        value={value}
      />
    </label>
  );
}
