import React, { useCallback, useEffect, useMemo, useState } from "react";
import { CheckCircle, Pencil, RefreshCw, RotateCcw, XCircle } from "lucide-react";
import { EmptyState } from "../components/EmptyState";
import { SectionHeader } from "../components/SectionHeader";
import { StatCard } from "../components/StatCard";
import { StatusPill } from "../components/StatusPill";
import {
  applyContentAgentJob,
  cancelContentAgentJob,
  getContentAgentPreview,
  listContentQaQueue,
  retryContentAgentJob,
  updateContentAgentRecord,
  type ContentAgentExercise,
  type ContentAgentJob,
  type ContentAgentLessonPreview,
  type ContentAgentPreview,
  type ContentQaQueue,
} from "../lib/contentAgentApi";

const statusTone = (status: string): "success" | "warning" | "info" | "danger" | "neutral" => {
  if (status === "preview_ready") return "warning";
  if (status === "completed") return "success";
  if (status === "failed") return "danger";
  return "info";
};

const summarizePreview = (preview: ContentAgentPreview | null) => {
  if (!preview) {
    return { courses: 0, units: 0, lessons: 0, vocabulary: 0, exercises: 0 };
  }

  return preview.courses.reduce(
    (acc, course) => {
      acc.courses += 1;
      acc.units += course.units.length;
      course.units.forEach((unit) => {
        acc.lessons += unit.lessons.length;
        unit.lessons.forEach((lesson) => {
          acc.vocabulary += lesson.vocabulary.length;
          acc.exercises += lesson.exercises.length;
        });
      });
      return acc;
    },
    { courses: 0, units: 0, lessons: 0, vocabulary: 0, exercises: 0 },
  );
};

const JobList = ({
  title,
  jobs,
  selectedId,
  onSelect,
}: {
  title: string;
  jobs: ContentAgentJob[];
  selectedId?: string;
  onSelect: (job: ContentAgentJob) => void;
}) => (
  <div className="panel-inner">
    <h3>{title}</h3>
    {!jobs.length ? (
      <EmptyState title="No jobs" description="Nothing is waiting in this bucket." />
    ) : (
      <div className="stack" style={{ gap: 10 }}>
        {jobs.map((job) => (
          <button
            key={job.id}
            className={selectedId === job.id ? "ghost-button active" : "ghost-button"}
            onClick={() => onSelect(job)}
            style={{
              justifyContent: "space-between",
              textAlign: "left",
              width: "100%",
              borderColor: selectedId === job.id ? "var(--accent-2)" : undefined,
            }}
          >
            <span>
              <strong>{job.config.title_focus || job.config.levels?.join(", ") || "Content job"}</strong>
              <span className="table-sub" style={{ display: "block" }}>
                {job.id.slice(0, 8)} · {new Date(job.updated_at).toLocaleString()}
              </span>
            </span>
            <StatusPill tone={statusTone(job.status)} label={job.status} />
          </button>
        ))}
      </div>
    )}
  </div>
);

type EditForm = {
  recordId: string;
  question: string;
  correctAnswer: string;
  explanation: string;
  optionsJson: string;
  lessonTitle: string;
  lessonOutcome: string;
};

