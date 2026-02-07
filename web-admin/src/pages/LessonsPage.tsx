import React, { useEffect, useState } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { DataTable } from "../components/DataTable";
import { SectionHeader } from "../components/SectionHeader";
import { EmptyState } from "../components/EmptyState";
import { StatusPill } from "../components/StatusPill";
import {
  listLessonsAdmin,
  createLesson,
  updateLesson,
  deleteLesson,
  type LessonItem,
} from "../lib/adminApi";

const LESSON_TYPES = ["lesson", "practice", "review", "test"];

const typeColors: Record<string, "info" | "success" | "warning" | "danger"> = {
  lesson: "info",
  practice: "success",
  review: "warning",
  test: "danger",
};

export const LessonsPage = () => {
  const { courseId, unitId } = useParams<{ courseId: string; unitId: string }>();
  const navigate = useNavigate();
  const [lessons, setLessons] = useState<LessonItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Form
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
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

  const loadLessons = async () => {
    if (!unitId) return;
    setLoading(true);
    setError(null);
    try {
      const res = await listLessonsAdmin({ unit_id: unitId });
      setLessons(res.data || []);
    } catch (err: any) {
      setError(err?.message || "Lỗi tải lessons");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { void loadLessons(); }, [unitId]);

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
    if (!unitId) return;
    setSaving(true);
    setError(null);
    try {
      if (editingId) {
        await updateLesson(editingId, form);
      } else {
        await createLesson({
          ...form,
          unit_id: unitId,
          order_index: form.order_index || lessons.length,
        });
      }
      resetForm();
      setShowForm(false);
      await loadLessons();
    } catch (err: any) {
      setError(err?.message || "Lưu thất bại");
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async (id: string) => {
    if (!confirm("Xóa lesson này?")) return;
    try {
      await deleteLesson(id);
      await loadLessons();
    } catch (err: any) {
      setError(err?.message || "Xóa thất bại");
    }
  };

  return (
    <div className="stack">
      <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
        <button className="ghost-button small" onClick={() => navigate(`/admin/courses/${courseId}/units`)}>
          ← Units
        </button>
        <SectionHeader
          title="Quản lý Lessons"
          description={`${lessons.length} bài học trong unit`}
        />
      </div>

      {error && <div className="form-error">{error}</div>}

      <div className="panel" style={{ padding: "12px 16px" }}>
        <div style={{ display: "flex", justifyContent: "flex-end" }}>
          <button className="primary-button" onClick={() => { resetForm(); setShowForm(true); }}>
            + Thêm Lesson
          </button>
        </div>
      </div>

      <div className="panel">
        {loading ? (
          <div className="loading">Đang tải...</div>
        ) : lessons.length === 0 ? (
          <EmptyState title="Chưa có lesson" description="Tạo lesson mới cho unit này." />
        ) : (
          <DataTable
            columns={[
              {
                header: "#",
                render: (row) => <span className="table-meta">{row.order_index}</span>,
                align: "center",
              },
              {
                header: "Bài học",
                render: (row) => (
                  <div>
                    <div className="table-title">{row.title}</div>
                    <div className="table-sub">{row.description || "—"}</div>
                  </div>
                ),
              },
              {
                header: "Loại",
                render: (row) => (
                  <StatusPill tone={typeColors[row.lesson_type] || "info"} label={row.lesson_type} />
                ),
                align: "center",
              },
              {
                header: "XP",
                render: (row) => <span className="table-meta">{row.xp_reward}</span>,
                align: "center",
              },
              {
                header: "Ngưỡng đạt",
                render: (row) => <span className="table-meta">{row.pass_threshold}%</span>,
                align: "center",
              },
              {
                header: "Bài tập",
                render: (row) => <span className="table-meta">{row.total_exercises}</span>,
                align: "center",
              },
              {
                header: "Hành động",
                render: (row) => (
                  <div className="table-actions">
                    <button className="ghost-button small" onClick={() => handleEdit(row)}>Sửa</button>
                    <button className="ghost-button small danger" onClick={() => handleDelete(row.id)}>Xóa</button>
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
            <h3>{editingId ? "Chỉnh sửa Lesson" : "Tạo Lesson mới"}</h3>
            <form className="form" onSubmit={handleSave}>
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
                <button className="ghost-button" type="button" onClick={() => setShowForm(false)}>Hủy</button>
                <button className="primary-button" type="submit" disabled={saving}>
                  {saving ? "Đang lưu..." : editingId ? "Cập nhật" : "Tạo"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
