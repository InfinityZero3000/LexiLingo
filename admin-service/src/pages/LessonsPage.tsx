import React, { useEffect, useState } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { DataTable } from "../components/DataTable";
import { SectionHeader } from "../components/SectionHeader";
import { EmptyState } from "../components/EmptyState";
import { StatusPill } from "../components/StatusPill";
import {
  listLessonsAdmin,
  listCoursesAdmin,
  listUnitsAdmin,
  createLesson,
  updateLesson,
  deleteLesson,
  type LessonItem,
  type CourseItem,
  type UnitItem,
} from "../lib/adminApi";
import { useI18n } from "../lib/i18n";

const LESSON_TYPES = ["lesson", "practice", "review", "test", "vocabulary", "grammar"];

const typeColors: Record<string, "info" | "success" | "warning" | "danger"> = {
  lesson: "info",
  practice: "success",
  review: "warning",
  test: "danger",
  vocabulary: "info",
  grammar: "warning",
};

export const LessonsPage = () => {
  const { courseId: paramCourseId, unitId: paramUnitId } = useParams<{ courseId: string; unitId: string }>();
  const navigate = useNavigate();
  const { t } = useI18n();
  const [lessons, setLessons] = useState<LessonItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Course & Unit filter (standalone mode)
  const [courses, setCourses] = useState<CourseItem[]>([]);
  const [units, setUnits] = useState<UnitItem[]>([]);
  const [selectedCourseId, setSelectedCourseId] = useState<string>("");
  const [selectedUnitId, setSelectedUnitId] = useState<string>("");
  const isStandalone = !paramUnitId;
  const activeUnitId = paramUnitId || selectedUnitId || undefined;
  const activeCourseId = paramCourseId || selectedCourseId || undefined;

  // Form
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [formUnitId, setFormUnitId] = useState("");
  const [form, setForm] = useState({
    title: "",
    description: "",
    order_index: 0,
    lesson_type: "lesson",
    xp_reward: 10,
    pass_threshold: 80,
  });

  const resetForm = () => {
    setForm({
      title: "",
      description: "",
      order_index: lessons.length,
      lesson_type: "lesson",
      xp_reward: 10,
      pass_threshold: 80,
    });
    setEditingId(null);
  };

  // Load courses for filter
  const loadCourses = async () => {
    try {
      const res = await listCoursesAdmin({ page_size: 100 });
      setCourses(res.data?.courses || []);
    } catch {}
  };

  // Load units for selected course
  const loadUnits = async (cId?: string) => {
    try {
      const res = await listUnitsAdmin(cId);
      setUnits(res.data || []);
    } catch {}
  };

  const loadLessons = async () => {
    setLoading(true);
    setError(null);
    try {
      const params: { unit_id?: string; course_id?: string } = {};
      if (activeUnitId) params.unit_id = activeUnitId;
      else if (activeCourseId) params.course_id = activeCourseId;
      const res = await listLessonsAdmin(params);
      setLessons(res.data || []);
    } catch (err: any) {
      setError(err?.message || t.lessons.loadFailed);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (isStandalone) {
      loadCourses();
      loadUnits();
    }
  }, []);

  // When course filter changes, reload units
  useEffect(() => {
    if (isStandalone && selectedCourseId) {
      loadUnits(selectedCourseId);
      setSelectedUnitId("");
    } else if (isStandalone && !selectedCourseId) {
      loadUnits();
      setSelectedUnitId("");
    }
  }, [selectedCourseId]);

  useEffect(() => { void loadLessons(); }, [paramUnitId, selectedUnitId, selectedCourseId]);

  // Build lookup maps
  const unitMap = new Map(units.map(u => [u.id, u.title]));
  const courseMap = new Map(courses.map(c => [c.id, c.title]));

  const handleEdit = (lesson: LessonItem) => {
    setEditingId(lesson.id);
    setForm({
      title: lesson.title,
      description: lesson.description || "",
      order_index: lesson.order_index,
      lesson_type: lesson.lesson_type,
      xp_reward: lesson.xp_reward,
      pass_threshold: lesson.pass_threshold,
    });
    setShowForm(true);
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    const targetUnitId = activeUnitId || formUnitId;
    if (!targetUnitId) return;
    setSaving(true);
    setError(null);
    try {
      if (editingId) {
        await updateLesson(editingId, form);
      } else {
        await createLesson({
          ...form,
          unit_id: targetUnitId,
          order_index: form.order_index || lessons.length,
        });
      }
      resetForm();
      setShowForm(false);
      setFormUnitId("");
      await loadLessons();
    } catch (err: any) {
      setError(err?.message || t.common.saveFailed);
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async (id: string) => {
    if (!confirm(t.lessons.deleteLesson)) return;
    try {
      await deleteLesson(id);
      await loadLessons();
    } catch (err: any) {
      setError(err?.message || t.common.deleteFailed);
    }
  };

  return (
    <div className="stack">
      <SectionHeader
        title={t.lessons.title}
        description={`${lessons.length} ${t.lessons.description}`}
      />

      {error && <div className="form-error">{error}</div>}

      <div className="panel" style={{ padding: "12px 16px" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
          {isStandalone && (
            <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap" }}>
              <select
                value={selectedCourseId}
                onChange={(e) => setSelectedCourseId(e.target.value)}
                style={{ minWidth: 200, padding: "8px 12px", borderRadius: 8, border: "1px solid var(--line)", background: "var(--panel)", fontSize: 14 }}
              >
                <option value="">-- Tất cả khóa học --</option>
                {courses.map(c => <option key={c.id} value={c.id}>{c.title}</option>)}
              </select>
              <select
                value={selectedUnitId}
                onChange={(e) => setSelectedUnitId(e.target.value)}
                style={{ minWidth: 200, padding: "8px 12px", borderRadius: 8, border: "1px solid var(--line)", background: "var(--panel)", fontSize: 14 }}
              >
                <option value="">-- Tất cả chương --</option>
                {units.map(u => <option key={u.id} value={u.id}>{u.title}</option>)}
              </select>
            </div>
          )}
          <button className="primary-button" onClick={() => { resetForm(); setShowForm(true); }}>
            {t.lessons.createLesson}
          </button>
        </div>
      </div>

      <div className="panel">
        {loading ? (
          <div className="loading">{t.common.loading}</div>
        ) : lessons.length === 0 ? (
          <EmptyState title={t.lessons.noLessons} description={t.lessons.noLessonsDesc} />
        ) : (
          <DataTable
            columns={[
              {
                header: "#",
                render: (row: LessonItem) => <span className="table-meta">{row.order_index}</span>,
                align: "center",
              },
              ...(isStandalone ? [{
                header: "Chương",
                render: (row: LessonItem) => (
                  <span className="table-meta" style={{ color: "var(--text)", fontWeight: 500 }}>
                    {unitMap.get(row.unit_id) || row.unit_id.slice(0, 8)}
                  </span>
                ),
              }] : []),
              {
                header: t.lessons.lesson,
                render: (row: LessonItem) => (
                  <div>
                    <div className="table-title">{row.title}</div>
                    <div className="table-sub">{row.description || "—"}</div>
                  </div>
                ),
              },
              {
                header: t.lessons.type,
                render: (row: LessonItem) => (
                  <StatusPill tone={typeColors[row.lesson_type] || "info"} label={row.lesson_type} />
                ),
                align: "center",
              },
              {
                header: "XP",
                render: (row: LessonItem) => <span className="table-meta">{row.xp_reward}</span>,
                align: "center",
              },
              {
                header: "Ngưỡng đạt",
                render: (row: LessonItem) => <span className="table-meta">{row.pass_threshold}%</span>,
                align: "center",
              },
              {
                header: "Bài tập",
                render: (row: LessonItem) => <span className="table-meta">{row.total_exercises}</span>,
                align: "center",
              },
              {
                header: t.common.actions,
                render: (row: LessonItem) => (
                  <div className="table-actions">
                    <button className="ghost-button small" onClick={() => handleEdit(row)}>{t.common.edit}</button>
                    <button className="ghost-button small danger" onClick={() => handleDelete(row.id)}>{t.common.delete}</button>
                  </div>
                ),
                align: "right",
              },
            ]}
            rows={lessons}
          />
        )}
      </div>

      {/* Create/Edit Modal */}
      {showForm && (
        <div className="modal-overlay" onClick={() => setShowForm(false)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 520 }}>
            <h3>{editingId ? t.lessons.editLesson : t.lessons.createNew}</h3>
            <form className="form" onSubmit={handleSave}>
              {isStandalone && !editingId && (
                <label>
                  Chương *
                  <select
                    value={formUnitId}
                    onChange={(e) => setFormUnitId(e.target.value)}
                    required
                  >
                    <option value="">-- Chọn chương --</option>
                    {units.map(u => <option key={u.id} value={u.id}>{u.title}</option>)}
                  </select>
                </label>
              )}
              <label>
                Tiêu đề *
                <input value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} required />
              </label>
              <label>
                Mô tả
                <textarea rows={2} value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} />
              </label>
              <div className="form-row">
                <label>
                  Loại bài học *
                  <select value={form.lesson_type} onChange={(e) => setForm({ ...form, lesson_type: e.target.value })}>
                    {LESSON_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
                  </select>
                </label>
                <label>
                  Thứ tự
                  <input type="number" min={0} value={form.order_index} onChange={(e) => setForm({ ...form, order_index: Number(e.target.value) })} />
                </label>
              </div>
              <div className="form-row">
                <label>
                  XP thưởng
                  <input type="number" min={0} value={form.xp_reward} onChange={(e) => setForm({ ...form, xp_reward: Number(e.target.value) })} />
                </label>
                <label>
                  Ngưỡng đạt (%)
                  <input type="number" min={0} max={100} value={form.pass_threshold} onChange={(e) => setForm({ ...form, pass_threshold: Number(e.target.value) })} />
                </label>
              </div>
              <div style={{ display: "flex", gap: 8, justifyContent: "flex-end" }}>
                <button className="ghost-button" type="button" onClick={() => setShowForm(false)}>{t.common.cancel}</button>
                <button className="primary-button" type="submit" disabled={saving}>
                  {saving ? t.common.saving : editingId ? t.common.update : t.common.create}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
