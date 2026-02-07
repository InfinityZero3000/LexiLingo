import { apiFetch } from "./api";
import { ENV } from "./env";

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
