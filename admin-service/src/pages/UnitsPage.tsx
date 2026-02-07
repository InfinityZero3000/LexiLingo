import React, { useEffect, useState } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { DataTable } from "../components/DataTable";
import { SectionHeader } from "../components/SectionHeader";
import { EmptyState } from "../components/EmptyState";
import {
  listUnitsAdmin,
  createUnit,
  updateUnit,
  deleteUnit,
  type UnitItem,
} from "../lib/adminApi";

export const UnitsPage = () => {
  const { courseId } = useParams<{ courseId: string }>();
  const navigate = useNavigate();
  const [units, setUnits] = useState<UnitItem[]>([]);
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
    background_color: "",
    icon_url: "",
  });

  const resetForm = () => {
    setForm({ title: "", description: "", order_index: units.length, background_color: "", icon_url: "" });
    setEditingId(null);
  };

  const loadUnits = async () => {
    if (!courseId) return;
    setLoading(true);
    setError(null);
    try {
      const res = await listUnitsAdmin(courseId);
      setUnits(res.data || []);
    } catch (err: any) {
      setError(err?.message || "Lỗi tải units");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { void loadUnits(); }, [courseId]);

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
    if (!courseId) return;
    setSaving(true);
    setError(null);
    try {
      if (editingId) {
        await updateUnit(editingId, form);
      } else {
        await createUnit({ ...form, course_id: courseId, order_index: form.order_index || units.length });
      }
      resetForm();
      setShowForm(false);
      await loadUnits();
    } catch (err: any) {
      setError(err?.message || "Lưu thất bại");
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async (id: string) => {
    if (!confirm("Xóa unit này? Tất cả lessons trong unit cũng sẽ bị xóa.")) return;
    try {
      await deleteUnit(id);
      await loadUnits();
    } catch (err: any) {
      setError(err?.message || "Xóa thất bại");
    }
  };

  return (
    <div className="stack">
      <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
        <button className="ghost-button small" onClick={() => navigate("/admin/courses")}>← Khóa học</button>
        <SectionHeader
          title={`Quản lý Units`}
          description={`${units.length} units trong khóa học`}
        />
      </div>

      {error && <div className="form-error">{error}</div>}

      <div className="panel" style={{ padding: "12px 16px" }}>
        <div style={{ display: "flex", justifyContent: "flex-end" }}>
          <button className="primary-button" onClick={() => { resetForm(); setShowForm(true); }}>
            + Thêm Unit
          </button>
        </div>
      </div>

      <div className="panel">
        {loading ? (
          <div className="loading">Đang tải...</div>
        ) : units.length === 0 ? (
          <EmptyState title="Chưa có unit" description="Tạo unit mới cho khóa học này." />
        ) : (
          <DataTable
            columns={[
              {
                header: "#",
                render: (row) => <span className="table-meta">{row.order_index}</span>,
                align: "center",
              },
              {
                header: "Unit",
                render: (row) => (
                  <div>
                    <div
                      className="table-title"
                      style={{ cursor: "pointer", color: "var(--accent)" }}
                      onClick={() => navigate(`/admin/courses/${courseId}/units/${row.id}/lessons`)}
                    >
                      {row.title}
                    </div>
                    <div className="table-sub">{row.description || "—"}</div>
                  </div>
                ),
              },
              {
                header: "Lessons",
                render: (row) => <span className="table-meta">{row.total_lessons}</span>,
                align: "center",
              },
              {
                header: "Màu",
                render: (row) =>
                  row.background_color ? (
                    <div
                      style={{
                        width: 24,
                        height: 24,
                        borderRadius: 4,
                        background: row.background_color,
                        border: "1px solid var(--border)",
                        margin: "0 auto",
                      }}
                    />
                  ) : (
                    <span className="table-meta">—</span>
                  ),
                align: "center",
              },
              {
                header: "Hành động",
                render: (row) => (
                  <div className="table-actions">
                    <button
                      className="ghost-button small"
                      onClick={() => navigate(`/admin/courses/${courseId}/units/${row.id}/lessons`)}
                    >
                      Lessons
                    </button>
                    <button className="ghost-button small" onClick={() => handleEdit(row)}>Sửa</button>
                    <button className="ghost-button small danger" onClick={() => handleDelete(row.id)}>Xóa</button>
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
            <h3>{editingId ? "Chỉnh sửa Unit" : "Tạo Unit mới"}</h3>
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
                  Thứ tự
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
