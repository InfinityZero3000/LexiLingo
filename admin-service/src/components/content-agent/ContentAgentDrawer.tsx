import React, { useCallback, useEffect, useMemo, useState } from "react";
import {
  AlertTriangle,
  Ban,
  CheckCircle2,
  ChevronRight,
  Database,
  FileCheck2,
  RefreshCw,
  RotateCcw,
  ShieldCheck,
  Sparkles,
  X,
} from "lucide-react";

import {
  CONTENT_AGENT_ACTIVE_STATUSES,
  applyContentAgentJob,
  cancelContentAgentJob,
  getContentAgentJob,
  getContentAgentPreview,
  retryContentAgentJob,
  type ContentAgentJob,
  type ContentAgentJobStatus,
  type ContentAgentPreview,
} from "../../lib/contentAgentApi";
import { useI18n } from "../../lib/i18n";
import { StatusPill } from "../StatusPill";

const POLL_INTERVAL_MS = 2_500;
const activeStatuses = new Set<string>(CONTENT_AGENT_ACTIVE_STATUSES);

export const isContentAgentJobActive = (status: ContentAgentJobStatus) =>
  activeStatuses.has(status);

export const canApplyContentAgentJob = (job: ContentAgentJob) =>
  job.status === "preview_ready" && job.blocking_errors.length === 0;

export type ContentAgentPreviewSummary = {
  courses: number;
  units: number;
  lessons: number;
  vocabulary: number;
  speaking: number;
  listening: number;
  duplicateReuse: number;
};

export const summarizeContentAgentPreview = (
  preview: ContentAgentPreview,
): ContentAgentPreviewSummary => {
  const summary: ContentAgentPreviewSummary = {
    courses: preview.courses.length,
    units: 0,
    lessons: 0,
    vocabulary: 0,
    speaking: 0,
    listening: 0,
    duplicateReuse: 0,
  };

  preview.courses.forEach((course) => {
    summary.units += course.units.length;
    course.units.forEach((unit) => {
      summary.lessons += unit.lessons.length;
      unit.lessons.forEach((lesson) => {
        summary.vocabulary += lesson.vocabulary.length;
        lesson.exercises.forEach((exercise) => {
          if (
            exercise.ui_type === "speaking_repeat" ||
            exercise.ui_type === "pronunciation_practice"
          ) {
            summary.speaking += 1;
          }
          if (
            exercise.ui_type === "dictation" ||
            exercise.ui_type === "listen_and_choose"
          ) {
            summary.listening += 1;
          }
        });
      });
    });
  });

  const duplicateReuse =
    preview.quality.metrics.duplicate_reuse_count ??
    preview.quality.metrics.deduplicated_records ??
    preview.quality.metrics.duplicate_reuse;
  summary.duplicateReuse =
    typeof duplicateReuse === "number" ? duplicateReuse : 0;

  return summary;
};

export const applyContentAgentPreview = async (
  jobId: string,
  apply: (id: string) => Promise<ContentAgentJob>,
  onApplied: (job: ContentAgentJob) => void,
) => {
  const result = await apply(jobId);
  onApplied(result);
  return result;
};

type ContentAgentDrawerProps = {
  jobId: string;
  initialJob?: ContentAgentJob | null;
  onClose: () => void;
  onApplied: (job: ContentAgentJob) => void;
};

