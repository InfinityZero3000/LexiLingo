import { apiFetch, type ApiResponse } from "./api";

export type NotificationCampaignJobType =
  | "targeted_push"
  | "in_app_broadcast"
  | "scheduled_push";

export const NOTIFICATION_CAMPAIGN_ACTIVE_STATUSES = [
  "queued",
  "segmenting",
  "generating",
  "validating",
  "sending",
] as const;

export type NotificationCampaignJobStatus =
  | (typeof NOTIFICATION_CAMPAIGN_ACTIVE_STATUSES)[number]
  | "preview_ready"
  | "completed"
  | "failed"
  | "cancelled";

export type NotificationCampaignJob = {
  id: string;
  job_type: NotificationCampaignJobType;
  status: NotificationCampaignJobStatus;
  progress: {
    stage: string;
    percent: number;
    counters?: Record<string, number>;
  };
  config: Record<string, unknown>;
  artifact: Record<string, unknown> | null;
  warnings: string[];
  blocking_errors: string[];
  delivery_stats: Record<string, unknown>;
  celery_task_id: string | null;
  error_message: string | null;
  requested_by_id: string | null;
  scheduled_at: string | null;
  created_at: string;
  updated_at: string;
  started_at: string | null;
  completed_at: string | null;
};

// `preview_ready` is intentionally excluded: the job has paused for human review,
// so callers (e.g. Drawer poller) should stop polling once this status is reached.
export function isNotificationCampaignJobActive(
  status: NotificationCampaignJobStatus
): boolean {
  return (NOTIFICATION_CAMPAIGN_ACTIVE_STATUSES as readonly string[]).includes(status);
}

export function canApplyNotificationCampaignJob(job: NotificationCampaignJob): boolean {
  return job.status === "preview_ready" && job.blocking_errors.length === 0;
}

/** True while the job needs user attention — either still running or awaiting apply. */
export function needsAttention(status: NotificationCampaignJobStatus): boolean {
  return isNotificationCampaignJobActive(status) || status === "preview_ready";
}

export const JOB_TYPE_LABELS: Record<NotificationCampaignJobType, string> = {
  targeted_push: "Targeted Push",
  in_app_broadcast: "In-App Broadcast",
  scheduled_push: "Scheduled Push",
};

export const STATUS_LABELS: Record<NotificationCampaignJobStatus, string> = {
  queued: "Queued",
  segmenting: "Segmenting",
  generating: "Generating",
  validating: "Validating",
  sending: "Sending",
  preview_ready: "Preview Ready",
  completed: "Completed",
  failed: "Failed",
  cancelled: "Cancelled",
};

// ---------------------------------------------------------------------------
// API functions
// ---------------------------------------------------------------------------

type ApplyResult = { job: NotificationCampaignJob; result: Record<string, unknown> };

export async function createNotificationCampaignJob(
  payload: Record<string, unknown>
): Promise<NotificationCampaignJob> {
  const res = await apiFetch<ApiResponse<NotificationCampaignJob>>(
    "/api/v1/admin/notification-campaign/jobs",
    { method: "POST", body: JSON.stringify(payload) }
  );
  return res.data as NotificationCampaignJob;
}

export async function listNotificationCampaignJobs(
  limit = 50,
  offset = 0
): Promise<NotificationCampaignJob[]> {
  const res = await apiFetch<ApiResponse<NotificationCampaignJob[]>>(
    `/api/v1/admin/notification-campaign/jobs?limit=${limit}&offset=${offset}`
  );
  return (res.data ?? []) as NotificationCampaignJob[];
}

export async function getNotificationCampaignJob(
  id: string
): Promise<NotificationCampaignJob> {
  const res = await apiFetch<ApiResponse<NotificationCampaignJob>>(
    `/api/v1/admin/notification-campaign/jobs/${id}`
  );
  return res.data as NotificationCampaignJob;
}

export async function applyNotificationCampaignJob(
  id: string
): Promise<NotificationCampaignJob> {
  const res = await apiFetch<ApiResponse<NotificationCampaignJob>>(
    `/api/v1/admin/notification-campaign/jobs/${id}/apply`,
    { method: "POST" }
  );
  return res.data as NotificationCampaignJob;
}

export async function cancelNotificationCampaignJob(
  id: string
): Promise<NotificationCampaignJob> {
  const res = await apiFetch<ApiResponse<NotificationCampaignJob>>(
    `/api/v1/admin/notification-campaign/jobs/${id}/cancel`,
    { method: "POST" }
  );
  return res.data as NotificationCampaignJob;
}

export async function retryNotificationCampaignJob(
  id: string
): Promise<NotificationCampaignJob> {
  const res = await apiFetch<ApiResponse<NotificationCampaignJob>>(
    `/api/v1/admin/notification-campaign/jobs/${id}/retry`,
    { method: "POST" }
  );
  return res.data as NotificationCampaignJob;
}
