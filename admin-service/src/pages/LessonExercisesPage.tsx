import { useConfirm } from "../components/ConfirmDialog";
import React, { useEffect, useState, useCallback, useRef } from "react";
import { useParams, useNavigate } from "react-router-dom";
import {
  getLessonDetail,
  updateLessonContent,
  generateLessonExercises,
  type LessonDetail,
  type Exercise,
  type UiType,
  UI_TYPES,
  UI_TYPE_LABELS,
  UI_TYPE_TO_TYPE,
} from "../lib/adminApi";
import { ExerciseTypeForm } from "../components/ExerciseTypeForm";
import { Dialog } from "../components/Dialog";
import { useI18n } from "../lib/i18n";
import {
  ArrowLeft,
  Plus,
  Pencil,
  Trash2,
  ChevronUp,
  ChevronDown,
  Save,
  Loader2,
  BookOpen,
  Clock,
  Sparkles,
  X,
} from "lucide-react";

// ─── helpers ────────────────────────────────────────────────────────────────

const makeId = () => `ex_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;

// The model numbers its ids from 1 each call, so a second unsaved draft repeats them.
const appendWithFreshIds = (prev: Exercise[], drafts: Exercise[], lessonId: string): Exercise[] => {
  const used = new Set(prev.map((e) => e.id));
  let n = 1;
  const added = drafts.map((d) => {
    let id = d.id;
    if (!id || used.has(id)) {
      while (used.has(`ex_${lessonId}_${n}`)) n += 1;
      id = `ex_${lessonId}_${n}`;
    }
    used.add(id);
    return id === d.id ? d : { ...d, id };
  });
  return [...prev, ...added];
};

const defaultExercise = (uiType: UiType, index: number): Exercise => ({
  id: makeId(),
  type: UI_TYPE_TO_TYPE[uiType],
  ui_type: uiType,
  question: "",
  options: null,
  correct_answer: "",
  explanation: null,
  hint: null,
  audio_url: null,
  image_url: null,
  difficulty: 1,
  points: 10,
});

const UI_TYPE_GROUPS: { label: string; types: UiType[] }[] = [
  {
    label: "Multiple Choice",
    types: ["multiple_choice", "collocation_choice", "image_based_choice", "listen_and_choose"],
  },
  {
    label: "True / False & Reading",
    types: ["true_or_false", "reading_comprehension"],
  },
  {
    label: "Fill Blank & Writing",
    types: ["fill_in_the_blank", "dictation", "short_writing_answer", "dialogue_completion", "grammar_correction"],
  },
  {
    label: "Arrange & Match",
    types: ["arrange_the_sentence", "match_word_to_meaning", "cognitive_fluidity", "categorization"],
  },
  {
    label: "Speaking & Listening",
    types: ["speaking_repeat", "pronunciation_practice", "translation_choice"],
  },
  {
    label: "Vocabulary",
    types: ["vocabulary_flashcard"],
  },
];

const TYPE_TONES: Record<string, string> = {
  multiple_choice: "tone-blue",
  collocation_choice: "tone-blue",
  image_based_choice: "tone-purple",
  listen_and_choose: "tone-teal",
  true_or_false: "tone-gold",
  reading_comprehension: "tone-orange",
  fill_in_the_blank: "tone-green",
  dictation: "tone-green",
  short_writing_answer: "tone-green",
  dialogue_completion: "tone-purple",
  grammar_correction: "tone-red",
  arrange_the_sentence: "tone-teal",
  match_word_to_meaning: "tone-berry",
  cognitive_fluidity: "tone-berry",
  categorization: "tone-purple",
  speaking_repeat: "tone-gold",
  pronunciation_practice: "tone-gold",
  translation_choice: "tone-blue",
  vocabulary_flashcard: "tone-green",
};

// ─── TypeSelector modal ──────────────────────────────────────────────────────

const TypeSelectorModal = ({
  onSelect,
  onClose,
}: {
  onSelect: (t: UiType) => void;
  onClose: () => void;
}) => {
  const { t: tr } = useI18n();
  return (
    <Dialog onClose={onClose} maxWidth={720}>
      <div className="lesson-exercise-modal-flat">
        <div className="lesson-exercise-modal-header">
          <h2>{tr.lessonExercises.selectTypeTitle}</h2>
          <button
            type="button"
            onClick={onClose}
            className="icon-button"
            aria-label={tr.common.close}
          >
            <X size={18} aria-hidden="true" />
          </button>
        </div>
        <div className="lesson-exercise-modal-body exercise-type-groups">
          {UI_TYPE_GROUPS.map((group) => (
            <div key={group.label}>
              <p className="exercise-group-label">
                {group.label}
              </p>
              <div className="exercise-type-grid">
                {group.types.map((t) => (
                  <button
                    key={t}
                    type="button"
                    onClick={() => onSelect(t)}
                    className={`exercise-type-choice ${TYPE_TONES[t] ?? "tone-neutral"}`}
                  >
                    {UI_TYPE_LABELS[t]}
                  </button>
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>
    </Dialog>
  );
};

// ─── ExerciseModal ────────────────────────────────────────────────────────────

const ExerciseModal = ({
  initial,
  index,
  onSave,
  onClose,
}: {
  initial: Exercise;
  index: number;
  onSave: (e: Exercise) => void;
  onClose: () => void;
}) => {
  const { t: tr } = useI18n();
  const [exercise, setExercise] = useState<Exercise>(initial);
  const [formError, setFormError] = useState<string | null>(null);

  const handleSave = () => {
    if (!exercise.question.trim()) {
      setFormError(tr.lessonExercises.errPromptRequired);
      return;
    }
    if (!exercise.correct_answer.trim() && exercise.ui_type !== "short_writing_answer") {
      setFormError(tr.lessonExercises.errAnswerRequired);
      return;
    }
    setFormError(null);
    onSave(exercise);
  };

  return (
    <Dialog onClose={onClose} maxWidth={560}>
      <div className="lesson-exercise-modal-flat">
        <div className="lesson-exercise-modal-header">
          <div>
            <span
              className={`exercise-type-tag ${TYPE_TONES[exercise.ui_type] ?? "tone-neutral"}`}
            >
              {UI_TYPE_LABELS[exercise.ui_type as UiType] ?? exercise.ui_type}
            </span>
            <h2>
              {tr.lessonExercises.exerciseHeading.replace("{n}", String(index + 1))}
            </h2>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="icon-button"
            aria-label={tr.common.close}
          >
            <X size={18} aria-hidden="true" />
          </button>
        </div>

        <div className="lesson-exercise-modal-body">
          <ExerciseTypeForm
            uiType={exercise.ui_type as UiType}
            value={exercise}
            onChange={setExercise}
          />

          {/* Difficulty */}
          <div className="exercise-form-field">
            <label className="exercise-form-label">
              {tr.lessonExercises.difficultyLabel}
            </label>
            <div className="exercise-difficulty-options">
              {[1, 2, 3, 4, 5].map((d) => (
                <button
                  key={d}
                  type="button"
                  className={`exercise-difficulty-button${exercise.difficulty === d ? " is-active" : ""}`}
                  onClick={() => setExercise({ ...exercise, difficulty: d })}
                >
                  {d}
                </button>
              ))}
            </div>
          </div>
        </div>

        {formError && (
          <div className="form-error" role="alert">{formError}</div>
        )}

        <div className="lesson-exercise-modal-footer">
          <button
            type="button"
            onClick={onClose}
            className="ghost-button"
          >
            {tr.common.cancel}
          </button>
          <button
            type="button"
            onClick={handleSave}
            className="primary-button"
          >
            <Save size={15} /> {tr.lessonExercises.saveExercise}
          </button>
        </div>
      </div>
    </Dialog>
  );
};

// ─── ExerciseRow ──────────────────────────────────────────────────────────────

const ExerciseRow = ({
  exercise,
  index,
  total,
  onEdit,
  onDelete,
  onMoveUp,
  onMoveDown,
}: {
  exercise: Exercise;
  index: number;
  total: number;
  onEdit: () => void;
  onDelete: () => void;
  onMoveUp: () => void;
  onMoveDown: () => void;
}) => {
  const { t: tr } = useI18n();
  return (
  <div className="exercise-row">
    <span className="exercise-index">
      {index + 1}
    </span>
    <span
      className={`exercise-type-tag ${TYPE_TONES[exercise.ui_type] ?? "tone-neutral"}`}
    >
      {UI_TYPE_LABELS[exercise.ui_type as UiType] ?? exercise.ui_type}
    </span>
    <p className="exercise-question">{exercise.question || <em>{tr.lessonExercises.noQuestionText}</em>}</p>
    <div className="exercise-row-actions">
      <button
        type="button"
        disabled={index === 0}
        onClick={onMoveUp}
        className="icon-button"
        aria-label={tr.lessonExercises.moveUpAria.replace("{n}", String(index + 1))}
        title={tr.lessonExercises.moveUpAria.replace("{n}", String(index + 1))}
      >
        <ChevronUp size={15} />
      </button>
      <button
        type="button"
        disabled={index === total - 1}
        onClick={onMoveDown}
        className="icon-button"
        aria-label={tr.lessonExercises.moveDownAria.replace("{n}", String(index + 1))}
        title={tr.lessonExercises.moveDownAria.replace("{n}", String(index + 1))}
      >
        <ChevronDown size={15} />
      </button>
      <button
        type="button"
        onClick={onEdit}
        className="icon-button"
        aria-label={tr.lessonExercises.editAria.replace("{n}", String(index + 1))}
        title={tr.common.edit}
      >
        <Pencil size={15} />
      </button>
      <button
        type="button"
        onClick={onDelete}
        className="icon-button exercise-delete-button"
        aria-label={tr.lessonExercises.deleteAria.replace("{n}", String(index + 1))}
        title={tr.common.delete}
      >
        <Trash2 size={15} />
      </button>
    </div>
  </div>
  );
};

// ─── main page ────────────────────────────────────────────────────────────────

export const LessonExercisesPage = () => {
  const confirm = useConfirm();
  const { t } = useI18n();
  const { courseId, unitId, lessonId } = useParams<{
    courseId: string;
    unitId: string;
    lessonId: string;
  }>();
  const navigate = useNavigate();

  const [lesson, setLesson] = useState<LessonDetail | null>(null);
  const [exercises, setExercises] = useState<Exercise[]>([]);
  const [estimatedMinutes, setEstimatedMinutes] = useState(10);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [isDirty, setIsDirty] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saveSuccess, setSaveSuccess] = useState(false);
  const [generating, setGenerating] = useState(false);
  const generatingRef = useRef(false);
  const savingRef = useRef(false);
  const [genError, setGenError] = useState<{ message: string; retry: boolean } | null>(null);
  const [genNotice, setGenNotice] = useState<string | null>(null);

  // Modal states
  const [showTypeSelector, setShowTypeSelector] = useState(false);
  const [editingExercise, setEditingExercise] = useState<{ exercise: Exercise; index: number } | null>(null);

  // Load lesson detail
  useEffect(() => {
    if (!lessonId) return;
    setLoading(true);
    getLessonDetail(lessonId)
      .then((res) => {
        if (res.success && res.data) {
          setLesson(res.data);
          setExercises(res.data.content?.exercises ?? []);
          setEstimatedMinutes(res.data.estimated_minutes ?? 10);
        } else {
          setError(t.lessonExercises.loadFailed);
        }
      })
      .catch(() => setError(t.lessonExercises.serverError))
      .finally(() => setLoading(false));
  }, [lessonId]);

  // Warn before closing/reloading the tab with unsaved exercises.
  useEffect(() => {
    if (!isDirty) return;
    const onBeforeUnload = (e: BeforeUnloadEvent) => {
      e.preventDefault();
      e.returnValue = "";
    };
    window.addEventListener("beforeunload", onBeforeUnload);
    return () => window.removeEventListener("beforeunload", onBeforeUnload);
  }, [isDirty]);

  const markDirty = useCallback(() => {
    setIsDirty(true);
    setSaveSuccess(false);
  }, []);

  // Add new exercise
  const handleTypeSelected = (uiType: UiType) => {
    setShowTypeSelector(false);
    const ex = defaultExercise(uiType, exercises.length);
    setEditingExercise({ exercise: ex, index: exercises.length });
  };

  // Save exercise from modal
  const handleSaveExercise = (updated: Exercise) => {
    setExercises((prev) => {
      const isNew = !prev.find((e) => e.id === updated.id);
      if (isNew) return [...prev, updated];
      return prev.map((e) => (e.id === updated.id ? updated : e));
    });
    setEditingExercise(null);
    markDirty();
  };

  const handleDelete = async (index: number) => {
    if (!(await confirm({ message: t.lessonExercises.deleteConfirm, confirmLabel: t.common.delete, danger: true }))) return;
    setExercises((prev) => prev.filter((_, i) => i !== index));
    markDirty();
  };

  const handleMove = (index: number, direction: -1 | 1) => {
    setExercises((prev) => {
      const next = [...prev];
      const target = index + direction;
      if (target < 0 || target >= next.length) return prev;
      [next[index], next[target]] = [next[target], next[index]];
      return next;
    });
    markDirty();
  };

  const handleSaveAll = async () => {
    if (!lessonId || generatingRef.current) return;
    savingRef.current = true;
    setSaving(true);
    setError(null);
    try {
      const res = await updateLessonContent(lessonId, exercises, estimatedMinutes);
      if (res.success) {
        setIsDirty(false);
        setSaveSuccess(true);
        if (res.data) {
          setLesson(res.data);
        }
        setTimeout(() => setSaveSuccess(false), 3000);
      } else {
        setError(res.message ?? t.common.saveFailed);
      }
    } catch (err: any) {
      // Server rejects e.g. emptying exercises of a live lesson — show why.
      setError(err?.message || t.lessonExercises.serverError);
    } finally {
      savingRef.current = false;
      setSaving(false);
    }
  };

  // Draft only: the exercises are appended and marked dirty, never saved here.
  const handleGenerate = async () => {
    if (!lessonId || generatingRef.current || savingRef.current) return;
    generatingRef.current = true;
    setGenerating(true);
    setGenError(null);
    setGenNotice(null);
    try {
      const res = await generateLessonExercises(lessonId);
      const drafts = res.data?.exercises ?? [];
      setExercises((prev) => appendWithFreshIds(prev, drafts, lessonId));
      if (drafts.length > 0) markDirty();
      setGenNotice(t.aiGenerate.added.replace("{count}", String(drafts.length)));
    } catch (err: any) {
      if (err?.status === 503) setGenError({ message: t.aiGenerate.unavailable, retry: false });
      else if (err?.status === 502) setGenError({ message: t.aiGenerate.couldNotProduce, retry: true });
      else setGenError({ message: err?.message || t.aiGenerate.couldNotProduce, retry: false });
    } finally {
      generatingRef.current = false;
      setGenerating(false);
    }
  };

  const goBack = async () => {
    if (isDirty) {
      const ok = await confirm({
        message: t.lessonExercises.discardConfirm,
        confirmLabel: t.lessonExercises.discardConfirmLabel,
        danger: true,
      });
      if (!ok) return;
    }
    if (courseId && unitId && courseId !== "_") {
      navigate(`/admin/courses/${courseId}/units/${unitId}/lessons`);
    } else {
      navigate("/admin/lessons");
    }
  };

  // ── render ──

  if (loading) {
    return (
      <div className="lesson-exercise-loading">
        <Loader2 size={28} className="is-spinning" aria-label={t.common.loading} />
      </div>
    );
  }

  return (
    <div className="stack lesson-exercises-page">
      {/* Header */}
      <div>
        <button
          type="button"
          onClick={goBack}
          className="ghost-button small lesson-back-button"
        >
          <ArrowLeft size={16} /> {t.lessonExercises.backToLessons}
        </button>
      </div>

      <section className="panel lesson-summary">
        <div className="lesson-summary-title">
          <span className="stat-icon"><BookOpen size={18} aria-hidden="true" /></span>
          <h1>{lesson?.title ?? "Bài học"}</h1>
          {lesson?.lesson_type && (
            <span className="status-pill info">
              {lesson.lesson_type}
            </span>
          )}
        </div>
        {lesson?.description && (
          <p className="lesson-description">{lesson.description}</p>
        )}
        <div className="lesson-meta-row">
          <div className="lesson-duration-field">
            <Clock size={15} aria-hidden="true" />
            <label htmlFor="estimated-minutes">{t.lessonExercises.estimatedMinutesLabel}</label>
            <input
              id="estimated-minutes"
              type="number"
              min={1}
              max={120}
              className="lesson-duration-input"
              value={estimatedMinutes}
              onChange={(e) => {
                setEstimatedMinutes(Number(e.target.value));
                markDirty();
              }}
            />
          </div>
          <span className="table-meta">{t.lessonExercises.exercisesCount.replace("{n}", String(exercises.length))}</span>
        </div>
      </section>

      {/* Error */}
      {error && (
        <div className="form-error">
          {error}
        </div>
      )}

      {/* Save success */}
      {saveSuccess && (
        <div className="form-success">
          {t.lessonExercises.savedSuccess}
        </div>
      )}

      {/* Exercise list + actions header */}
      <div className="lesson-exercise-section-header">
        <h2>
          {t.lessonExercises.listTitle.replace("{n}", String(exercises.length))}
        </h2>
        <div className="table-actions">
          <button
            type="button"
            onClick={handleGenerate}
            disabled={generating || saving}
            className="ghost-button"
          >
            {generating ? (
              <Loader2 size={15} className="is-spinning" aria-hidden="true" />
            ) : (
              <Sparkles size={15} aria-hidden="true" />
            )}
            {generating ? t.aiGenerate.running : t.aiGenerate.button}
          </button>
          <button
            type="button"
            onClick={() => setShowTypeSelector(true)}
            className="primary-button"
          >
            <Plus size={15} /> {t.lessonExercises.addExercise}
          </button>
        </div>
      </div>

      <div role="status" aria-live="polite">
        {genNotice && <div className="form-success">{genNotice}</div>}
      </div>
      {genError && (
        <div className="form-error" role="alert">
          {genError.message}
          {genError.retry && (
            <>
              {" "}
              <button type="button" className="ghost-button small" onClick={handleGenerate} disabled={generating || saving}>
                {t.aiGenerate.retry}
              </button>
            </>
          )}
        </div>
      )}

      {/* Exercise list */}
      {exercises.length === 0 ? (
        <div className="empty-state lesson-exercise-empty">
          <BookOpen size={36} aria-hidden="true" />
          <p className="empty-title">{t.lessonExercises.emptyTitle}</p>
          <p className="empty-description">{t.lessonExercises.emptyDesc}</p>
        </div>
      ) : (
        <div className="exercise-list">
          {exercises.map((ex, idx) => (
            <ExerciseRow
              key={ex.id}
              exercise={ex}
              index={idx}
              total={exercises.length}
              onEdit={() => setEditingExercise({ exercise: ex, index: idx })}
              onDelete={() => handleDelete(idx)}
              onMoveUp={() => handleMove(idx, -1)}
              onMoveDown={() => handleMove(idx, 1)}
            />
          ))}
        </div>
      )}

      {/* Save bar */}
      <div className="lesson-save-bar">
        <button
          type="button"
          disabled={!isDirty || saving || generating}
          onClick={handleSaveAll}
          className="primary-button lesson-save-button"
        >
          {saving ? (
            <Loader2 size={16} className="is-spinning" aria-hidden="true" />
          ) : (
            <Save size={16} />
          )}
          {saving ? t.lessonExercises.savingAll : t.lessonExercises.saveAll}
        </button>
      </div>

      {/* Modals */}
      {showTypeSelector && (
        <TypeSelectorModal
          onSelect={handleTypeSelected}
          onClose={() => setShowTypeSelector(false)}
        />
      )}

      {editingExercise && (
        <ExerciseModal
          initial={editingExercise.exercise}
          index={editingExercise.index}
          onSave={handleSaveExercise}
          onClose={() => setEditingExercise(null)}
        />
      )}
    </div>
  );
};