export function ContentAgentDrawer({
  jobId,
  initialJob = null,
  onClose,
  onApplied,
}: ContentAgentDrawerProps) {
  const { t } = useI18n();
  const [job, setJob] = useState<ContentAgentJob | null>(
    initialJob?.id === jobId ? initialJob : null,
  );
  const [preview, setPreview] = useState<ContentAgentPreview | null>(null);
  const [loading, setLoading] = useState(!initialJob);
  const [busyAction, setBusyAction] = useState<
    "apply" | "retry" | "cancel" | null
  >(null);
  const [error, setError] = useState<string | null>(null);

  const refreshJob = useCallback(async () => {
    const nextJob = await getContentAgentJob(jobId);
    setJob(nextJob);
    return nextJob;
  }, [jobId]);

  useEffect(() => {
    let disposed = false;
    setPreview(null);
    setError(null);

    if (initialJob?.id === jobId) {
      setJob(initialJob);
      setLoading(false);
      return () => {
        disposed = true;
      };
    }

    setLoading(true);
    void refreshJob()
      .catch((requestError) => {
        if (!disposed) {
          setError(
            requestError instanceof Error
              ? requestError.message
              : t.contentAgent.loadJobFailed,
          );
        }
      })
      .finally(() => {
        if (!disposed) setLoading(false);
      });

    return () => {
      disposed = true;
    };
  }, [initialJob, jobId, refreshJob, t.contentAgent.loadJobFailed]);

  useEffect(() => {
    if (!job || !isContentAgentJobActive(job.status)) return;

    let disposed = false;
    const interval = window.setInterval(() => {
      void refreshJob().catch((requestError) => {
        if (!disposed) {
          setError(
            requestError instanceof Error
              ? requestError.message
              : t.contentAgent.loadJobFailed,
          );
        }
      });
    }, POLL_INTERVAL_MS);

    return () => {
      disposed = true;
      window.clearInterval(interval);
    };
  }, [job, refreshJob, t.contentAgent.loadJobFailed]);

  useEffect(() => {
    if (
      !job ||
      (job.status !== "preview_ready" && job.status !== "completed") ||
      preview
    ) {
      return;
    }

    let disposed = false;
    void getContentAgentPreview(job.id)
      .then((nextPreview) => {
        if (!disposed) setPreview(nextPreview);
      })
      .catch((requestError) => {
        if (!disposed) {
          setError(
            requestError instanceof Error
              ? requestError.message
              : t.contentAgent.loadPreviewFailed,
          );
        }
      });

    return () => {
      disposed = true;
    };
  }, [job, preview, t.contentAgent.loadPreviewFailed]);

  const summary = useMemo(
    () => (preview ? summarizeContentAgentPreview(preview) : null),
    [preview],
  );

  const handleApply = async () => {
    if (!job || !canApplyContentAgentJob(job)) return;
    setBusyAction("apply");
    setError(null);
    try {
      const result = await applyContentAgentPreview(
        job.id,
        applyContentAgentJob,
        onApplied,
      );
      setJob(result);
    } catch (requestError) {
      setError(
        requestError instanceof Error
          ? requestError.message
          : t.contentAgent.applyFailed,
      );
    } finally {
      setBusyAction(null);
    }
  };

  const handleRetry = async () => {
    if (!job) return;
    setBusyAction("retry");
    setError(null);
    try {
      const result = await retryContentAgentJob(job.id);
      setJob(result);
      setPreview(null);
    } catch (requestError) {
      setError(
        requestError instanceof Error
          ? requestError.message
          : t.contentAgent.retryFailed,
      );
    } finally {
      setBusyAction(null);
    }
  };

  const handleCancel = async () => {
    if (!job) return;
    setBusyAction("cancel");
    setError(null);
    try {
      setJob(await cancelContentAgentJob(job.id));
    } catch (requestError) {
      setError(
        requestError instanceof Error
          ? requestError.message
          : t.contentAgent.cancelFailed,
      );
    } finally {
      setBusyAction(null);
    }
  };

  const percentage = Math.max(
    0,
    Math.min(
      100,
      Number(job?.progress.percentage ?? job?.progress.percent ?? 0),
    ),
  );
  const warnings = [
    ...(job?.warnings ?? []),
    ...(preview?.quality.warnings ?? []),
  ];
  const blockingErrors = [
    ...(job?.blocking_errors ?? []),
    ...(preview?.quality.blocking_errors ?? []),
  ];
  const courseIds =
    job?.created_entity_ids.course_ids ??
    job?.created_entity_ids.courses ??
    [];

  return (
    <div className="content-agent-drawer-layer">
      <button
        aria-label={t.common.close}
        className="content-agent-drawer-backdrop"
        onClick={onClose}
        type="button"
      />
      <aside
        aria-labelledby="content-agent-drawer-title"
        aria-modal="true"
        className="content-agent-drawer"
        role="dialog"
      >
        <header className="content-agent-drawer__header">
          <div className="content-agent-title-lockup">
            <span className="content-agent-title-icon" aria-hidden="true">
              <Sparkles size={19} />
            </span>
            <div>
              <h3 id="content-agent-drawer-title">
                {t.contentAgent.jobTitle}
              </h3>
              <p className="mono">{jobId}</p>
            </div>
          </div>
          <div className="content-agent-drawer__header-actions">
            <button
              aria-label={t.contentAgent.refresh}
              className="icon-button"
              disabled={loading}
              onClick={() => void refreshJob()}
              type="button"
            >
              <RefreshCw size={17} />
            </button>
            <button
              aria-label={t.common.close}
              className="icon-button"
              onClick={onClose}
              type="button"
            >
              <X size={18} />
            </button>
          </div>
        </header>

        <div className="content-agent-drawer__body">
          {loading && !job ? (
            <div className="content-agent-loading">
              <span className="spinner" />
              {t.contentAgent.loadingJob}
            </div>
          ) : job ? (
            <>
              <section className="content-agent-job-status">
                <div className="content-agent-job-status__topline">
                  <div>
                    <span>{t.contentAgent.currentStage}</span>
                    <strong>{formatStage(job.status)}</strong>
                  </div>
                  <StatusPill
                    label={formatStage(job.status)}
                    tone={statusTone(job.status)}
                  />
                </div>
                <div
                  aria-label={`${percentage}%`}
                  aria-valuemax={100}
                  aria-valuemin={0}
                  aria-valuenow={percentage}
                  className="content-agent-progress"
                  role="progressbar"
                >
                  <span style={{ width: `${percentage}%` }} />
                </div>
                <div className="content-agent-job-status__meta">
                  <span>{job.progress.message || t.contentAgent.processing}</span>
                  <strong>{percentage}%</strong>
                </div>
              </section>

              <section className="content-agent-counter-grid">
                <Counter
                  label={t.contentAgent.processed}
                  value={counter(job, "processed")}
                />
                <Counter
                  label={t.contentAgent.rejected}
                  value={counter(job, "rejected")}
                />
                <Counter
                  label={t.contentAgent.deduplicated}
                  value={counter(job, "deduplicated")}
                />
              </section>

              {job.error_message && (
                <MessageList
                  icon={<AlertTriangle size={17} />}
                  items={[job.error_message]}
                  title={t.contentAgent.jobError}
                  tone="danger"
                />
              )}
              {blockingErrors.length > 0 && (
                <MessageList
                  icon={<Ban size={17} />}
                  items={blockingErrors}
                  title={t.contentAgent.blockingErrors}
                  tone="danger"
                />
              )}
              {warnings.length > 0 && (
                <MessageList
                  icon={<AlertTriangle size={17} />}
                  items={warnings}
                  title={t.contentAgent.warnings}
                  tone="warning"
                />
              )}

              {job.source_manifest.length > 0 && (
                <section className="content-agent-drawer-section">
                  <div className="content-agent-drawer-section__heading">
                    <ShieldCheck size={17} />
                    <h4>{t.contentAgent.provenance}</h4>
                  </div>
                  <div className="content-agent-manifest">
                    {job.source_manifest.map((source, index) => (
                      <div
                        className="content-agent-manifest__item"
                        key={`${source.source_name}-${index}`}
                      >
                        <div>
                          <strong>{source.source_name}</strong>
                          <span>
                            {typeof source.policy_version === "string" && source.policy_version
                              ? `${t.contentAgent.snapshotVersion} ${source.policy_version} · `
                              : ""}
                            {Array.isArray(source.content_usage)
                              ? source.content_usage.join(", ")
                              : source.content_usage ||
                                source.license_mode ||
                                t.common.unknown}
                          </span>
                        </div>
                        {typeof source.record_count === "number" && (
                          <span>{source.record_count} {t.contentAgent.snapshotRecords}</span>
                        )}
                      </div>
                    ))}
                  </div>
                </section>
              )}

              {summary && preview && (
                <>
                  <section className="content-agent-drawer-section">
                    <div className="content-agent-drawer-section__heading">
                      <FileCheck2 size={17} />
                      <h4>{t.contentAgent.previewSummary}</h4>
                    </div>
                    <div className="content-agent-preview-metrics">
                      <PreviewMetric
                        label={t.contentAgent.coursesCount}
                        value={summary.courses}
                      />
                      <PreviewMetric
                        label={t.contentAgent.unitsCount}
                        value={summary.units}
                      />
                      <PreviewMetric
                        label={t.contentAgent.lessonsCount}
                        value={summary.lessons}
                      />
                      <PreviewMetric
                        label={t.contentAgent.vocabularyCount}
                        value={summary.vocabulary}
                      />
                      <PreviewMetric
                        label={t.contentAgent.speakingCount}
                        value={summary.speaking}
                      />
                      <PreviewMetric
                        label={t.contentAgent.listeningCount}
                        value={summary.listening}
                      />
                    </div>
                    <p className="content-agent-duplicate-note">
                      {summary.duplicateReuse} {t.contentAgent.duplicatesReused}
                    </p>
                  </section>

                  <section className="content-agent-drawer-section">
                    <div className="content-agent-drawer-section__heading">
                      <Database size={17} />
                      <h4>{t.contentAgent.courseTree}</h4>
                    </div>
                    <div className="content-agent-course-tree">
                      {preview.courses.map((course, courseIndex) => (
                        <details
                          key={`${course.level}-${course.title}`}
                          open={courseIndex === 0}
                        >
                          <summary>
                            <span>
                              <strong>{course.title}</strong>
                              <small>
                                {course.level} · {course.units.length}{" "}
                                {t.contentAgent.unitsCount.toLowerCase()}
                              </small>
                            </span>
                            <ChevronRight aria-hidden="true" size={16} />
                          </summary>
                          <div className="content-agent-course-tree__units">
                            {course.units.map((unit) => (
                              <div key={`${unit.order_index}-${unit.title}`}>
                                <strong>{unit.title}</strong>
                                <ul>
                                  {unit.lessons.map((lesson) => (
                                    <li
                                      key={`${lesson.order_index}-${lesson.title}`}
                                    >
                                      <span>{lesson.title}</span>
                                      <small>
                                        {lesson.vocabulary.length}{" "}
                                        {t.contentAgent.words} ·{" "}
                                        {lesson.exercises.length}{" "}
                                        {t.contentAgent.exercises}
                                      </small>
                                    </li>
                                  ))}
                                </ul>
                              </div>
                            ))}
                          </div>
                        </details>
                      ))}
                    </div>
                  </section>

                  <SampleExercises preview={preview} />
                </>
              )}

              {job.status === "completed" && (
                <section className="content-agent-complete">
                  <CheckCircle2 aria-hidden="true" size={22} />
                  <div>
                    <strong>{t.contentAgent.applyComplete}</strong>
                    <p>{t.contentAgent.draftsCreated}</p>
                    {courseIds.length > 0 && (
                      <div className="content-agent-created-links">
                        {courseIds.map((courseId, index) => (
                          <a
                            className="ghost-button small"
                            href={`/admin/courses/${courseId}/units`}
                            key={courseId}
                          >
                            {t.contentAgent.openDraft} {index + 1}
                          </a>
                        ))}
                      </div>
                    )}
                  </div>
                </section>
              )}

              {error && <div className="form-error">{error}</div>}
            </>
          ) : (
            <div className="form-error">
              {error || t.contentAgent.loadJobFailed}
            </div>
          )}
        </div>

        {job && (
          <footer className="content-agent-drawer__footer">
            {(job.status === "failed" || job.status === "cancelled") && (
              <button
                className="ghost-button"
                disabled={busyAction !== null}
                onClick={() => void handleRetry()}
                type="button"
              >
                <RotateCcw size={16} />
                {busyAction === "retry"
                  ? t.contentAgent.retrying
                  : t.contentAgent.retry}
              </button>
            )}
            {isContentAgentJobActive(job.status) &&
              job.status !== "applying" && (
                <button
                  className="ghost-button danger"
                  disabled={busyAction !== null}
                  onClick={() => void handleCancel()}
                  type="button"
                >
                  <Ban size={16} />
                  {busyAction === "cancel"
                    ? t.contentAgent.cancelling
                    : t.contentAgent.cancelJob}
                </button>
              )}
            {job.status === "preview_ready" && (
              <>
                {blockingErrors.length > 0 && (
                  <span className="content-agent-apply-blocked">
                    {t.contentAgent.validationBlocking}
                  </span>
                )}
                <button
                  className="primary-button content-agent-apply-button"
                  disabled={
                    busyAction !== null ||
                    !canApplyContentAgentJob({
                      ...job,
                      blocking_errors: blockingErrors,
                    })
                  }
                  onClick={() => void handleApply()}
                  type="button"
                >
                  <Database size={16} />
                  {busyAction === "apply"
                    ? t.contentAgent.applying
                    : t.contentAgent.applyDraft}
                </button>
              </>
            )}
          </footer>
        )}
      </aside>
    </div>
  );
}

