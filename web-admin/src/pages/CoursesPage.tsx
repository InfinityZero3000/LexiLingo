import React, { useEffect, useState } from "react";
import { DataTable } from "../components/DataTable";
import { SectionHeader } from "../components/SectionHeader";
import { EmptyState } from "../components/EmptyState";
import { StatusPill } from "../components/StatusPill";
import { apiFetch } from "../lib/api";
import { ENV } from "../lib/env";
import { PaginatedResponse } from "../lib/types";

type CourseListItem = {
  id: string;
  title: string;
  description?: string | null;
  language: string;
  level: string;
  tags?: string[];
  total_lessons?: number;
  total_xp?: number;
  estimated_duration?: number;
  is_enrolled?: boolean | null;
};

export const CoursesPage = () => {
  const [courses, setCourses] = useState<CourseListItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [form, setForm] = useState({
    title: "",
    description: "",
    language: "en",
    level: "A1",
    tags: "",
    thumbnail_url: "",
    is_published: false
  });

  const loadCourses = async () => {
    setLoading(true);
    setError(null);
    try {
      const response = await apiFetch<PaginatedResponse<CourseListItem>>(
        `${ENV.backendUrl}/courses?page=1&page_size=20`
      );
      setCourses(response.data);
    } catch (err: any) {
      setError(err?.message || "Không lấy được danh sách khóa học");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void loadCourses();
  }, []);

  const createCourse = async (event: React.FormEvent) => {
    event.preventDefault();
    setCreating(true);
    try {
      await apiFetch(`${ENV.backendUrl}/admin/courses`, {
        method: "POST",
        body: JSON.stringify({
          ...form,
          tags: form.tags
            .split(",")
            .map((tag) => tag.trim())
            .filter(Boolean)
        })
      });
      setForm({
        title: "",
        description: "",
        language: "en",
        level: "A1",
        tags: "",
        thumbnail_url: "",
        is_published: false
      });
      await loadCourses();
    } catch (err: any) {
      setError(err?.message || "Tạo khóa học thất bại");
    } finally {
      setCreating(false);
    }
  };

  const deleteCourse = async (courseId: string) => {
    if (!confirm("Xóa khóa học này?")) return;
    try {
      await apiFetch(`${ENV.backendUrl}/admin/courses/${courseId}`, {
        method: "DELETE"
      });
      await loadCourses();
    } catch (err: any) {
      setError(err?.message || "Xóa khóa học thất bại");
    }
  };

  return (
    <div className="stack">
      <div className="grid-2">
        <div className="panel">
          <SectionHeader
            title="Danh sách khóa học"
            description="Dữ liệu lấy từ /api/v1/courses"
          />
          {error && <div className="form-error">{error}</div>}
          {loading ? (
            <div className="loading">Đang tải dữ liệu...</div>
          ) : courses.length === 0 ? (
            <EmptyState title="Chưa có khóa học" description="Hãy tạo khóa học mới bên phải." />
          ) : (
            <DataTable
              columns={[
                {
                  header: "Khóa học",
                  render: (row) => (
                    <div>
                      <div className="table-title">{row.title}</div>
                      <div className="table-sub">{row.description || "Chưa có mô tả"}</div>
                    </div>
                  )
                },
                {
                  header: "Level",
                  render: (row) => <StatusPill tone="info" label={row.level} />,
                  align: "center"
                },
                {
                  header: "Ngôn ngữ",
                  render: (row) => <span className="table-meta">{row.language}</span>,
                  align: "center"
                },
                {
                  header: "Hành động",
                  render: (row) => (
                    <div className="table-actions">
                      <button className="ghost-button small">Sửa</button>
                      <button className="ghost-button small danger" onClick={() => deleteCourse(row.id)}>
                        Xóa
                      </button>
                    </div>
                  ),
                  align: "right"
                }
              ]}
              rows={courses}
            />
          )}
        </div>

        <div className="panel">
          <SectionHeader title="Tạo khóa học mới" description="POST /api/v1/admin/courses" />
          <form className="form" onSubmit={createCourse}>
            <label>
              Tiêu đề
              <input
                value={form.title}
                onChange={(e) => setForm({ ...form, title: e.target.value })}
                required
              />
            </label>
            <label>
              Mô tả
              <textarea
                rows={3}
                value={form.description}
                onChange={(e) => setForm({ ...form, description: e.target.value })}
              />
            </label>
            <div className="form-row">
              <label>
                Ngôn ngữ
                <input
                  value={form.language}
                  onChange={(e) => setForm({ ...form, language: e.target.value })}
                />
              </label>
              <label>
                Level
                <select
                  value={form.level}
                  onChange={(e) => setForm({ ...form, level: e.target.value })}
                >
                  {"A1 A2 B1 B2 C1 C2".split(" ").map((lvl) => (
                    <option key={lvl} value={lvl}>
                      {lvl}
                    </option>
                  ))}
                </select>
              </label>
            </div>
            <label>
              Tags (cách nhau bởi dấu phẩy)
              <input
                value={form.tags}
                onChange={(e) => setForm({ ...form, tags: e.target.value })}
              />
            </label>
            <label>
              Thumbnail URL
              <input
                value={form.thumbnail_url}
                onChange={(e) => setForm({ ...form, thumbnail_url: e.target.value })}
              />
            </label>
            <label className="checkbox">
              <input
                type="checkbox"
                checked={form.is_published}
                onChange={(e) => setForm({ ...form, is_published: e.target.checked })}
              />
              Publish ngay
            </label>
            <button className="primary-button" type="submit" disabled={creating}>
              {creating ? "Đang tạo..." : "Tạo khóa học"}
            </button>
          </form>
        </div>
      </div>
    </div>
  );
};
