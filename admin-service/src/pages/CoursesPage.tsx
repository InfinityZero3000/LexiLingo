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
import { CourseImportModal } from "../components/CourseImportModal";
import { useI18n } from "../lib/i18n";

const LEVELS = ["A1", "A2", "B1", "B2", "C1", "C2"];

export const CoursesPage = () => {
  const navigate = useNavigate();
  const { t } = useI18n();
  const [courses, setCourses] = useState<CourseItem[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showImport, setShowImport] = useState(false);
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
      setError(err?.message || t.courses.loadFailed);
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
      setError(err?.message || t.common.saveFailed);
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async (id: string) => {
    if (!confirm(t.courses.deleteCourse)) return;
    try {
      await deleteCourse(id);
      await loadCourses();
    } catch (err: any) {
      setError(err?.message || t.common.deleteFailed);
    }
  };

  return (
    <div className="stack">
      <SectionHeader
        title={t.courses.title}
        description={`${total} ${t.courses.description}`}
      />

      {error && <div className="form-error">{error}</div>}

      {/* Toolbar */}
      <div className="panel" style={{ padding: "12px 16px" }}>
        <div style={{ display: "flex", gap: 12, alignItems: "center", flexWrap: "wrap" }}>
          <form onSubmit={handleSearch} style={{ display: "flex", gap: 8, flex: 1, minWidth: 200 }}>
            <input
              placeholder={t.courses.searchPlaceholder}
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              style={{ flex: 1 }}
            />
            <button className="ghost-button" type="submit">{t.common.search}</button>
          </form>
          <select value={filterLevel} onChange={(e) => { setFilterLevel(e.target.value); setPage(1); }}>
            <option value="">{t.courses.allLevels}</option>
            {LEVELS.map((l) => <option key={l} value={l}>{l}</option>)}
          </select>
          <select value={filterPublished} onChange={(e) => { setFilterPublished(e.target.value); setPage(1); }}>
            <option value="">{t.courses.allStatus}</option>
            <option value="true">{t.common.published}</option>
            <option value="false">{t.common.draft}</option>
          </select>
          <button
            className="ghost-button"
            onClick={() => setShowImport(true)}
          >
            {t.courses.importData}
          </button>
          <button
            className="primary-button"
            onClick={() => { resetForm(); setShowForm(true); }}
          >
            {t.courses.createCourse}
          </button>
        </div>
      </div>

      {/* Course list */}
      <div className="panel">
        {loading ? (
          <div className="loading">{t.common.loading}</div>
        ) : courses.length === 0 ? (
          <EmptyState title={t.courses.noCourses} description={t.courses.noCoursesDesc} />
        ) : (
          <>
            <DataTable
              columns={[
                {
                  header: t.courses.course,
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
                  header: t.courses.level,
                  render: (row) => <StatusPill tone="info" label={row.level} />,
                  align: "center",
                },
                {
                  header: t.courses.lessons,
                  render: (row) => <span className="table-meta">{row.total_lessons}</span>,
                  align: "center",
                },
                {
                  header: t.courses.xp,
                  render: (row) => <span className="table-meta">{row.total_xp}</span>,
                  align: "center",
                },
                {
                  header: t.common.status,
                  render: (row) => (
                    <StatusPill
                      tone={row.is_published ? "success" : "warning"}
                      label={row.is_published ? t.common.published : t.common.draft}
                    />
                  ),
                  align: "center",
                },
                {
                  header: t.common.actions,
                  render: (row) => (
                    <div className="table-actions">
                      <button className="ghost-button small" onClick={() => navigate(`/admin/courses/${row.id}/units`)}>
                        {t.courses.units}
                      </button>
                      <button className="ghost-button small" onClick={() => handleEdit(row)}>{t.common.edit}</button>
                      <button className="ghost-button small danger" onClick={() => handleDelete(row.id)}>{t.common.delete}</button>
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
                {t.courses.prev}
              </button>
              <span className="table-meta" style={{ padding: "6px 12px" }}>
                {t.common.page} {page} {t.common.of} {Math.ceil(total / 20) || 1}
              </span>
              <button className="ghost-button small" disabled={page >= Math.ceil(total / 20)} onClick={() => setPage(page + 1)}>
                {t.courses.next}
              </button>
            </div>
          </>
        )}
      </div>

      {showForm && (
        <div className="modal-overlay" onClick={() => setShowForm(false)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 520 }}>
            <h3>{editingId ? t.courses.editCourse : t.courses.createNew}</h3>
            <form className="form" onSubmit={handleSave}>
              <label>
                {t.courses.courseTitle}
                <input value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} required />
              </label>
              <label>
                {t.common.description}
                <textarea rows={3} value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} />
              </label>
              <div className="form-row">
                <label>
                  {t.courses.language}
                  <input value={form.language} onChange={(e) => setForm({ ...form, language: e.target.value })} />
                </label>
                <label>
                  {t.courses.level}
                  <select value={form.level} onChange={(e) => setForm({ ...form, level: e.target.value })}>
                    {LEVELS.map((l) => <option key={l} value={l}>{l}</option>)}
                  </select>
                </label>
              </div>
              <label>
                {t.courses.tags}
                <input value={form.tags} onChange={(e) => setForm({ ...form, tags: e.target.value })} />
              </label>
              <label>
                {t.courses.thumbnailUrl}
                <input value={form.thumbnail_url} onChange={(e) => setForm({ ...form, thumbnail_url: e.target.value })} />
              </label>
              <label className="checkbox">
                <input type="checkbox" checked={form.is_published} onChange={(e) => setForm({ ...form, is_published: e.target.checked })} />
                {t.courses.publishNow}
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

      {showImport && (
        <CourseImportModal
          onClose={() => setShowImport(false)}
          onImported={() => { void loadCourses(); }}
        />
      )}
    </div>
  );
};
