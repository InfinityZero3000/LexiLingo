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

const TYPE_COLORS: Record<string, string> = {
  multiple_choice: "bg-blue-100 text-blue-700",
  collocation_choice: "bg-blue-100 text-blue-700",
  image_based_choice: "bg-purple-100 text-purple-700",
  listen_and_choose: "bg-teal-100 text-teal-700",
  true_or_false: "bg-yellow-100 text-yellow-700",
  reading_comprehension: "bg-orange-100 text-orange-700",
  fill_in_the_blank: "bg-green-100 text-green-700",
  dictation: "bg-green-100 text-green-700",
  short_writing_answer: "bg-lime-100 text-lime-700",
  dialogue_completion: "bg-indigo-100 text-indigo-700",
  grammar_correction: "bg-red-100 text-red-700",
  arrange_the_sentence: "bg-cyan-100 text-cyan-700",
  match_word_to_meaning: "bg-pink-100 text-pink-700",
  cognitive_fluidity: "bg-pink-100 text-pink-700",
  categorization: "bg-violet-100 text-violet-700",
  speaking_repeat: "bg-amber-100 text-amber-700",
  pronunciation_practice: "bg-amber-100 text-amber-700",
  translation_choice: "bg-sky-100 text-sky-700",
  vocabulary_flashcard: "bg-emerald-100 text-emerald-700",
};

// ─── TypeSelector modal ──────────────────────────────────────────────────────

