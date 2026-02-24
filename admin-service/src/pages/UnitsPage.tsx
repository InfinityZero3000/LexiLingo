import React, { useEffect, useState } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { DataTable } from "../components/DataTable";
import { SectionHeader } from "../components/SectionHeader";
import { EmptyState } from "../components/EmptyState";
import {
  listUnitsAdmin,
  listCoursesAdmin,
  createUnit,
  updateUnit,
  deleteUnit,
  type UnitItem,
  type CourseItem,
} from "../lib/adminApi";
import { useI18n } from "../lib/i18n";

export const UnitsPage = () => {
  const { courseId: paramCourseId } = useParams<{ courseId: string }>();
  const navigate = useNavigate();
  const { t } = useI18n();
  const [units, setUnits] = useState<UnitItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Course filter (standalone mode)
  const [courses, setCourses] = useState<CourseItem[]>([]);
  const [selectedCourseId, setSelectedCourseId] = useState<string>("");
  const isStandalone = !paramCourseId;
  const activeCourseId = paramCourseId || selectedCourseId || undefined;

  // Form
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [formCourseId, setFormCourseId] = useState("");
  const [form, setForm] = useState({
    title: "",
    description: "",
    order_index: 0,
    background_color: "",
    icon_url: "",
  });

  const resetForm = () => {
    setForm({ title: "", description: "", order_index: units.length, background_color: "", icon_url: "" });
    setEditingId(null);
  };

  // Load courses list for filter dropdown
  const loadCourses = async () => {
    try {
      const res = await listCoursesAdmin({ page_size: 100 });
      setCourses(res.data?.courses || []);
    } catch {}
  };

  const loadUnits = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await listUnitsAdmin(activeCourseId);
      setUnits(res.data || []);
    } catch (err: any) {
      setError(err?.message || t.units.loadFailed);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (isStandalone) loadCourses();
  }, []);

  useEffect(() => { void loadUnits(); }, [paramCourseId, selectedCourseId]);

  // Build course name lookup
  const courseMap = new Map(courses.map(c => [c.id, c.title]));

  const handleEdit = (unit: UnitItem) => {
    setEditingId(unit.id);
    setForm({
      title: unit.title,
      description: unit.description || "",
      order_index: unit.order_index,
      background_color: unit.background_color || "",
      icon_url: unit.icon_url || "",
    });
    setShowForm(true);
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    const targetCourseId = activeCourseId || formCourseId;
    if (!targetCourseId) return;
    setSaving(true);
    setError(null);
    try {
      if (editingId) {
        await updateUnit(editingId, form);
      } else {
        await createUnit({ ...form, course_id: targetCourseId, order_index: form.order_index || units.length });
      }
      resetForm();
      setShowForm(false);
      setFormCourseId("");
      await loadUnits();
    } catch (err: any) {
      setError(err?.message || t.common.saveFailed);
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async (id: string) => {
    if (!confirm(t.units.deleteUnit)) return;
    try {
      await deleteUnit(id);
      await loadUnits();
    } catch (err: any) {
      setError(err?.message || t.common.deleteFailed);
    }
  };

  return (
    <div className="stack">
      <SectionHeader
        title={t.units.title}
        description={`${units.length} ${t.units.description}`}
      />

      {error && <div className="form-error">{error}</div>}

      <div className="panel" style={{ padding: "12px 16px" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12 }}>
          {isStandalone && (
            <select
              value={selectedCourseId}
              onChange={(e) => setSelectedCourseId(e.target.value)}
              style={{ minWidth: 220, padding: "8px 12px", borderRadius: 8, border: "1px solid var(--line)", background: "var(--panel)", fontSize: 14 }}
            >
              <option value="">-- Tất cả khóa học --</option>
              {courses.map(c => <option key={c.id} value={c.id}>{c.title}</option>)}
            </select>
          )}
          <button className="primary-button" onClick={() => { resetForm(); setShowForm(true); }}>
            {t.units.createUnit}
          </button>
        </div>
      </div>

      <div className="panel">
        {loading ? (
          <div className="loading">{t.common.loading}</div>
        ) : units.length === 0 ? (
          <EmptyState title={t.units.noUnits} description={t.units.noUnitsDesc} />
        ) : (
          <DataTable
            columns={[
              {
                header: "#",
                render: (row) => <span className="table-meta">{row.order_index}</span>,
                align: "center",
              },
              ...(isStandalone ? [{
                header: "Khóa học",
                render: (row: UnitItem) => (
                  <span className="table-meta" style={{ color: "var(--text)", fontWeight: 500 }}>
                    {courseMap.get(row.course_id) || row.course_id.slice(0, 8)}
                  </span>
                ),
              }] : []),
              {
                header: t.units.unit,
                render: (row: UnitItem) => (
                  <div>
                    <div
                      className="table-title"
                      style={{ cursor: "pointer", color: "var(--accent)" }}
                      onClick={() => navigate(`/admin/courses/${row.course_id}/units/${row.id}/lessons`)}
                    >
                      {row.title}
                    </div>
                    <div className="table-sub">{row.description || "—"}</div>
                  </div>
                ),
              },
              {
                header: "Bài học",
                render: (row: UnitItem) => <span className="table-meta">{row.total_lessons}</span>,
                align: "center",
              },
              {
                header: "Màu",
                render: (row: UnitItem) =>
                  row.background_color ? (
                    <div
                      style={{
                        width: 24,
                        height: 24,
                        borderRadius: 4,
                        background: row.background_color,
                        border: "1px solid var(--line)",
                        margin: "0 auto",
                      }}
                    />
                  ) : (
                    <span className="table-meta">—</span>
                  ),
                align: "center",
              },
              {
                header: t.common.actions,
                render: (row: UnitItem) => (
                  <div className="table-actions">
                    <button
                      className="ghost-button small"
                      onClick={() => navigate(`/admin/courses/${row.course_id}/units/${row.id}/lessons`)}
                    >
                      {t.nav.lessons}
                    </button>
                    <button className="ghost-button small" onClick={() => handleEdit(row)}>{t.common.edit}</button>
                    <button className="ghost-button small danger" onClick={() => handleDelete(row.id)}>{t.common.delete}</button>
                  </div>
                ),
                align: "right",
              },
            ]}
            rows={units}
          />
        )}
      </div>

      {/* Create/Edit Modal */}
      {showForm && (
        <div className="modal-overlay" onClick={() => setShowForm(false)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 480 }}>
            <h3>{editingId ? t.units.editUnit : t.units.createNew}</h3>
            <form className="form" onSubmit={handleSave}>
              {isStandalone && !editingId && (
                <label>
                  Khóa học *
                  <select
                    value={formCourseId}
                    onChange={(e) => setFormCourseId(e.target.value)}
                    required
                  >
                    <option value="">-- Chọn khóa học --</option>
                    {courses.map(c => <option key={c.id} value={c.id}>{c.title}</option>)}
                  </select>
                </label>
              )}
              <label>
                {t.units.unitTitle}
                <input value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} required />
              </label>
              <label>
                {t.common.description}
                <textarea rows={2} value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} />
              </label>
              <div className="form-row">
                <label>
                  {t.units.order}
                  <input type="number" min={0} value={form.order_index} onChange={(e) => setForm({ ...form, order_index: Number(e.target.value) })} />
                </label>
                <label>
                  Màu nền
                  <input value={form.background_color} onChange={(e) => setForm({ ...form, background_color: e.target.value })} placeholder="#4CAF50" />
                </label>
              </div>
              <label>
                Icon URL
                <input value={form.icon_url} onChange={(e) => setForm({ ...form, icon_url: e.target.value })} />
              </label>
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
