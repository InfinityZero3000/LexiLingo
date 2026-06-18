import React, { useCallback, useEffect, useRef, useState } from "react";
import {
  AlertTriangle,
  Bell,
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

  const statusColor: Record<string, string> = {
    queued: "text-gray-500 bg-gray-100",
    segmenting: "text-blue-600 bg-blue-50",
    generating: "text-purple-600 bg-purple-50",
    validating: "text-indigo-600 bg-indigo-50",
    sending: "text-orange-600 bg-orange-50",
    preview_ready: "text-amber-600 bg-amber-50",
    completed: "text-green-600 bg-green-50",
    failed: "text-red-600 bg-red-50",
    cancelled: "text-gray-500 bg-gray-100",
  };

  const content = (job.config as Record<string, Record<string, unknown>>)?.content ?? {};

  return (
    <div className="fixed inset-y-0 right-0 w-[480px] bg-white shadow-2xl flex flex-col z-40 border-l">
      <div className="flex items-center justify-between px-5 py-4 border-b">
        <div className="flex items-center gap-2">
          <Radio className="w-5 h-5 text-blue-500" />
          <div>
            <div className="flex items-center gap-2">
              <span className="font-semibold text-gray-900 text-sm">
                {JOB_TYPE_LABELS[job.job_type]}
              </span>
              <Bell className="w-4 h-4 text-gray-400" />
            </div>
            <span className="text-xs text-gray-400">{job.id.slice(0, 8)}…</span>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <span
            className={`text-xs font-medium px-2 py-0.5 rounded-full ${statusColor[job.status] ?? "text-gray-500 bg-gray-100"}`}
          >
            {STATUS_LABELS[job.status] ?? job.status}
          </span>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600">
            <X className="w-5 h-5" />
          </button>
        </div>
      </div>

      {isNotificationCampaignJobActive(job.status) && (
        <div className="px-5 pt-3">
          <div className="flex justify-between text-xs text-gray-500 mb-1">
            <span className="capitalize">{job.progress.stage}</span>
            <span>{job.progress.percent ?? 0}%</span>
          </div>
          <div className="h-1.5 bg-gray-100 rounded-full overflow-hidden">
            <div
              className="h-full bg-blue-500 transition-all duration-500"
              style={{ width: `${job.progress.percent ?? 0}%` }}
            />
          </div>
        </div>
      )}

      <div className="flex-1 overflow-y-auto px-5 py-4 space-y-4">
        {(job.status === "segmenting" || job.status === "generating" || job.status === "validating") && (
          <div className="flex flex-col items-center gap-3 py-8 text-gray-400">
            <Clock className="w-8 h-8 animate-spin" />
            <p className="text-sm capitalize">{job.status}…</p>
          </div>
        )}

        {job.blocking_errors.length > 0 && (
          <div className="bg-red-50 border border-red-200 rounded-lg p-3 space-y-1">
            <p className="text-xs font-semibold text-red-700 flex items-center gap-1">
              <XCircle className="w-3.5 h-3.5" /> Blocking errors
            </p>
            {job.blocking_errors.map((e, i) => (
              <p key={i} className="text-xs text-red-600">{e}</p>
            ))}
          </div>
        )}

        {job.warnings.length > 0 && (
          <div className="bg-amber-50 border border-amber-200 rounded-lg p-3 space-y-1">
            <p className="text-xs font-semibold text-amber-700 flex items-center gap-1">
              <AlertTriangle className="w-3.5 h-3.5" /> Warnings
            </p>
            {job.warnings.map((w, i) => (
              <p key={i} className="text-xs text-amber-700">{w}</p>
            ))}
          </div>
        )}

        {job.artifact && job.status === "preview_ready" && (
          <div className="border rounded-lg overflow-hidden">
            <button
              onClick={() => setPreviewExpanded((v) => !v)}
              className="w-full flex items-center justify-between px-4 py-3 bg-gray-50 text-sm font-medium text-gray-700 hover:bg-gray-100"
            >
              <span>Preview</span>
              {previewExpanded ? (
                <ChevronUp className="w-4 h-4" />
              ) : (
                <ChevronDown className="w-4 h-4" />
              )}
            </button>
            {previewExpanded && (
              <div className="px-4 py-3 space-y-3">
                <PreviewSummary job={job} />
              </div>
            )}
          </div>
        )}

        {job.status === "completed" && (
          <div className="flex flex-col items-center gap-3 py-8 text-green-600">
            <CheckCircle className="w-10 h-10" />
            <p className="text-sm font-medium">Campaign sent successfully</p>
            <DeliveryStats stats={job.delivery_stats} />
          </div>
        )}

        {job.status === "failed" && (
          <div className="bg-red-50 border border-red-200 rounded-lg p-4">
            <p className="text-sm font-medium text-red-700">Job failed</p>
            {job.error_message && (
              <p className="text-xs text-red-600 mt-1">{job.error_message}</p>
            )}
          </div>
        )}

        {actionError && (
          <p className="text-sm text-red-600 bg-red-50 rounded-lg px-3 py-2">{actionError}</p>
        )}
      </div>

      <div className="px-5 py-4 border-t flex justify-between gap-3">
        <div className="flex gap-2">
          {isNotificationCampaignJobActive(job.status) && job.status !== "sending" && (
            <button
              onClick={handleCancel}
              className="px-3 py-1.5 text-sm text-red-600 hover:text-red-700 border border-red-200 rounded-lg hover:bg-red-50 transition-colors"
            >
              Cancel
            </button>
          )}
          {job.status === "failed" && (
            <button
              onClick={handleRetry}
              className="px-3 py-1.5 text-sm text-blue-600 border border-blue-200 rounded-lg hover:bg-blue-50 transition-colors flex items-center gap-1"
            >
              <RotateCcw className="w-3.5 h-3.5" /> Retry
            </button>
          )}
        </div>
        {canApplyNotificationCampaignJob(job) && (
          <button
            onClick={handleApply}
            disabled={applying}
            className="px-5 py-2 text-sm bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50 transition-colors font-medium"
          >
            {applying ? "Sending…" : "Send Campaign"}
          </button>
        )}
      </div>
    </div>
  );
}

