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
  };
  health?: {
    healthy?: boolean;
    warnings?: string[];
    critical_count?: number;
    warning_count?: number;
  };
  process?: {
    memory_percent?: number;
    num_threads?: number;
  };
};

export const getMonitoringDashboard = async () => {
  return apiFetch<MonitoringDashboard>(`${ENV.aiUrl}/ai/monitoring/dashboard`);
};

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

