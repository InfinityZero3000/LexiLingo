import React, { useEffect, useState, useCallback } from "react";
import { useParams, useNavigate } from "react-router-dom";
import {
  getLessonDetail,
  updateLessonContent,
  type LessonDetail,
  type Exercise,
  type UiType,
  UI_TYPES,
  UI_TYPE_LABELS,
  UI_TYPE_TO_TYPE,
} from "../lib/adminApi";
import { ExerciseTypeForm } from "../components/ExerciseTypeForm";
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
  GripVertical,
  X,
} from "lucide-react";

// ─── helpers ────────────────────────────────────────────────────────────────

const makeId = () => `ex_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;

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
}) => (
  <div className="modal-overlay lesson-exercise-overlay" role="presentation">
    <div className="lesson-exercise-modal lesson-exercise-type-modal" role="dialog" aria-modal="true" aria-labelledby="exercise-type-title">
      <div className="lesson-exercise-modal-header">
        <h2 id="exercise-type-title">Chọn loại bài tập</h2>
        <button
          type="button"
          onClick={onClose}
          className="icon-button"
          aria-label="Đóng"
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
  </div>
);

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
  const [exercise, setExercise] = useState<Exercise>(initial);

  const handleSave = () => {
    if (!exercise.question.trim()) {
      alert("Vui lòng nhập câu hỏi / prompt.");
      return;
    }
    if (!exercise.correct_answer.trim() && exercise.ui_type !== "short_writing_answer") {
      alert("Vui lòng nhập đáp án đúng.");
      return;
    }
    onSave(exercise);
  };

  return (
    <div className="modal-overlay lesson-exercise-overlay" role="presentation">
      <div className="lesson-exercise-modal" role="dialog" aria-modal="true" aria-labelledby="exercise-editor-title">
        <div className="lesson-exercise-modal-header">
          <div>
            <span
              className={`exercise-type-tag ${TYPE_TONES[exercise.ui_type] ?? "tone-neutral"}`}
            >
              {UI_TYPE_LABELS[exercise.ui_type as UiType] ?? exercise.ui_type}
            </span>
            <h2 id="exercise-editor-title">
              Bài tập #{index + 1}
            </h2>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="icon-button"
            aria-label="Đóng"
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
              Difficulty (1–5)
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

        <div className="lesson-exercise-modal-footer">
          <button
            type="button"
            onClick={onClose}
            className="ghost-button"
          >
            Hủy
          </button>
          <button
            type="button"
            onClick={handleSave}
            className="primary-button"
          >
            <Save size={15} /> Lưu bài tập
          </button>
        </div>
      </div>
    </div>
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
}) => (
  <div className="exercise-row">
    <GripVertical size={16} className="exercise-drag-icon" aria-hidden="true" />
    <span className="exercise-index">
      {index + 1}
    </span>
    <span
      className={`exercise-type-tag ${TYPE_TONES[exercise.ui_type] ?? "tone-neutral"}`}
    >
      {UI_TYPE_LABELS[exercise.ui_type as UiType] ?? exercise.ui_type}
    </span>
    <p className="exercise-question">{exercise.question || <em>No question text</em>}</p>
    <div className="exercise-row-actions">
      <button
        type="button"
        disabled={index === 0}
        onClick={onMoveUp}
        className="icon-button"
        aria-label={`Di chuyển bài tập ${index + 1} lên`}
        title="Move up"
      >
        <ChevronUp size={15} />
      </button>
      <button
        type="button"
        disabled={index === total - 1}
        onClick={onMoveDown}
        className="icon-button"
        aria-label={`Di chuyển bài tập ${index + 1} xuống`}
        title="Move down"
      >
        <ChevronDown size={15} />
      </button>
      <button
        type="button"
        onClick={onEdit}
        className="icon-button"
        aria-label={`Sửa bài tập ${index + 1}`}
        title="Edit"
      >
        <Pencil size={15} />
      </button>
      <button
        type="button"
        onClick={onDelete}
        className="icon-button exercise-delete-button"
        aria-label={`Xóa bài tập ${index + 1}`}
        title="Delete"
      >
        <Trash2 size={15} />
      </button>
    </div>
  </div>
);

// ─── main page ────────────────────────────────────────────────────────────────

export const LessonExercisesPage = () => {
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
          setError("Không tải được bài học.");
        }
      })
      .catch(() => setError("Lỗi kết nối server."))
      .finally(() => setLoading(false));
  }, [lessonId]);

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

  const handleDelete = (index: number) => {
    if (!confirm("Xóa bài tập này?")) return;
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
    if (!lessonId) return;
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
        setError(res.message ?? "Lưu thất bại.");
      }
    } catch {
      setError("Lỗi kết nối server.");
    } finally {
      setSaving(false);
    }
  };

  const goBack = () => {
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
        <Loader2 size={28} className="is-spinning" aria-label="Đang tải" />
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
          <ArrowLeft size={16} /> Quay lại Lessons
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
            <label htmlFor="estimated-minutes">Estimated minutes:</label>
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
          <span className="table-meta">{exercises.length} bài tập</span>
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
          Đã lưu thành công!
        </div>
      )}

      {/* Exercise list + actions header */}
      <div className="lesson-exercise-section-header">
        <h2>
          Danh sách bài tập ({exercises.length})
        </h2>
        <button
          type="button"
          onClick={() => setShowTypeSelector(true)}
          className="primary-button"
        >
          <Plus size={15} /> Thêm bài tập
        </button>
      </div>

      {/* Exercise list */}
      {exercises.length === 0 ? (
        <div className="empty-state lesson-exercise-empty">
          <BookOpen size={36} aria-hidden="true" />
          <p className="empty-title">Chưa có bài tập nào</p>
          <p className="empty-description">Nhấn "Thêm bài tập" để bắt đầu</p>
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
          disabled={!isDirty || saving}
          onClick={handleSaveAll}
          className="primary-button lesson-save-button"
        >
          {saving ? (
            <Loader2 size={16} className="is-spinning" aria-hidden="true" />
          ) : (
            <Save size={16} />
          )}
          {saving ? "Đang lưu..." : "Lưu tất cả"}
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