function PreviewSummary({ job }: { job: NotificationCampaignJob }) {
  const art = job.artifact!;
  const contentPreview = art.content_preview as Record<string, unknown> | undefined;
  const aiCopy = art.ai_copy as Record<string, unknown> | undefined;
  const sampleUsers = (art.sample_users as Array<Record<string, unknown>>) ?? [];

  return (
    <div className="space-y-3 text-sm">
      <div className="grid grid-cols-2 gap-2">
        <Stat label="Audience size" value={String(art.audience_size ?? 0)} />
        <Stat
          label="FCM eligible"
          value={String(art.fcm_eligible ?? 0)}
          color={Number(art.fcm_eligible ?? 0) > 0 ? "text-green-600" : "text-red-500"}
        />
      </div>

      {contentPreview && (
        <div className="bg-blue-50 border border-blue-100 rounded-lg p-3 space-y-1">
          {!!aiCopy && (
            <p className="text-xs font-semibold text-purple-700 flex items-center gap-1 mb-1">
              <Sparkles className="w-3.5 h-3.5" /> AI-generated copy
            </p>
          )}
          <p className="text-xs font-semibold text-gray-700">
            {String(contentPreview.title ?? "")}
          </p>
          <p className="text-xs text-gray-600">{String(contentPreview.body ?? "")}</p>
        </div>
      )}

      {sampleUsers.length > 0 && (
        <div className="space-y-1">
          <p className="text-xs font-medium text-gray-500 flex items-center gap-1">
            <Users className="w-3.5 h-3.5" /> Sample users ({sampleUsers.length})
          </p>
          <div className="divide-y text-xs">
            {sampleUsers.map((u, i) => (
              <div key={i} className="py-1 flex justify-between">
                <span className="font-mono text-gray-600">{String(u.username ?? "")}</span>
                <span className="text-gray-400">
                  {String(u.cefr_level ?? "")} · {u.has_fcm ? "FCM ✓" : "no FCM"}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}

      {!!art.scheduled_for && (
        <p className="text-xs text-gray-400">
          Scheduled: {new Date(String(art.scheduled_for)).toLocaleString()}
        </p>
      )}
    </div>
  );
}

function Stat({
  label,
  value,
  color = "text-gray-900",
}: {
  label: string;
  value: string;
  color?: string;
}) {
  return (
    <div className="bg-gray-50 rounded-lg p-2">
      <p className="text-xs text-gray-500">{label}</p>
      <p className={`text-lg font-bold ${color}`}>{value}</p>
    </div>
  );
}

function DeliveryStats({ stats }: { stats: Record<string, unknown> }) {
  if (!Object.keys(stats).length) return null;
  return (
    <div className="grid grid-cols-3 gap-2 mt-2">
      <Stat label="Sent" value={String(stats.sent ?? 0)} color="text-green-600" />
      <Stat label="Failed" value={String(stats.failed ?? 0)} color="text-red-500" />
      <Stat label="Skipped" value={String(stats.skipped ?? 0)} color="text-gray-500" />
    </div>
  );
}
