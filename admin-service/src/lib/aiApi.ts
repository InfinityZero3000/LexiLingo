import { apiFetch } from "./api";
import { ENV } from "./env";

// ─── AI Service monitoring ────────────────────────────────────────────────────

export type MonitoringDashboard = {
  telemetry?: any;
  system?: {
    cpu_percent?: number;
    memory_percent?: number;
    disk_percent?: number;
    load_avg?: number[];
    cpu?: { percent?: number };
    memory?: { percent?: number };
    disk?: { percent?: number };
  };
  health?: {
    healthy?: boolean;
    warnings?: Array<{ type: string; message: string; severity: string; value: number }>;
    critical_count?: number;
    warning_count?: number;
  };
  process?: {
    memory_percent?: number;
    num_threads?: number;
  };
};

export const getMonitoringDashboard = async () => {
  return apiFetch<MonitoringDashboard>(`${ENV.aiAdminUrl}/monitoring/dashboard`);
};

// ─── Lexi chat + LLM key pool (admin proxy: the ai-service admin key stays server-side) ───

export type AiWindow = "1h" | "24h" | "7d";
export type Percentiles = { p50: number | null; p95: number | null };
export type LatencyBlock = { latency_ms: Percentiles; ttft_ms: Percentiles; first_chunk_ms: Percentiles };
export type ShareRow = { turns: number; share: number | null };

export type ChatMonitoring = {
  window: AiWindow;
  generated_at: string;
  turns: number;
  topic_turns: number;
  errors: number;
  error_rate: number | null;
  latency: { all: LatencyBlock; hit: LatencyBlock; miss: LatencyBlock };
  tokens: {
    prompt_sum: number;
    completion_sum: number;
    cached_sum: number;
    prompt_avg: number | null;
    completion_avg: number | null;
    cached_avg: number | null;
    per_turn: number | null;
    reported_turns: number;
    partial_turns: number;
    usage_source: Record<string, ShareRow>;
  };
  cache: {
    hit_rate: number | null;
    layers: Record<string, ShareRow>;
    bypass: Record<string, ShareRow>;
    l1_shadow: {
      compared: number | null;
      low_similarity: number | null;
      low_similarity_rate: number | null;
      f1_distribution: Array<{ from: number; count: number }>;
    };
  };
  learner_state: { degraded: number; degraded_rate: number | null };
  models: Array<{ model: string; turns: number }>;
  series: Array<{ ts: string; turns: number; p95_latency_ms: number | null; tokens: number }>;
};

export type SpoolMonitoring = {
  queue_depth: number;
  by_status: Record<string, number>;
  dead: number;
  delivered: number;
  receiver_off_since_start: number;
  dead_since_start: number;
  worker_loop_errors_since_start: number;
};

export type LlmKeyState = "available" | "busy" | "cooling" | "exhausted";
export type LlmKeyRow = {
  index: number;
  state: LlmKeyState;
  rpm: number;
  rpm_limit: number;
  tpm: number;
  tpm_limit: number;
  rpd: number;
  rpd_limit: number;
  voice_rpm: number;
};
export type LlmKeyMonitoring = {
  mode: "pool" | "unpooled";
  model: string;
  keys: LlmKeyRow[];
  totals: { keys: number } & Record<LlmKeyState, number>;
};

export const getChatMonitoring = (window: AiWindow) =>
  apiFetch<ChatMonitoring>(`${ENV.aiAdminUrl}/monitoring/chat?window=${window}`);

export const getSpoolMonitoring = () =>
  apiFetch<SpoolMonitoring>(`${ENV.aiAdminUrl}/monitoring/observation-spool`);

export const getLlmKeyMonitoring = () =>
  apiFetch<LlmKeyMonitoring>(`${ENV.aiAdminUrl}/monitoring/llm-keys`);

// ─── Backend monitoring ───────────────────────────────────────────────────────

export type SystemMetrics = {
  cpu_percent: number;
  memory: {
    total_mb: number;
    used_mb: number;
    available_mb: number;
    percent: number;
  };
  disk: {
    total_gb: number;
    used_gb: number;
    free_gb: number;
    percent: number;
  };
  load_avg: { "1m": number; "5m": number; "15m": number };
  network: {
    bytes_sent_mb: number;
    bytes_recv_mb: number;
    packets_sent: number;
    packets_recv: number;
  };
  disk_io: { read_mb: number; write_mb: number };
  timestamp: string;
};

export type ServicesHealth = {
  postgres: "healthy" | "unhealthy" | "unknown";
  redis: "healthy" | "unhealthy" | "not_configured" | "unknown";
  ai_service: "healthy" | "unhealthy" | "unreachable" | "unknown";
  timestamp: string;
};

export type DbStats = {
  counts: { users: number | null; courses: number | null; lessons: number | null; vocabulary_items: number | null };
  timestamp: string;
};

export type RequestStats = {
  active_connections: number;
  redis_available: boolean;
  requests_last_minute?: number;
  timestamp: string;
};

export const getSystemMetrics = () =>
  apiFetch<SystemMetrics>(`${ENV.backendUrl}/admin/monitoring/system`);

export const getServicesHealth = () =>
  apiFetch<ServicesHealth>(`${ENV.backendUrl}/admin/monitoring/services`);

export const getDbStats = () =>
  apiFetch<DbStats>(`${ENV.backendUrl}/admin/monitoring/db-stats`);

export const getRequestStats = () =>
  apiFetch<RequestStats>(`${ENV.backendUrl}/admin/monitoring/request-stats`);

