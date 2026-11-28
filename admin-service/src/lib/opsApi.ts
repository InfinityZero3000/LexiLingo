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

/* ─── Schema drift ─── */

export type SchemaDriftIssue = {
  kind: "missing_table" | "missing_column" | "missing_unique" | "missing_enum" | "missing_enum_label";
  table: string | null;
  detail: string;
};

export type SchemaDrift = { ok: boolean; checked_at: string; issue_count: number; issues: SchemaDriftIssue[] };

export const getSchemaDrift = () => apiFetch<SchemaDrift>(`${ENV.backendUrl}/admin/ops/schema-drift`);

/* ─── Error monitoring ─── */

export type ErrorState = "open" | "resolved" | "muted";
export type ErrorKind = "error" | "client";

export type ErrorGroup = {
  fingerprint: string;
  service: string;
  kind: ErrorKind;
  method: string;
  route: string;
  status_code: number | null;
  error_type: string | null;
  location: string | null;
  sample_message: string | null;
  sample_request_id: string | null;
  first_seen: string;
  last_seen: string;
  total_count: number;
  count_window: number;
  state: ErrorState;
  regressed: boolean;
};

export type ErrorGroupsResult = {
  groups: ErrorGroup[];
  totals: { errors: number; groups: number; by_service: Record<string, number> };
};

export type ErrorGroupParams = { hours: number; service?: string; state?: ErrorState | "all"; kind?: ErrorKind };

export const getErrorGroups = async (params: ErrorGroupParams) => {
  const query = new URLSearchParams({ hours: String(params.hours), state: params.state ?? "open" });
  if (params.service) query.set("service", params.service);
  if (params.kind) query.set("kind", params.kind);
  const res = await apiFetch<Envelope<ErrorGroupsResult>>(`${ENV.backendUrl}/admin/ops/errors?${query}`);
  return res.data;
};

export const setErrorGroupState = async (fingerprint: string, state: ErrorState) => {
  const res = await apiFetch<Envelope<ErrorGroup>>(`${ENV.backendUrl}/admin/ops/errors/${encodeURIComponent(fingerprint)}`, {
    method: "PATCH",
    body: JSON.stringify({ state }),
  });
  return res.data;
};

export type ErrorReportSettings = {
  enabled: boolean;
  recipients: string[];
  digest_interval_minutes: number;
  spike_threshold: number;
  client_spike_threshold: number;
  cooldown_minutes: number;
  last_digest_at: string | null;
};

export type ErrorReportSettingsPatch = Partial<Omit<ErrorReportSettings, "last_digest_at">>;

export const DIGEST_INTERVALS = [15, 30, 60, 180, 360, 720, 1440];

export const getErrorReportSettings = async () => {
  const res = await apiFetch<Envelope<ErrorReportSettings>>(`${ENV.backendUrl}/admin/ops/error-report/settings`);
  return res.data;
};

export const updateErrorReportSettings = async (patch: ErrorReportSettingsPatch) => {
  const res = await apiFetch<Envelope<ErrorReportSettings>>(`${ENV.backendUrl}/admin/ops/error-report/settings`, {
    method: "PUT",
    body: JSON.stringify(patch),
  });
  return res.data;
};

export const sendTestErrorReport = async () => {
  const res = await apiFetch<Envelope<{ sent_to: string[]; groups: number }>>(
    `${ENV.backendUrl}/admin/ops/error-report/test`,
    { method: "POST" },
  );
  return res.data;
};
