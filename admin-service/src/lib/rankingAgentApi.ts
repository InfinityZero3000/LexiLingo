import { apiFetch, type ApiResponse } from "./api";

export type RankingAgentJobType =
  | "league_reset"
  | "xp_event"
  | "achievement_batch";

export const RANKING_AGENT_ACTIVE_STATUSES = [
  "queued",
  "calculating",
  "validating",
  "applying",
] as const;

export type RankingAgentJobStatus =
  | (typeof RANKING_AGENT_ACTIVE_STATUSES)[number]
  | "preview_ready"
  | "completed"
  | "failed"
  | "cancelled";

export type RankingAgentJob = {
  id: string;
  job_type: RankingAgentJobType;
  status: RankingAgentJobStatus;
  progress: {
    stage: string;
    percent: number;
    counters?: Record<string, number>;
  };
  config: Record<string, unknown>;
  artifact: Record<string, unknown> | null;
  warnings: string[];
  blocking_errors: string[];
  created_entity_ids: Record<string, unknown>;
  celery_task_id: string | null;
  error_message: string | null;
  requested_by_id: string | null;
  created_at: string;
  updated_at: string;
  started_at: string | null;
  completed_at: string | null;
};

export type LeagueResetConfig = {
  job_type: "league_reset";
  week_start?: string;
};

export type XPEventConfig = {
  job_type: "xp_event";
  name: string;
  multiplier: number;
  duration_hours: number;
  target: string;
};

export type AchievementBatchConfig = {
  job_type: "achievement_batch";
  achievement_slugs: string[];
  criteria: {
    min_streak?: number;
    min_vocabulary_mastered?: number;
    leagues?: string[];
    cefr_levels?: string[];
  };
};

export type RankingAgentJobCreate =
  | { job_type: "league_reset"; config: Omit<LeagueResetConfig, "job_type">; use_ai_insights?: boolean }
  | { job_type: "xp_event"; config: Omit<XPEventConfig, "job_type">; use_ai_insights?: boolean }
  | {
      job_type: "achievement_batch";
      config: Omit<AchievementBatchConfig, "job_type">;
      use_ai_insights?: boolean;
    };

export function isRankingAgentJobActive(status: RankingAgentJobStatus): boolean {
  return (RANKING_AGENT_ACTIVE_STATUSES as readonly string[]).includes(status);
}

export function canApplyRankingAgentJob(job: RankingAgentJob): boolean {
  return job.status === "preview_ready" && job.blocking_errors.length === 0;
}

export const JOB_TYPE_LABELS: Record<RankingAgentJobType, string> = {
  league_reset: "League Reset",
  xp_event: "XP Event",
  achievement_batch: "Achievement Batch",
};

export const STATUS_LABELS: Record<RankingAgentJobStatus, string> = {
  queued: "Queued",
  calculating: "Calculating",
  validating: "Validating",
  applying: "Applying",
  preview_ready: "Preview Ready",
  completed: "Completed",
  failed: "Failed",
  cancelled: "Cancelled",
};

// ---------------------------------------------------------------------------
// API functions
// ---------------------------------------------------------------------------

type PreviewData = { artifact: Record<string, unknown>; warnings: string[]; blocking_errors: string[] };
type ApplyResult = { job: RankingAgentJob; result: Record<string, unknown> };

export async function createRankingAgentJob(
  payload: RankingAgentJobCreate
): Promise<RankingAgentJob> {
  const res = await apiFetch<ApiResponse<RankingAgentJob>>("/api/v1/admin/ranking-agent/jobs", {
    method: "POST",
    body: JSON.stringify(payload),
  });
  return res.data as RankingAgentJob;
}

export async function listRankingAgentJobs(
  limit = 50,
  offset = 0
): Promise<RankingAgentJob[]> {
  const res = await apiFetch<ApiResponse<RankingAgentJob[]>>(
    `/api/v1/admin/ranking-agent/jobs?limit=${limit}&offset=${offset}`
  );
  return (res.data ?? []) as RankingAgentJob[];
}

export async function getRankingAgentJob(id: string): Promise<RankingAgentJob> {
  const res = await apiFetch<ApiResponse<RankingAgentJob>>(`/api/v1/admin/ranking-agent/jobs/${id}`);
  return res.data as RankingAgentJob;
}

export async function getRankingAgentPreview(id: string): Promise<PreviewData> {
  const res = await apiFetch<ApiResponse<PreviewData>>(
    `/api/v1/admin/ranking-agent/jobs/${id}/preview`
  );
  return res.data as PreviewData;
}

export async function applyRankingAgentJob(id: string): Promise<ApplyResult> {
  const res = await apiFetch<ApiResponse<ApplyResult>>(
    `/api/v1/admin/ranking-agent/jobs/${id}/apply`,
    { method: "POST" }
  );
  return res.data as ApplyResult;
}

export async function cancelRankingAgentJob(id: string): Promise<RankingAgentJob> {
  const res = await apiFetch<ApiResponse<RankingAgentJob>>(
    `/api/v1/admin/ranking-agent/jobs/${id}/cancel`,
    { method: "POST" }
  );
  return res.data as RankingAgentJob;
}

export async function retryRankingAgentJob(id: string): Promise<RankingAgentJob> {
  const res = await apiFetch<ApiResponse<RankingAgentJob>>(
    `/api/v1/admin/ranking-agent/jobs/${id}/retry`,
    { method: "POST" }
  );
  return res.data as RankingAgentJob;
}