export const ContentQaQueuePage = () => {
  const [queue, setQueue] = useState<ContentQaQueue | null>(null);
  const [selected, setSelected] = useState<ContentAgentJob | null>(null);
  const [preview, setPreview] = useState<ContentAgentPreview | null>(null);
  const [loading, setLoading] = useState(false);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [editForm, setEditForm] = useState<EditForm | null>(null);
  const [editError, setEditError] = useState<string | null>(null);
  const [savingEdit, setSavingEdit] = useState(false);

  const loadQueue = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const nextQueue = await listContentQaQueue();
      setQueue(nextQueue);
      setSelected((current) => {
        const jobs = [
          ...nextQueue.reviewable,
          ...nextQueue.failed,
          ...nextQueue.applied,
        ];
        return (
          (current ? jobs.find((job) => job.id === current.id) : null) ??
          nextQueue.reviewable[0] ??
          nextQueue.failed[0] ??
          nextQueue.applied[0] ??
          null
        );
      });
    } catch (err: any) {
      setError(err?.message || "Failed to load content QA queue");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadQueue();
  }, [loadQueue]);

  useEffect(() => {
    if (!selected) {
      setPreview(null);
      return;
    }

    setPreviewLoading(true);
    getContentAgentPreview(selected.id)
      .then(setPreview)
      .catch(() => setPreview(null))
      .finally(() => setPreviewLoading(false));
  }, [selected]);

  const summary = useMemo(() => summarizePreview(preview), [preview]);
  const validationErrors = [
    ...(selected?.blocking_errors || []),
    ...(preview?.quality.blocking_errors || []),
  ];
  const validationWarnings = [
    ...(selected?.warnings || []),
    ...(preview?.quality.warnings || []),
  ];
  const createdCourseIds =
    selected?.created_entity_ids.course_ids ??
    selected?.created_entity_ids.courses ??
    [];

  const runAction = async (action: "apply" | "cancel" | "retry") => {
    if (!selected) return;
    setError(null);
    try {
      if (action === "apply") await applyContentAgentJob(selected.id);
      if (action === "cancel") await cancelContentAgentJob(selected.id);
      if (action === "retry") await retryContentAgentJob(selected.id);
      await loadQueue();
    } catch (err: any) {
      setError(err?.message || `Failed to ${action} content job`);
    }
  };

  const openEdit = (exercise: ContentAgentExercise, lesson: ContentAgentLessonPreview) => {
    setEditError(null);
    setEditForm({
      recordId: exercise.id,
      question: exercise.question,
      correctAnswer: exercise.correct_answer,
      explanation: exercise.explanation || "",
      optionsJson: exercise.options ? JSON.stringify(exercise.options, null, 2) : "",
      lessonTitle: lesson.title,
      lessonOutcome: lesson.outcome || "",
    });
  };

  const saveEdit = async () => {
    if (!selected || !editForm) return;
    setEditError(null);
    let options: unknown;
    if (editForm.optionsJson.trim()) {
      try {
        options = JSON.parse(editForm.optionsJson);
      } catch {
        setEditError("Options must be valid JSON (e.g. [\"a\", \"b\"]).");
        return;
      }
    }
    setSavingEdit(true);
    try {
      const updated = await updateContentAgentRecord(selected.id, editForm.recordId, {
        question: editForm.question,
        correct_answer: editForm.correctAnswer,
        explanation: editForm.explanation || undefined,
        options,
        lesson_outcome: editForm.lessonOutcome || undefined,
      });
      setPreview(updated);
      setEditForm(null);
    } catch (err: any) {
      setEditError(err?.message || "Failed to save the edit");
    } finally {
      setSavingEdit(false);
    }
  };

  return (
    <div className="stack">
      <SectionHeader
        title="Content QA Queue"
        description="Review, validate, publish, or reject AI-generated learning content."
        action={
          <button className="btn-secondary btn-sm" onClick={loadQueue} disabled={loading}>
            <RefreshCw size={14} /> Refresh
          </button>
        }
      />

      {error && <div className="form-error">{error}</div>}

      <div className="card-grid">
        <StatCard label="Ready for review" value={String(queue?.reviewable.length || 0)} accent="orange" />
        <StatCard label="Failed validation" value={String(queue?.failed.length || 0)} accent="berry" />
        <StatCard label="Published jobs" value={String(queue?.applied.length || 0)} accent="teal" />
        <StatCard label="Tracked jobs" value={String(queue?.total || 0)} accent="ink" />
      </div>

      <div className="grid-2">
        <div className="stack">
          <JobList title="Needs approval" jobs={queue?.reviewable || []} selectedId={selected?.id} onSelect={setSelected} />
          <JobList title="Needs repair" jobs={queue?.failed || []} selectedId={selected?.id} onSelect={setSelected} />
          <JobList title="Apply history" jobs={queue?.applied || []} selectedId={selected?.id} onSelect={setSelected} />
        </div>

        <div className="panel">
          {!selected ? (
            <EmptyState title="No content job selected" description="Create a content-agent job, then review it here before publishing." />
          ) : (
            <div className="stack">
              <div style={{ display: "flex", justifyContent: "space-between", gap: 12, alignItems: "center" }}>
                <div>
                  <h3 style={{ margin: 0 }}>{selected.config.title_focus || "Generated content preview"}</h3>
                  <div className="table-sub">{selected.id}</div>
                </div>
                <StatusPill tone={statusTone(selected.status)} label={selected.status} />
              </div>

              <div className="card-grid">
                <StatCard label="Courses" value={String(summary.courses)} accent="orange" />
                <StatCard label="Lessons" value={String(summary.lessons)} accent="teal" />
                <StatCard label="Vocabulary" value={String(summary.vocabulary)} accent="ink" />
                <StatCard label="Exercises" value={String(summary.exercises)} accent="berry" />
              </div>

              <div className="panel-inner">
                <h3>Validation</h3>
                {previewLoading && <div className="loading">Loading preview...</div>}
                {!validationErrors.length && !validationWarnings.length ? (
                  <StatusPill tone="success" label="No blocking issues" />
                ) : (
                  <div className="stack" style={{ gap: 8 }}>
                    {validationErrors.map((message, index) => (
                      <div key={`error-${index}`} className="form-error">{message}</div>
                    ))}
                    {validationWarnings.map((message, index) => (
                      <div key={`warning-${index}`} className="callout warning">{message}</div>
                    ))}
                  </div>
                )}
              </div>

              <div className="panel-inner">
                <h3>Lessons & exercises</h3>
                {!preview?.courses?.length ? (
                  <div className="table-sub">No lesson content in this preview.</div>
                ) : (
                  <div className="stack" style={{ gap: 16 }}>
                    {preview.courses.flatMap((course) =>
                      course.units.flatMap((unit) =>
                        unit.lessons.map((lesson) => (
                          <div key={`${course.title}-${unit.title}-${lesson.title}`} className="panel-inner">
                            <strong>{lesson.title}</strong>
                            <div className="table-sub" style={{ marginBottom: 8 }}>
                              {lesson.outcome ? `Outcome: ${lesson.outcome}` : "No outcome set."}
                            </div>
                            <div className="stack" style={{ gap: 6 }}>
                              {lesson.exercises.map((exercise) => (
                                <div
                                  key={exercise.id}
                                  style={{
                                    display: "flex",
                                    justifyContent: "space-between",
                                    alignItems: "flex-start",
                                    gap: 8,
                                    borderTop: "1px solid var(--border-soft)",
                                    paddingTop: 6,
                                  }}
                                >
                                  <div>
                                    <div className="table-sub">
                                      {exercise.ui_type}
                                      {exercise.phase ? ` · ${exercise.phase}` : ""}
                                    </div>
                                    <div>{exercise.question}</div>
                                  </div>
                                  <button
                                    className="ghost-button small"
                                    disabled={selected.status !== "preview_ready"}
                                    onClick={() => openEdit(exercise, lesson)}
                                  >
                                    <Pencil size={14} /> Edit
                                  </button>
                                </div>
                              ))}
                            </div>
                          </div>
                        )),
                      ),
                    )}
                  </div>
                )}
              </div>

              <div className="panel-inner">
                <h3>Source policy</h3>
                {!preview?.source_manifest?.length ? (
                  <div className="table-sub">No source manifest attached.</div>
                ) : (
                  <div className="stack" style={{ gap: 8 }}>
                    {preview.source_manifest.map((source, index) => (
                      <div key={`${source.source_name}-${index}`} className="table-sub">
                        <strong>{source.source_name}</strong> · {source.license_mode || "unknown"} · {source.record_count || 0} records
                      </div>
                    ))}
                  </div>
                )}
              </div>

              <div className="panel-inner">
                <h3>Apply history</h3>
                <div className="table-sub">Created courses: {createdCourseIds.length ? createdCourseIds.join(", ") : "none yet"}</div>
                <div className="table-sub">Completed: {selected.completed_at ? new Date(selected.completed_at).toLocaleString() : "not completed"}</div>
              </div>

              <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
                <button className="primary-button" disabled={selected.status !== "preview_ready"} onClick={() => runAction("apply")}>
                  <CheckCircle size={16} /> Approve & publish
                </button>
                <button className="ghost-button danger" disabled={!["preview_ready", "failed"].includes(selected.status)} onClick={() => runAction("cancel")}>
                  <XCircle size={16} /> Reject
                </button>
                <button className="ghost-button" disabled={selected.status !== "failed"} onClick={() => runAction("retry")}>
                  <RotateCcw size={16} /> Retry
                </button>
              </div>
            </div>
          )}
        </div>
      </div>

      {editForm && (
        <div className="modal-overlay" onClick={() => setEditForm(null)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 560 }}>
            <h3>Edit exercise</h3>
            <div className="table-sub" style={{ marginBottom: 8 }}>Lesson: {editForm.lessonTitle}</div>
            {editError && <div className="form-error">{editError}</div>}
            <div className="stack" style={{ gap: 10 }}>
              <label>
                Question
                <textarea
                  rows={2}
                  value={editForm.question}
                  onChange={(e) => setEditForm({ ...editForm, question: e.target.value })}
                />
              </label>
              <label>
                Options (JSON, optional)
                <textarea
                  rows={3}
                  placeholder='["option a", "option b"]'
                  value={editForm.optionsJson}
                  onChange={(e) => setEditForm({ ...editForm, optionsJson: e.target.value })}
                />
              </label>
              <label>
                Correct answer
                <input
                  value={editForm.correctAnswer}
                  onChange={(e) => setEditForm({ ...editForm, correctAnswer: e.target.value })}
                />
              </label>
              <label>
                Explanation (optional)
                <textarea
                  rows={2}
                  value={editForm.explanation}
                  onChange={(e) => setEditForm({ ...editForm, explanation: e.target.value })}
                />
              </label>
              <label>
                Lesson outcome (can-do statement)
                <textarea
                  rows={2}
                  value={editForm.lessonOutcome}
                  onChange={(e) => setEditForm({ ...editForm, lessonOutcome: e.target.value })}
                />
              </label>
              <div style={{ display: "flex", gap: 10, justifyContent: "flex-end" }}>
                <button className="ghost-button" onClick={() => setEditForm(null)} disabled={savingEdit}>
                  Cancel
                </button>
                <button className="primary-button" onClick={saveEdit} disabled={savingEdit}>
                  {savingEdit ? "Saving..." : "Save"}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
