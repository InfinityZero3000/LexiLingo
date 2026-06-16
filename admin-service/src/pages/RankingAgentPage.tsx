import React, { useCallback, useEffect, useState } from "react";
import { Award, Plus, RotateCcw, Trophy, Zap } from "lucide-react";

import { RankingAgentDrawer } from "../components/ranking-agent/RankingAgentDrawer";
import { RankingAgentModal } from "../components/ranking-agent/RankingAgentModal";
import { SectionHeader } from "../components/SectionHeader";
import { StatusPill } from "../components/StatusPill";
import {
  isRankingAgentJobActive,
  JOB_TYPE_LABELS,
  listRankingAgentJobs,
  STATUS_LABELS,
  type RankingAgentJob,
  type RankingAgentJobStatus,
} from "../lib/rankingAgentApi";

const JOB_TYPE_ICONS: Record<string, React.ReactNode> = {
  league_reset: <RotateCcw className="w-4 h-4" />,
  xp_event: <Zap className="w-4 h-4" />,
  achievement_batch: <Award className="w-4 h-4" />,
};

const STATUS_TONE: Record<RankingAgentJobStatus, "success" | "warning" | "danger" | "info" | "neutral"> = {
  queued: "neutral",
  calculating: "info",
  validating: "info",
  applying: "warning",
  preview_ready: "warning",
  completed: "success",
  failed: "danger",
  cancelled: "neutral",
};

function formatDate(iso: string): string {
  return new Date(iso).toLocaleString("vi-VN", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export function RankingAgentPage() {
  const [jobs, setJobs] = useState<RankingAgentJob[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [showModal, setShowModal] = useState(false);
  const [activeJob, setActiveJob] = useState<RankingAgentJob | null>(null);

  const loadJobs = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await listRankingAgentJobs(50, 0);
      setJobs(data);
      // Auto-open drawer if there's an in-progress job
      const inProgress = data.find(
        (j) => isRankingAgentJobActive(j.status) || j.status === "preview_ready"
      );
      if (inProgress && !activeJob) {
        setActiveJob(inProgress);
      }
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Không tải được danh sách jobs");
    } finally {
      setLoading(false);
    }
  }, [activeJob]);

  useEffect(() => {
    void loadJobs();
  }, []);

  const handleJobCreated = useCallback((job: RankingAgentJob) => {
    setJobs((prev) => [job, ...prev]);
    setShowModal(false);
    setActiveJob(job);
  }, []);

  const handleJobUpdated = useCallback((updated: RankingAgentJob) => {
    setJobs((prev) => prev.map((j) => (j.id === updated.id ? updated : j)));
    setActiveJob(updated);
  }, []);

  return (
    <div>
      <SectionHeader
        title="Ranking Agent"
        description="Tự động hóa league reset, XP events và phát thành tích hàng loạt."
        action={
          <button
            className="primary-button"
            onClick={() => setShowModal(true)}
          >
            <Plus className="w-4 h-4 mr-1" />
            Tạo Job mới
          </button>
        }
      />

      {error && (
        <div className="alert alert-error mb-4">{error}</div>
      )}

      {loading && jobs.length === 0 ? (
        <div className="empty-state">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary mx-auto" />
          <p className="mt-2 text-sm text-muted">Đang tải...</p>
        </div>
      ) : jobs.length === 0 ? (
        <div className="empty-state">
          <Trophy className="w-10 h-10 text-muted mb-2 mx-auto" />
          <p className="font-medium">Chưa có jobs nào</p>
          <p className="text-sm text-muted">Tạo job đầu tiên để bắt đầu.</p>
        </div>
      ) : (
        <div className="data-table-wrapper">
          <table className="data-table">
            <thead>
              <tr>
                <th>Loại</th>
                <th>Trạng thái</th>
                <th>Tiến độ</th>
                <th>Cảnh báo</th>
                <th>Tạo lúc</th>
                <th>Hoàn thành</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {jobs.map((job) => (
                <tr
                  key={job.id}
                  className="cursor-pointer hover:bg-muted/10"
                  onClick={() => setActiveJob(job)}
                >
                  <td>
                    <span className="flex items-center gap-1.5">
                      {JOB_TYPE_ICONS[job.job_type]}
                      <span className="font-medium">{JOB_TYPE_LABELS[job.job_type]}</span>
                    </span>
                  </td>
                  <td>
                    <StatusPill tone={STATUS_TONE[job.status]} label={STATUS_LABELS[job.status]} />
                  </td>
                  <td>
                    <span className="text-sm text-muted">{job.progress.percent}%</span>
                  </td>
                  <td>
                    {job.warnings.length > 0 ? (
                      <span className="text-sm text-warning font-medium">
                        {job.warnings.length} cảnh báo
                      </span>
                    ) : job.blocking_errors.length > 0 ? (
                      <span className="text-sm text-error font-medium">
                        {job.blocking_errors.length} lỗi
                      </span>
                    ) : (
                      <span className="text-sm text-muted">—</span>
                    )}
                  </td>
                  <td className="text-sm text-muted">{formatDate(job.created_at)}</td>
                  <td className="text-sm text-muted">
                    {job.completed_at ? formatDate(job.completed_at) : "—"}
                  </td>
                  <td>
                    <button
                      className="ghost-button text-sm"
                      onClick={(e) => {
                        e.stopPropagation();
                        setActiveJob(job);
                      }}
                    >
                      Xem
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {showModal && (
        <RankingAgentModal
          onClose={() => setShowModal(false)}
          onJobCreated={handleJobCreated}
        />
      )}

      {activeJob && (
        <RankingAgentDrawer
          job={activeJob}
          onClose={() => setActiveJob(null)}
          onJobUpdated={handleJobUpdated}
        />
      )}
    </div>
  );
}
