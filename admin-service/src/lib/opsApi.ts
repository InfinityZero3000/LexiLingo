import { apiFetch } from "./api";
import { ENV } from "./env";

type Envelope<T> = { success: boolean; message?: string; data: T };

/* ─── Third-party integrations (probes make real outbound calls) ─── */

export type IntegrationState = "ok" | "dead" | "not_configured" | "unreachable";

export type IntegrationResult = {
  integration: string;
  env_var: string;
  feature: string;
  state: IntegrationState;
  detail: string;
};

export type IntegrationHealth = {
  healthy: boolean;
  checked: number;
  broken: number;
  integrations: IntegrationResult[];
};

export const getIntegrationHealth = () =>
  apiFetch<IntegrationHealth>(`${ENV.backendHealthUrl}/integrations`);

/* ─── External API quotas ─── */

export type QuotaStatus = "normal" | "warning" | "critical" | "blocked";

export type QuotaUsage = {
  api: string;
  used: number;
  budget: number;
  remaining: number;
  usage_percent: number;
  status: QuotaStatus;
  warning_at: number;
  critical_at: number;
  resets_in: string;
};

export const getQuotaUsage = async () => {
  const res = await apiFetch<Envelope<{ apis: QuotaUsage[]; reset_in: string }>>(
    `${ENV.backendUrl}/admin/quota-usage`,
  );
  return res.data;
};

export const resetQuota = (api: string) =>
  apiFetch<Envelope<QuotaUsage>>(`${ENV.backendUrl}/admin/quota-reset/${encodeURIComponent(api)}`, {
    method: "POST",
  });

/* ─── Operator read-outs ─── */

export type ReminderOverview = {
  days: number;
  enabled: boolean;
  dry_run: boolean;
  totals: Record<string, number>;
  by_day: Array<{ date: string } & Record<string, number | string>>;
  by_channel: Array<{ channel: string; status: string; count: number }>;
};

export const getReminderOverview = (days: number) =>
  apiFetch<ReminderOverview>(`${ENV.backendUrl}/admin/ops/reminders?days=${days}`);

export type ProductEventOverview = {
  days: number;
  total: number;
  events: Array<{ event_name: string; count: number; last_at: string | null }>;
  by_day: Array<{ date: string; count: number }>;
};

export const getProductEventOverview = (days: number) =>
  apiFetch<ProductEventOverview>(`${ENV.backendUrl}/admin/ops/product-events?days=${days}`);

export type ContentAgentOverview = {
  by_status: Record<string, number>;
  recent_failures: Array<{ id: string; status: string; error: string; updated_at: string | null }>;
};

export const getContentAgentOverview = () =>
  apiFetch<ContentAgentOverview>(`${ENV.backendUrl}/admin/ops/content-agent`);

/* ─── Background tasks (Celery) ─── */

export type TaskStatus = "ok" | "stale" | "failed" | "never";

export type ScheduledTask = {
  name: string;
  task: string;
  schedule: string;
  status: TaskStatus;
  last_run_at: string | null;
  last_state: string | null;
  runtime: number | null;
  error: string | null;
};

export type CeleryOverview = {
  worker: { reachable: boolean; online: boolean; nodes: string[] };
  beat_alive: boolean;
  queue_depth: number | null;
  reminders_enabled: boolean;
  tasks: ScheduledTask[];
};

export const getCeleryOverview = () => apiFetch<CeleryOverview>(`${ENV.backendUrl}/admin/ops/celery`);

/* ─── Backups ─── */

export type BackupState = "ok" | "stale" | "failed" | "never" | "unavailable";

export type BackupOverview = {
  state: BackupState;
  backup: {
    result: string;
    at: string;
    set?: string;
    postgres_bytes?: number;
    mongo_bytes?: number;
    sets_kept?: number;
    offsite?: boolean;
    error?: string;
    age_seconds: number | null;
  } | null;
  verify: { state: BackupState; result?: string; at?: string; backup?: string; error?: string; age_seconds?: number | null };
  failure_marker_at: string | null;
};

export const getBackupOverview = () => apiFetch<BackupOverview>(`${ENV.backendUrl}/admin/ops/backups`);
