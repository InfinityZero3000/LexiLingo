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

const RateBarCell = ({
  percent,
  tone,
  label,
}: {
  percent: number;
  tone: "success" | "warning" | "danger" | "info";
  label: string;
}) => {
  const clamped = Math.max(0, Math.min(100, percent));
  const fillColor =
    tone === "success"
      ? "#FF4D00"
      : tone === "info"
        ? "#FF7A00"
        : tone === "warning"
          ? "#F59E0B"
          : "#F43F5E";

  return (
    <div style={{ display: "inline-flex", alignItems: "center", gap: 10, justifyContent: "center" }}>
      <div
        aria-hidden="true"
        style={{
          width: 64,
          height: 6,
          borderRadius: 999,
          background: "var(--panel-soft)",
          overflow: "hidden",
          flexShrink: 0,
        }}
      >
        <div
          style={{
            width: `${clamped}%`,
            height: "100%",
            borderRadius: 999,
            background: fillColor,
            transition: "width 0.35s ease",
          }}
        />
      </div>
      <StatusPill tone={tone} label={label} />
    </div>
  );
};

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
        <StatCard
          label="Lượt đăng ký"
          value={totalEnrollments.toLocaleString()}
          trend={`${perf?.courses?.length || 0} khóa học`}
          variant="blue"
          accent="orange"
        />
        <StatCard
          label="Tỷ lệ hoàn thành"
          value={`${avgCompletion}%`}
          trend={avgCompletion >= 50 ? "Mức hoàn thành tốt" : "Cần tối ưu lộ trình"}
          accent="teal"
        />
        <StatCard
          label="Lượt làm bài"
          value={totalLessonAttempts.toLocaleString()}
          trend={`${perf?.lessons?.length || 0} bài học`}
          accent="berry"
        />
        <StatCard
          label="Từ vựng"
          value={String(vocab?.total_words || 0)}
          trend={`Mastery: ${Math.round(vocab?.avg_mastery_rate || 0)}%`}
          variant="dark"
          accent="ink"
        />
      </div>

      {/* Course Performance */}
      <div className="panel">
        <h3 className="panel-heading">Hiệu suất Khóa học</h3>
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
                render: (row) => (
                  <span className="table-meta" style={{ fontWeight: 600, fontVariantNumeric: "tabular-nums" }}>
                    {row.enrollments.toLocaleString()}
                  </span>
                ),
                align: "center",
              },
              {
                header: "Hoàn thành",
                render: (row) => (
                  <span className="table-meta" style={{ fontWeight: 600, fontVariantNumeric: "tabular-nums" }}>
                    {row.completions.toLocaleString()}
                  </span>
                ),
                align: "center",
              },
              {
                header: "Tỷ lệ",
                render: (row) => (
                  <RateBarCell
                    percent={row.completion_rate}
                    tone={row.completion_rate >= 50 ? "success" : row.completion_rate >= 20 ? "warning" : "danger"}
                    label={`${Math.round(row.completion_rate)}%`}
                  />
                ),
                align: "center",
              },
              {
                header: "Điểm TB",
                render: (row) => (
                  <StatusPill
                    tone={row.avg_score >= 80 ? "success" : row.avg_score >= 50 ? "info" : "warning"}
                    label={`${Math.round(row.avg_score)}`}
                  />
                ),
                align: "center",
              },
              {
                header: "Thời gian TB",
                render: (row) => (
                  <span className="status-pill neutral" style={{ fontVariantNumeric: "tabular-nums" }}>
                    {Math.round(row.avg_time_minutes)} phút
                  </span>
                ),
                align: "center",
              },
            ]}
            rows={perf.courses}
          />
        )}
      </div>

      {/* Lesson Performance */}
      <div className="panel">
        <h3 className="panel-heading">Hiệu suất Bài học</h3>
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
                render: (row) => (
                  <span className="table-meta" style={{ fontWeight: 600, fontVariantNumeric: "tabular-nums" }}>
                    {row.attempts.toLocaleString()}
                  </span>
                ),
                align: "center",
              },
              {
                header: "Hoàn thành",
                render: (row) => {
                  const pct = row.attempts > 0 ? (row.completions / row.attempts) * 100 : 0;
                  return (
                    <RateBarCell
                      percent={pct}
                      tone={pct >= 60 ? "success" : pct >= 30 ? "info" : "warning"}
                      label={row.completions.toLocaleString()}
                    />
                  );
                },
                align: "center",
              },
              {
                header: "Điểm TB",
                render: (row) => (
                  <RateBarCell
                    percent={row.avg_score}
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
        <h3 className="panel-heading">Từ vựng khó nhất</h3>
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
                  <RateBarCell
                    percent={row.mastery_rate}
                    tone={row.mastery_rate >= 50 ? "success" : row.mastery_rate >= 25 ? "warning" : "danger"}
                    label={`${Math.round(row.mastery_rate)}%`}
                  />
                ),
                align: "center",
              },
              {
                header: "Lượt ôn TB",
                render: (row) => (
                  <span className="status-pill neutral" style={{ fontVariantNumeric: "tabular-nums" }}>
                    {Math.round(row.avg_reviews)}
                  </span>
                ),
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
