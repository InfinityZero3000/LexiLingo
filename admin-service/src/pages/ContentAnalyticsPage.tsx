import React, { useEffect, useState } from "react";
import { SectionHeader } from "../components/SectionHeader";
import { StatCard } from "../components/StatCard";
import { DataTable } from "../components/DataTable";
import { StatusPill } from "../components/StatusPill";
import { EmptyState } from "../components/EmptyState";
import {
  getContentPerformance,
  getVocabEffectiveness,
  type ContentPerformance,
  type VocabEffectiveness,
} from "../lib/adminApi";

export const ContentAnalyticsPage = () => {
  const [perf, setPerf] = useState<ContentPerformance | null>(null);
  const [vocab, setVocab] = useState<VocabEffectiveness | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setLoading(true);
    Promise.allSettled([getContentPerformance(), getVocabEffectiveness()])
      .then(([perfRes, vocabRes]) => {
        if (perfRes.status === "fulfilled") setPerf(perfRes.value.data || null);
        if (vocabRes.status === "fulfilled") setVocab(vocabRes.value.data || null);
      })
      .catch((err) => setError(err?.message || "Lỗi tải analytics"))
      .finally(() => setLoading(false));
  }, []);

  if (loading) return <div className="loading">Đang tải analytics...</div>;

  const totalEnrollments = perf?.courses?.reduce((s, c) => s + c.enrollments, 0) || 0;
  const avgCompletion = perf?.courses?.length
    ? Math.round(perf.courses.reduce((s, c) => s + c.completion_rate, 0) / perf.courses.length)
    : 0;
  const totalLessonAttempts = perf?.lessons?.reduce((s, l) => s + l.attempts, 0) || 0;

  return (
    <div className="stack">
      <SectionHeader title="Content Analytics" description="Phân tích hiệu quả nội dung học" />

      {error && <div className="form-error">{error}</div>}

      {/* Summary Cards */}
      <div className="card-grid">
        <StatCard label="Lượt đăng ký" value={String(totalEnrollments)} accent="orange" />
        <StatCard label="Tỷ lệ hoàn thành" value={`${avgCompletion}%`} accent="teal" />
        <StatCard label="Lượt làm bài" value={String(totalLessonAttempts)} accent="berry" />
        <StatCard label="Từ vựng" value={String(vocab?.total_words || 0)} note={`Mastery: ${Math.round(vocab?.avg_mastery_rate || 0)}%`} accent="ink" />
      </div>

      {/* Course Performance */}
      <div className="panel">
        <h3 style={{ padding: "16px 16px 0" }}>Hiệu suất Khóa học</h3>
        {!perf?.courses?.length ? (
          <EmptyState title="Chưa có dữ liệu" description="Chưa có dữ liệu hiệu suất khóa học." />
        ) : (
          <DataTable
            columns={[
              {
                header: "Khóa học",
                render: (row) => <span className="table-title">{row.course_title}</span>,
              },
              {
                header: "Đăng ký",
                render: (row) => <span className="table-meta">{row.enrollments}</span>,
                align: "center",
              },
              {
                header: "Hoàn thành",
                render: (row) => <span className="table-meta">{row.completions}</span>,
                align: "center",
              },
              {
                header: "Tỷ lệ",
                render: (row) => (
                  <StatusPill
                    tone={row.completion_rate >= 50 ? "success" : row.completion_rate >= 20 ? "warning" : "danger"}
                    label={`${Math.round(row.completion_rate)}%`}
                  />
                ),
                align: "center",
              },
              {
                header: "Điểm TB",
                render: (row) => <span className="table-meta">{Math.round(row.avg_score)}</span>,
                align: "center",
              },
              {
                header: "Thời gian TB",
                render: (row) => <span className="table-meta">{Math.round(row.avg_time_minutes)} phút</span>,
                align: "center",
              },
            ]}
            rows={perf.courses}
          />
        )}
      </div>

      {/* Lesson Performance */}
      <div className="panel">
        <h3 style={{ padding: "16px 16px 0" }}>Hiệu suất Bài học</h3>
        {!perf?.lessons?.length ? (
          <EmptyState title="Chưa có dữ liệu" description="Chưa có dữ liệu hiệu suất bài học." />
        ) : (
          <DataTable
            columns={[
              {
                header: "Bài học",
                render: (row) => <span className="table-title">{row.lesson_title}</span>,
              },
              {
                header: "Lượt làm",
                render: (row) => <span className="table-meta">{row.attempts}</span>,
                align: "center",
              },
              {
                header: "Hoàn thành",
                render: (row) => <span className="table-meta">{row.completions}</span>,
                align: "center",
              },
              {
                header: "Điểm TB",
                render: (row) => (
                  <StatusPill
                    tone={row.avg_score >= 80 ? "success" : row.avg_score >= 50 ? "warning" : "danger"}
                    label={`${Math.round(row.avg_score)}`}
                  />
                ),
                align: "center",
              },
            ]}
            rows={perf.lessons}
          />
        )}
      </div>

      {/* Hardest Vocabulary */}
      <div className="panel">
        <h3 style={{ padding: "16px 16px 0" }}>Từ vựng khó nhất</h3>
        {!vocab?.hardest_words?.length ? (
          <EmptyState title="Chưa có dữ liệu" description="Chưa có dữ liệu từ vựng." />
        ) : (
          <DataTable
            columns={[
              {
                header: "Từ",
                render: (row) => <span className="table-title">{row.word}</span>,
              },
              {
                header: "Tỷ lệ nhớ",
                render: (row) => (
                  <StatusPill
                    tone={row.mastery_rate >= 50 ? "success" : row.mastery_rate >= 25 ? "warning" : "danger"}
                    label={`${Math.round(row.mastery_rate)}%`}
                  />
                ),
                align: "center",
              },
              {
                header: "Lượt ôn TB",
                render: (row) => <span className="table-meta">{Math.round(row.avg_reviews)}</span>,
                align: "center",
              },
            ]}
            rows={vocab.hardest_words}
          />
        )}
      </div>
    </div>
  );
};
