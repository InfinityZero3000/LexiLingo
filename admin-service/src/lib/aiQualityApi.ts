import { apiFetch } from "./api";
import { ENV } from "./env";

export type AiQualityEndpointBreakdown = {
  endpoint: string;
  total: number;
  failures: number;
  average_latency_ms: number;
};

export type AiQualityFailure = {
  request_id?: string | null;
  user_id?: string | null;
  endpoint?: string | null;
  status?: string | null;
  latency_ms?: number | null;
  received_at?: string | null;
  error?: string | null;
};

export type AiQualitySummary = {
  total_events: number;
  success_count: number;
  failure_count: number;
  success_rate: number;
  average_latency_ms: number;
  p95_latency_ms: number;
  lexi: {
    events: number;
    failures: number;
    average_latency_ms: number;
  };
  stt: {
    failures: number;
  };
  tts: {
    failures: number;
  };
  correction: {
    events: number;
    failures: number;
    average_score: number;
  };
  endpoint_breakdown: AiQualityEndpointBreakdown[];
  latest_failures: AiQualityFailure[];
};

export type AiQualityResponse = {
  events: unknown[];
  summary: AiQualitySummary;
  total: number;
  source: string;
};

export const getAiQualitySummary = (limit = 500) =>
  apiFetch<AiQualityResponse>(
    `${ENV.backendUrl}/ai-audit/quality-summary?limit=${encodeURIComponent(limit)}`,
  );
