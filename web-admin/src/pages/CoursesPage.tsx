import React, { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { DataTable } from "../components/DataTable";
import { SectionHeader } from "../components/SectionHeader";
import { EmptyState } from "../components/EmptyState";
import { StatusPill } from "../components/StatusPill";
import {
  listCoursesAdmin,
  createCourse,
  updateCourse,
  deleteCourse,
  type CourseItem,
} from "../lib/adminApi";

const LEVELS = ["A1", "A2", "B1", "B2", "C1", "C2"];

export const CoursesPage = () => {
  const navigate = useNavigate();
  const [courses, setCourses] = useState<CourseItem[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [filterLevel, setFilterLevel] = useState("");
  const [filterPublished, setFilterPublished] = useState<string>("");

  // Create/Edit form state
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [form, setForm] = useState({
    title: "",
    description: "",
    language: "en",
    level: "A1",
    tags: "",
    thumbnail_url: "",
    is_published: false,
  });

  const resetForm = () => {
    setForm({ title: "", description: "", language: "en", level: "A1", tags: "", thumbnail_url: "", is_published: false });
    setEditingId(null);
  };

  const loadCourses = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await listCoursesAdmin({
        page,
        page_size: 20,
        search: search || undefined,
        level: filterLevel || undefined,
        is_published: filterPublished === "" ? undefined : filterPublished === "true",
      });
      const data = res.data;
      if (data) {
        setCourses(data.courses || []);
        setTotal(data.total || 0);
      }
    } catch (err: any) {
      setError(err?.message || "Không tải được danh sách khóa học");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { void loadCourses(); }, [page, filterLevel, filterPublished]);

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    setPage(1);
    void loadCourses();
  };

  const handleEdit = (course: CourseItem) => {
    setEditingId(course.id);
    setForm({
      title: course.title,
      description: course.description || "",
      language: course.language,
      level: course.level,
      tags: (course.tags || []).join(", "),
      thumbnail_url: course.thumbnail_url || "",
      is_published: course.is_published,
    });
    setShowForm(true);
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setError(null);
    try {
      const payload = {
        ...form,
        tags: form.tags.split(",").map((t) => t.trim()).filter(Boolean),
      };
      if (editingId) {
        await updateCourse(editingId, payload);
      } else {
        await createCourse(payload);
      }
      resetForm();
      setShowForm(false);
      await loadCourses();
    } catch (err: any) {
      setError(err?.message || "Lưu thất bại");
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async (id: string) => {
    if (!confirm("Xóa khóa học này?")) return;
    try {
      await deleteCourse(id);
      await loadCourses();
    } catch (err: any) {
      setError(err?.message || "Xóa thất bại");
    }
  };

  return (
    <div className="stack">
      <SectionHeader
        title="Quản lý Khóa học"
        description={`${total} khóa học • Tạo, chỉnh sửa, quản lý nội dung khóa học`}
      />

      {error && <div className="form-error">{error}</div>}

      {/* Toolbar */}
      <div className="panel" style={{ padding: "12px 16px" }}>
        <div style={{ display: "flex", gap: 12, alignItems: "center", flexWrap: "wrap" }}>
          <form onSubmit={handleSearch} style={{ display: "flex", gap: 8, flex: 1, minWidth: 200 }}>
            <input
              placeholder="Tìm kiếm khóa học..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              style={{ flex: 1 }}
            />
            <button className="ghost-button" type="submit">Tìm</button>
          </form>
          <select value={filterLevel} onChange={(e) => { setFilterLevel(e.target.value); setPage(1); }}>
            <option value="">Tất cả level</option>
            {LEVELS.map((l) => <option key={l} value={l}>{l}</option>)}
          </select>
          <select value={filterPublished} onChange={(e) => { setFilterPublished(e.target.value); setPage(1); }}>
            <option value="">Tất cả trạng thái</option>
            <option value="true">Đã xuất bản</option>
            <option value="false">Bản nháp</option>
          </select>
          <button
            className="primary-button"
            onClick={() => { resetForm(); setShowForm(true); }}
          >
            + Tạo khóa học
          </button>
        </div>
      </div>

      {/* Course list */}
      <div className="panel">
        {loading ? (
          <div className="loading">Đang tải...</div>
        ) : courses.length === 0 ? (
          <EmptyState title="Chưa có khóa học" description="Hãy tạo khóa học mới." />
        ) : (
          <>
            <DataTable
              columns={[
                {
                  header: "Khóa học",
                  render: (row) => (
                    <div>
                      <div className="table-title" style={{ cursor: "pointer", color: "var(--accent)" }}
                        onClick={() => navigate(`/admin/courses/${row.id}/units`)}>
                        {row.title}
                      </div>
                      <div className="table-sub">{row.description || "—"}</div>
                    </div>
                  ),
                },
                {
                  header: "Level",
                  render: (row) => <StatusPill tone="info" label={row.level} />,
                  align: "center",
                },
                {
                  header: "Lessons",
                  render: (row) => <span className="table-meta">{row.total_lessons}</span>,
                  align: "center",
                },
                {
                  header: "XP",
                  render: (row) => <span className="table-meta">{row.total_xp}</span>,
                  align: "center",
                },
                {
                  header: "Trạng thái",
                  render: (row) => (
                    <StatusPill
                      tone={row.is_published ? "success" : "warning"}
                      label={row.is_published ? "Published" : "Draft"}
                    />
                  ),
                  align: "center",
                },
                {
                  header: "Hành động",
                  render: (row) => (
                    <div className="table-actions">
                      <button className="ghost-button small" onClick={() => navigate(`/admin/courses/${row.id}/units`)}>
                        Units
                      </button>
                      <button className="ghost-button small" onClick={() => handleEdit(row)}>Sửa</button>
                      <button className="ghost-button small danger" onClick={() => handleDelete(row.id)}>Xóa</button>
                    </div>
                  ),
                  align: "right",
                },
              ]}
              rows={courses}
            />
            {/* Pagination */}
            <div style={{ display: "flex", justifyContent: "center", gap: 8, marginTop: 16 }}>
              <button className="ghost-button small" disabled={page <= 1} onClick={() => setPage(page - 1)}>
                ← Trước
              </button>
              <span className="table-meta" style={{ padding: "6px 12px" }}>
                Trang {page} / {Math.ceil(total / 20) || 1}
              </span>
              <button className="ghost-button small" disabled={page >= Math.ceil(total / 20)} onClick={() => setPage(page + 1)}>
                Sau →
              </button>
            </div>
          </>
        )}
      </div>

      {/* Create/Edit Modal */}
      {showForm && (
        <div className="modal-overlay" onClick={() => setShowForm(false)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 520 }}>
            <h3>{editingId ? "Chỉnh sửa khóa học" : "Tạo khóa học mới"}</h3>
            <form className="form" onSubmit={handleSave}>
              <label>
                Tiêu đề *
                <input value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} required />
              </label>
              <label>
                Mô tả
                <textarea rows={3} value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} />
              </label>
              <div className="form-row">
                <label>
                  Ngôn ngữ
                  <input value={form.language} onChange={(e) => setForm({ ...form, language: e.target.value })} />
                </label>
                <label>
                  Level
                  <select value={form.level} onChange={(e) => setForm({ ...form, level: e.target.value })}>
                    {LEVELS.map((l) => <option key={l} value={l}>{l}</option>)}
                  </select>
                </label>
              </div>
              <label>
                Tags (cách bởi dấu phẩy)
                <input value={form.tags} onChange={(e) => setForm({ ...form, tags: e.target.value })} />
              </label>
              <label>
                Thumbnail URL
                <input value={form.thumbnail_url} onChange={(e) => setForm({ ...form, thumbnail_url: e.target.value })} />
              </label>
              <label className="checkbox">
                <input type="checkbox" checked={form.is_published} onChange={(e) => setForm({ ...form, is_published: e.target.checked })} />
                Xuất bản ngay
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
