import React, { useCallback, useEffect, useRef, useState } from "react";
import {
  AlertTriangle,
  Bell,
  Check,
  CheckCircle,
  ChevronDown,
  ChevronUp,
  Clock,
  Radio,
  RotateCcw,
  Sparkles,
  Users,
  X,
  XCircle,
} from "lucide-react";

import {
  applyNotificationCampaignJob,
  cancelNotificationCampaignJob,
  canApplyNotificationCampaignJob,
  getNotificationCampaignJob,
  isNotificationCampaignJobActive,
  JOB_TYPE_LABELS,
  retryNotificationCampaignJob,
  STATUS_LABELS,
  type NotificationCampaignJob,
} from "../../lib/notificationCampaignApi";

const POLL_MS = 2500;

type Props = {
  job: NotificationCampaignJob;
  onClose: () => void;
  onJobUpdated: (job: NotificationCampaignJob) => void;
};

export function NotificationCampaignDrawer({ job: initialJob, onClose, onJobUpdated }: Props) {
  const [job, setJob] = useState<NotificationCampaignJob>(initialJob);
  const [applying, setApplying] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [previewExpanded, setPreviewExpanded] = useState(true);
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const updateJob = useCallback(
    (updated: NotificationCampaignJob) => {
      setJob(updated);
      onJobUpdated(updated);
    },
    [onJobUpdated]
  );

  useEffect(() => {
    if (!isNotificationCampaignJobActive(job.status)) return;
    pollRef.current = setInterval(async () => {
      try {
        const updated = await getNotificationCampaignJob(job.id);
        updateJob(updated);
        if (!isNotificationCampaignJobActive(updated.status)) {
          clearInterval(pollRef.current!);
        }
      } catch {
        // ignore transient
      }
    }, POLL_MS);
    return () => clearInterval(pollRef.current!);
  }, [job.id, job.status, updateJob]);

  async function handleApply() {
    setActionError(null);
    setApplying(true);
    try {
      const updated = await applyNotificationCampaignJob(job.id);
      updateJob(updated);
    } catch (err) {
      setActionError(err instanceof Error ? err.message : "Apply failed.");
    } finally {
      setApplying(false);
    }
  }

  async function handleCancel() {
    setActionError(null);
    try {
      updateJob(await cancelNotificationCampaignJob(job.id));
    } catch (err) {
      setActionError(err instanceof Error ? err.message : "Cancel failed.");
    }
  }

  async function handleRetry() {
    setActionError(null);
    try {
      updateJob(await retryNotificationCampaignJob(job.id));
    } catch (err) {
      setActionError(err instanceof Error ? err.message : "Retry failed.");
    }
  }

  const statusTone: Record<string, string> = {
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

  const content = (job.config as Record<string, Record<string, unknown>>)?.content ?? {};

  return (
    <aside className="notification-drawer" aria-label="Notification campaign details">
      <div className="notification-drawer-header">
        <div className="notification-drawer-heading">
          <Radio size={20} aria-hidden="true" />
          <div>
            <div className="notification-drawer-title">
              <span>
                {JOB_TYPE_LABELS[job.job_type]}
              </span>
              <Bell size={16} aria-hidden="true" />
            </div>
            <span className="notification-drawer-id">{job.id.slice(0, 8)}…</span>
          </div>
        </div>
        <div className="notification-drawer-header-actions">
          <span
            className={`status-pill ${statusTone[job.status] ?? "neutral"}`}
          >
            {STATUS_LABELS[job.status] ?? job.status}
          </span>
          <button type="button" onClick={onClose} className="icon-button" aria-label="Close campaign details">
            <X size={18} aria-hidden="true" />
          </button>
        </div>
      </div>

      {isNotificationCampaignJobActive(job.status) && (
        <div className="notification-progress-block">
          <div className="notification-progress-meta">
            <span>{job.progress.stage}</span>
            <span>{job.progress.percent ?? 0}%</span>
          </div>
          <div className="notification-progress-track" role="progressbar" aria-valuenow={job.progress.percent ?? 0} aria-valuemin={0} aria-valuemax={100}>
            <div
              className="notification-progress-fill"
              style={{ width: `${job.progress.percent ?? 0}%` }}
            />
          </div>
        </div>
      )}

      <div className="notification-drawer-body">
        {(job.status === "segmenting" || job.status === "generating" || job.status === "validating") && (
          <div className="notification-job-loading">
            <Clock size={32} className="is-spinning" aria-hidden="true" />
            <p>{job.status}…</p>
          </div>
        )}

        {job.blocking_errors.length > 0 && (
          <div className="notification-callout danger">
            <p className="notification-callout-title">
              <XCircle size={15} aria-hidden="true" /> Blocking errors
            </p>
            {job.blocking_errors.map((e, i) => (
              <p key={i}>{e}</p>
            ))}
          </div>
        )}

        {job.warnings.length > 0 && (
          <div className="notification-callout warning">
            <p className="notification-callout-title">
              <AlertTriangle size={15} aria-hidden="true" /> Warnings
            </p>
            {job.warnings.map((w, i) => (
              <p key={i}>{w}</p>
            ))}
          </div>
        )}

        {job.artifact && job.status === "preview_ready" && (
          <div className="notification-preview-section">
            <button
              type="button"
              onClick={() => setPreviewExpanded((v) => !v)}
              className="notification-preview-toggle"
              aria-expanded={previewExpanded}
            >
              <span>Preview</span>
              {previewExpanded ? (
                <ChevronUp size={16} aria-hidden="true" />
              ) : (
                <ChevronDown size={16} aria-hidden="true" />
              )}
            </button>
            {previewExpanded && (
              <div className="notification-preview-body">
                <PreviewSummary job={job} />
              </div>
            )}
          </div>
        )}

        {job.status === "completed" && (
          <div className="notification-job-complete">
            <CheckCircle size={40} aria-hidden="true" />
            <p>Campaign sent successfully</p>
            <DeliveryStats stats={job.delivery_stats} />
          </div>
        )}

        {job.status === "failed" && (
          <div className="notification-callout danger">
            <p className="notification-callout-title">Job failed</p>
            {job.error_message && (
              <p>{job.error_message}</p>
            )}
          </div>
        )}

        {actionError && (
          <p className="form-error">{actionError}</p>
        )}
      </div>

      <div className="notification-drawer-footer">
        <div className="notification-drawer-actions">
          {isNotificationCampaignJobActive(job.status) && job.status !== "sending" && (
            <button
              type="button"
              onClick={handleCancel}
              className="ghost-button small danger"
            >
              Cancel
            </button>
          )}
          {job.status === "failed" && (
            <button
              type="button"
              onClick={handleRetry}
              className="ghost-button small notification-action-button"
            >
              <RotateCcw size={15} aria-hidden="true" /> Retry
            </button>
          )}
        </div>
        {canApplyNotificationCampaignJob(job) && (
          <button
            type="button"
            onClick={handleApply}
            disabled={applying}
            className="primary-button"
          >
            {applying ? "Sending…" : "Send Campaign"}
          </button>
        )}
      </div>
    </aside>
  );
}

function PreviewSummary({ job }: { job: NotificationCampaignJob }) {
  const art = job.artifact!;
  const contentPreview = art.content_preview as Record<string, unknown> | undefined;
  const aiCopy = art.ai_copy as Record<string, unknown> | undefined;
  const sampleUsers = (art.sample_users as Array<Record<string, unknown>>) ?? [];

  return (
    <div className="notification-preview-summary">
      <div className="notification-stat-grid two-columns">
        <Stat label="Audience size" value={String(art.audience_size ?? 0)} />
        <Stat
          label="FCM eligible"
          value={String(art.fcm_eligible ?? 0)}
          tone={Number(art.fcm_eligible ?? 0) > 0 ? "success" : "danger"}
        />
      </div>

      {contentPreview && (
        <div className="notification-content-preview">
          {!!aiCopy && (
            <p className="notification-content-label">
              <Sparkles size={15} aria-hidden="true" /> AI-generated copy
            </p>
          )}
          <p className="notification-content-title">
            {String(contentPreview.title ?? "")}
          </p>
          <p className="notification-content-body">{String(contentPreview.body ?? "")}</p>
        </div>
      )}

      {sampleUsers.length > 0 && (
        <div className="notification-sample-users">
          <p className="notification-sample-heading">
            <Users size={15} aria-hidden="true" /> Sample users ({sampleUsers.length})
          </p>
          <div className="notification-sample-list">
            {sampleUsers.map((u, i) => (
              <div key={i} className="notification-sample-row">
                <span className="mono">{String(u.username ?? "")}</span>
                <span className="notification-sample-meta">
                  {String(u.cefr_level ?? "")} · {u.has_fcm ? <><Check size={13} aria-hidden="true" /> FCM</> : "no FCM"}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}

      {!!art.scheduled_for && (
        <p className="notification-scheduled">
          Scheduled: {new Date(String(art.scheduled_for)).toLocaleString()}
        </p>
      )}
    </div>
  );
}

function Stat({
  label,
  value,
  tone = "default",
}: {
  label: string;
  value: string;
  tone?: "default" | "success" | "danger" | "muted";
}) {
  return (
    <div className="notification-stat">
      <p>{label}</p>
      <strong className={`notification-stat-value ${tone}`}>{value}</strong>
    </div>
  );
}

function DeliveryStats({ stats }: { stats: Record<string, unknown> }) {
  if (!Object.keys(stats).length) return null;
  return (
    <div className="notification-stat-grid three-columns">
      <Stat label="Sent" value={String(stats.sent ?? 0)} tone="success" />
      <Stat label="Failed" value={String(stats.failed ?? 0)} tone="danger" />
      <Stat label="Skipped" value={String(stats.skipped ?? 0)} tone="muted" />
    </div>
  );
}