function formatStage(status: string) {
  return status
    .split("_")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function statusTone(status: ContentAgentJobStatus) {
  if (status === "completed" || status === "preview_ready") return "success";
  if (status === "failed" || status === "cancelled") return "danger";
  if (status === "queued") return "neutral";
  return "info";
}

function counter(
  job: ContentAgentJob,
  name: "processed" | "rejected" | "deduplicated",
) {
  const longName = `${name}_records`;
  const counters = job.progress.counters ?? {};
  const value =
    job.progress[longName] ??
    job.progress[name] ??
    counters[longName] ??
    counters[name] ??
    (name === "processed" ? counters.input_records : undefined);
  return typeof value === "number" ? value : 0;
}

function Counter({ label, value }: { label: string; value: number }) {
  return (
    <div>
      <strong>{value.toLocaleString()}</strong>
      <span>{label}</span>
    </div>
  );
}

function PreviewMetric({ label, value }: { label: string; value: number }) {
  return (
    <div>
      <span>{label}</span>
      <strong>{value.toLocaleString()}</strong>
    </div>
  );
}

function MessageList({
  icon,
  items,
  title,
  tone,
}: {
  icon: React.ReactNode;
  items: string[];
  title: string;
  tone: "danger" | "warning";
}) {
  return (
    <section className={`content-agent-message-list ${tone}`}>
      <div>
        {icon}
        <strong>{title}</strong>
      </div>
      <ul>
        {items.map((item, index) => (
          <li key={`${item}-${index}`}>{item}</li>
        ))}
      </ul>
    </section>
  );
}

function SampleExercises({ preview }: { preview: ContentAgentPreview }) {
  const { t } = useI18n();
  const exercises = preview.courses
    .flatMap((course) => course.units)
    .flatMap((unit) => unit.lessons)
    .flatMap((lesson) => lesson.exercises)
    .slice(0, 3);

  if (exercises.length === 0) return null;

  return (
    <section className="content-agent-drawer-section">
      <div className="content-agent-drawer-section__heading">
        <Sparkles size={17} />
        <h4>{t.contentAgent.sampleExercises}</h4>
      </div>
      <div className="content-agent-exercise-samples">
        {exercises.map((exercise) => (
          <article key={exercise.id}>
            <span>{formatStage(exercise.ui_type)}</span>
            <strong>{exercise.question}</strong>
            <p>{exercise.correct_answer}</p>
          </article>
        ))}
      </div>
    </section>
  );
}
