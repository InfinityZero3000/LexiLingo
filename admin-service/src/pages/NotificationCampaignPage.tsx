import React, { useCallback, useEffect, useState } from "react";
import { Bell, Calendar, Loader2, MessageSquare, Plus, Radio } from "lucide-react";

import { NotificationCampaignDrawer } from "../components/notification-campaign/NotificationCampaignDrawer";
import { NotificationCampaignModal } from "../components/notification-campaign/NotificationCampaignModal";
import { EmptyState } from "../components/EmptyState";
import { SectionHeader } from "../components/SectionHeader";
import { StatusPill } from "../components/StatusPill";
import {
  JOB_TYPE_LABELS,
  listNotificationCampaignJobs,
  needsAttention,
  STATUS_LABELS,
  type NotificationCampaignJob,
  type NotificationCampaignJobStatus,
} from "../lib/notificationCampaignApi";

const JOB_TYPE_ICONS: Record<string, React.ReactNode> = {
  targeted_push: <Bell size={16} aria-hidden="true" />,
  in_app_broadcast: <MessageSquare size={16} aria-hidden="true" />,
  scheduled_push: <Calendar size={16} aria-hidden="true" />,
};

const STATUS_TONE: Record<
  NotificationCampaignJobStatus,
  "success" | "warning" | "danger" | "info" | "neutral"
> = {
  queued: "neutral",
  segmenting: "info",
  generating: "info",
  validating: "info",
  sending: "warning",
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

export function NotificationCampaignPage() {
  const [jobs, setJobs] = useState<NotificationCampaignJob[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showModal, setShowModal] = useState(false);
  const [activeJob, setActiveJob] = useState<NotificationCampaignJob | null>(null);

  const loadJobs = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await listNotificationCampaignJobs(50, 0);
      setJobs(data);
      // Auto-open the first job that needs attention (active or awaiting apply)
      const inProgress = data.find((j) => needsAttention(j.status));
      if (inProgress) {
        setActiveJob((prev) => prev ?? inProgress);
      }
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Không tải được danh sách jobs");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadJobs();
  }, []);

  const handleJobCreated = useCallback((job: NotificationCampaignJob) => {
    setJobs((prev) => [job, ...prev]);
    setShowModal(false);
    setActiveJob(job);
  }, []);

  const handleJobUpdated = useCallback((updated: NotificationCampaignJob) => {
    setJobs((prev) => prev.map((j) => (j.id === updated.id ? updated : j)));
    setActiveJob(updated);
  }, []);

  return (
    <div>
      <SectionHeader
        title="Notification Campaigns"
        description="Gửi push notification và in-app broadcast đến user segments."
        action={
          <button className="primary-button" onClick={() => setShowModal(true)}>
            <Plus size={16} aria-hidden="true" />
            Tạo Campaign
          </button>
        }
      />

      {error && <div className="form-error" style={{ marginBottom: 16 }}>{error}</div>}

      {loading && jobs.length === 0 ? (
        <EmptyState icon={<Loader2 className="is-spinning" size={32} />} title="Đang tải..." />
      ) : jobs.length === 0 ? (
        <EmptyState
          icon={<Radio size={36} />}
          title="Chưa có campaign nào"
          description="Tạo campaign đầu tiên để bắt đầu."
        />
      ) : (
        <div className="table-container">
          <table className="data-table">
            <thead>
              <tr>
                <th>Loại</th>
                <th>Trạng thái</th>
                <th>Tiến độ</th>
                <th>Audience</th>
                <th>Gửi</th>
                <th>Tạo lúc</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {jobs.map((job) => {
                const art = job.artifact as Record<string, unknown> | null;
                const stats = job.delivery_stats as Record<string, unknown>;
                return (
                  <tr
                    key={job.id}
                    style={{ cursor: "pointer" }}
                    onClick={() => setActiveJob(job)}
                  >
                    <td>
                      <span className="inline-actions">
                        {JOB_TYPE_ICONS[job.job_type]}
                        <span className="table-title">{JOB_TYPE_LABELS[job.job_type]}</span>
                      </span>
                    </td>
                    <td>
                      <StatusPill tone={STATUS_TONE[job.status]} label={STATUS_LABELS[job.status]} />
                    </td>
                    <td>
                      <span className="table-meta">{job.progress.percent}%</span>
                    </td>
                    <td>
                      <span className="table-meta">
                        {art ? `${String(art.audience_size ?? "?")} users` : "—"}
                      </span>
                    </td>
                    <td>
                      {Object.keys(stats).length > 0 ? (
                        <span className="table-title" style={{ color: "var(--accent-2)" }}>
                          {String(stats.sent ?? 0)} sent
                        </span>
                      ) : (
                        <span className="table-meta">—</span>
                      )}
                    </td>
                    <td className="table-meta">{formatDate(job.created_at)}</td>
                    <td>
                      <button
                        className="ghost-button small"
                        onClick={(e) => {
                          e.stopPropagation();
                          setActiveJob(job);
                        }}
                      >
                        Xem
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {showModal && (
        <NotificationCampaignModal
          onClose={() => setShowModal(false)}
          onJobCreated={handleJobCreated}
        />
      )}

      {activeJob && (
        <NotificationCampaignDrawer
          job={activeJob}
          onClose={() => setActiveJob(null)}
          onJobUpdated={handleJobUpdated}
        />
      )}
    </div>
  );
}