const TypeSelectorModal = ({
  onSelect,
  onClose,
}: {
  onSelect: (t: UiType) => void;
  onClose: () => void;
}) => (
  <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm">
    <div className="bg-white rounded-2xl shadow-2xl w-full max-w-2xl max-h-[80vh] flex flex-col">
      <div className="flex items-center justify-between px-6 py-4 border-b border-gray-100">
        <h2 className="text-lg font-bold text-gray-800">Chọn loại bài tập</h2>
        <button
          onClick={onClose}
          className="text-gray-400 hover:text-gray-600 text-xl font-bold w-8 h-8 flex items-center justify-center rounded-full hover:bg-gray-100"
        >
          ✕
        </button>
      </div>
      <div className="overflow-y-auto p-6 flex flex-col gap-6">
        {UI_TYPE_GROUPS.map((group) => (
          <div key={group.label}>
            <p className="text-xs font-semibold text-gray-400 uppercase tracking-widest mb-2">
              {group.label}
            </p>
            <div className="grid grid-cols-2 gap-2">
              {group.types.map((t) => (
                <button
                  key={t}
                  type="button"
                  onClick={() => onSelect(t)}
                  className={`flex items-center gap-2 px-3 py-2.5 rounded-xl text-left text-sm font-medium border border-transparent hover:border-blue-300 hover:bg-blue-50 transition-colors ${TYPE_COLORS[t] ?? "bg-gray-100 text-gray-700"}`}
                >
                  <span className="font-semibold">{UI_TYPE_LABELS[t]}</span>
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
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm">
      <div className="bg-white rounded-2xl shadow-2xl w-full max-w-xl max-h-[90vh] flex flex-col">
        <div className="flex items-center justify-between px-6 py-4 border-b border-gray-100">
          <div>
            <span
              className={`text-xs font-semibold px-2 py-0.5 rounded-full ${TYPE_COLORS[exercise.ui_type] ?? "bg-gray-100 text-gray-600"}`}
            >
              {UI_TYPE_LABELS[exercise.ui_type as UiType] ?? exercise.ui_type}
            </span>
            <h2 className="text-base font-bold text-gray-800 mt-1">
              Bài tập #{index + 1}
            </h2>
          </div>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-gray-600 text-xl font-bold w-8 h-8 flex items-center justify-center rounded-full hover:bg-gray-100"
          >
            ✕
          </button>
        </div>

        <div className="overflow-y-auto p-6 flex flex-col gap-4">
          <ExerciseTypeForm
            uiType={exercise.ui_type as UiType}
            value={exercise}
            onChange={setExercise}
          />

          {/* Difficulty */}
          <div className="flex flex-col gap-1">
            <label className="block text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1">
              Difficulty (1–5)
            </label>
            <div className="flex gap-2">
              {[1, 2, 3, 4, 5].map((d) => (
                <button
                  key={d}
                  type="button"
                  className={`w-9 h-9 rounded-lg text-sm font-bold border-2 transition-colors ${
                    exercise.difficulty === d
                      ? "border-blue-500 bg-blue-500 text-white"
                      : "border-gray-200 bg-white text-gray-600 hover:border-blue-300"
                  }`}
                  onClick={() => setExercise({ ...exercise, difficulty: d })}
                >
                  {d}
                </button>
              ))}
            </div>
          </div>
        </div>

        <div className="flex gap-3 px-6 py-4 border-t border-gray-100">
          <button
            type="button"
            onClick={onClose}
            className="flex-1 py-2.5 rounded-xl border border-gray-200 text-gray-600 text-sm font-semibold hover:bg-gray-50"
          >
            Hủy
          </button>
          <button
            type="button"
            onClick={handleSave}
            className="flex-1 py-2.5 rounded-xl bg-blue-600 text-white text-sm font-semibold hover:bg-blue-700 flex items-center justify-center gap-2"
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
  <div className="flex items-center gap-3 bg-white rounded-xl border border-gray-100 px-4 py-3 hover:border-blue-200 transition-colors group">
    <GripVertical size={16} className="text-gray-300 flex-shrink-0" />
    <span className="w-7 h-7 rounded-full bg-gray-100 text-gray-500 text-xs font-bold flex items-center justify-center flex-shrink-0">
      {index + 1}
    </span>
    <span
      className={`text-xs font-semibold px-2 py-0.5 rounded-full flex-shrink-0 ${TYPE_COLORS[exercise.ui_type] ?? "bg-gray-100 text-gray-600"}`}
    >
      {UI_TYPE_LABELS[exercise.ui_type as UiType] ?? exercise.ui_type}
    </span>
    <p className="flex-1 text-sm text-gray-700 truncate">{exercise.question || <em className="text-gray-400">No question text</em>}</p>
    <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
      <button
        type="button"
        disabled={index === 0}
        onClick={onMoveUp}
        className="p-1.5 rounded-lg hover:bg-gray-100 disabled:opacity-30 text-gray-500"
        title="Move up"
      >
        <ChevronUp size={15} />
      </button>
      <button
        type="button"
        disabled={index === total - 1}
        onClick={onMoveDown}
        className="p-1.5 rounded-lg hover:bg-gray-100 disabled:opacity-30 text-gray-500"
        title="Move down"
      >
        <ChevronDown size={15} />
      </button>
      <button
        type="button"
        onClick={onEdit}
        className="p-1.5 rounded-lg hover:bg-blue-50 text-blue-600"
        title="Edit"
      >
        <Pencil size={15} />
      </button>
      <button
        type="button"
        onClick={onDelete}
        className="p-1.5 rounded-lg hover:bg-red-50 text-red-500"
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
      <div className="flex items-center justify-center h-64">
        <Loader2 size={28} className="animate-spin text-blue-500" />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-6 p-6 max-w-3xl mx-auto">
      {/* Header */}
      <div className="flex items-start gap-4">
        <button
          type="button"
          onClick={goBack}
          className="flex items-center gap-1.5 text-sm text-gray-500 hover:text-gray-800 mt-0.5"
        >
          <ArrowLeft size={16} /> Quay lại Lessons
        </button>
      </div>

      <div className="bg-white rounded-2xl border border-gray-100 p-5 flex flex-col gap-2">
        <div className="flex items-center gap-2">
          <BookOpen size={18} className="text-blue-500" />
          <h1 className="text-xl font-bold text-gray-900">{lesson?.title ?? "Bài học"}</h1>
          {lesson?.lesson_type && (
            <span className="text-xs font-semibold px-2 py-0.5 rounded-full bg-blue-50 text-blue-600">
              {lesson.lesson_type}
            </span>
          )}
        </div>
        {lesson?.description && (
          <p className="text-sm text-gray-500">{lesson.description}</p>
        )}
        <div className="flex items-center gap-4 mt-2">
          <div className="flex items-center gap-1.5">
            <Clock size={14} className="text-gray-400" />
            <label className="text-xs text-gray-500">Estimated minutes:</label>
            <input
              type="number"
              min={1}
              max={120}
              className="w-16 border border-gray-200 rounded-lg px-2 py-1 text-sm text-center focus:outline-none focus:ring-2 focus:ring-blue-400"
              value={estimatedMinutes}
              onChange={(e) => {
                setEstimatedMinutes(Number(e.target.value));
                markDirty();
              }}
            />
          </div>
          <span className="text-xs text-gray-400">{exercises.length} bài tập</span>
        </div>
      </div>

      {/* Error */}
      {error && (
        <div className="bg-red-50 border border-red-200 rounded-xl px-4 py-3 text-sm text-red-600">
          {error}
        </div>
      )}

      {/* Save success */}
      {saveSuccess && (
        <div className="bg-green-50 border border-green-200 rounded-xl px-4 py-3 text-sm text-green-700 font-medium">
          Đã lưu thành công!
        </div>
      )}

      {/* Exercise list + actions header */}
      <div className="flex items-center justify-between">
        <h2 className="font-semibold text-gray-700">
          Danh sách bài tập ({exercises.length})
        </h2>
        <button
          type="button"
          onClick={() => setShowTypeSelector(true)}
          className="flex items-center gap-1.5 px-4 py-2 bg-blue-600 text-white rounded-xl text-sm font-semibold hover:bg-blue-700 transition-colors"
        >
          <Plus size={15} /> Thêm bài tập
        </button>
      </div>

      {/* Exercise list */}
      {exercises.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-16 border-2 border-dashed border-gray-200 rounded-2xl text-gray-400">
          <BookOpen size={36} className="mb-3 opacity-40" />
          <p className="text-sm font-medium">Chưa có bài tập nào</p>
          <p className="text-xs mt-1">Nhấn "Thêm bài tập" để bắt đầu</p>
        </div>
      ) : (
        <div className="flex flex-col gap-2">
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
      <div className="sticky bottom-4 flex justify-end">
        <button
          type="button"
          disabled={!isDirty || saving}
          onClick={handleSaveAll}
          className={`flex items-center gap-2 px-6 py-3 rounded-xl text-sm font-semibold shadow-lg transition-all ${
            isDirty && !saving
              ? "bg-blue-600 text-white hover:bg-blue-700 shadow-blue-200"
              : "bg-gray-100 text-gray-400 cursor-not-allowed shadow-none"
          }`}
        >
          {saving ? (
            <Loader2 size={16} className="animate-spin" />
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
