// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { I18nProvider } from "../lib/i18n";
import { AiMonitoringPage } from "./AiMonitoringPage";

const api = vi.hoisted(() => ({ getChatMonitoring: vi.fn(), getLlmKeyMonitoring: vi.fn(), getSpoolMonitoring: vi.fn() }));
vi.mock("../lib/aiApi", () => api);
vi.mock("recharts", () => {
  const Stub = () => null;
  return { AreaChart: Stub, Area: Stub, BarChart: Stub, Bar: Stub, XAxis: Stub, YAxis: Stub, CartesianGrid: Stub, Tooltip: Stub, ResponsiveContainer: Stub };
});

const pair = (p50: number | null, p95: number | null) => ({ p50, p95 });
const block = (p50: number | null, p95: number | null) => ({ latency_ms: pair(p50, p95), ttft_ms: pair(300, 900), first_chunk_ms: pair(null, null) });

const chat = (over = {}) => ({
  window: "24h",
  generated_at: "2026-11-24T12:00:00Z",
  turns: 120,
  topic_turns: 10,
  errors: 6,
  error_rate: 0.05,
  latency: { all: block(800, 2400), hit: block(20, 40), miss: block(1500, 2600) },
  tokens: {
    prompt_sum: 90000, completion_sum: 30000, cached_sum: 40000,
    prompt_avg: 900, completion_avg: 300, cached_avg: 400, per_turn: 1200, reported_turns: 100, partial_turns: 8,
    usage_source: { provider: { turns: 80, share: 0.6667 }, partial: { turns: 8, share: 0.0667 }, none: { turns: 20, share: 0.1667 }, not_recorded: { turns: 12, share: 0.1 } },
  },
  cache: {
    hit_rate: 0.25,
    layers: { L0: { turns: 20, share: 0.1667 }, L1: { turns: 10, share: 0.0833 }, none: { turns: 90, share: 0.75 } },
    bypass: { facts: { turns: 12, share: 0.1 } },
    l1_shadow: { compared: 50, low_similarity: 5, low_similarity_rate: 0.1, f1_distribution: [{ from: 0, count: 5 }] },
  },
  learner_state: { degraded: 3, degraded_rate: 0.025 },
  models: [{ model: "qwen/qwen3.8-27b", turns: 100 }],
  series: [{ ts: "2026-11-24T10:00:00Z", turns: 60, p95_latency_ms: 2000, tokens: 70000 }],
  ...over,
});

const spool = {
  queue_depth: 7, by_status: { pending: 7 }, dead: 2, delivered: 400,
  receiver_off_since_start: 4, dead_since_start: 1, worker_loop_errors_since_start: 0,
};

const keys = {
  mode: "pool",
  model: "qwen/qwen3.8-27b",
  keys: [
    { index: 0, state: "available", rpm: 1, rpm_limit: 30, tpm: 100, tpm_limit: 6000, rpd: 10, rpd_limit: 14400 },
    { index: 1, state: "exhausted", rpm: 0, rpm_limit: 30, tpm: 0, tpm_limit: 6000, rpd: 13000, rpd_limit: 14400 },
  ],
  totals: { keys: 2, available: 1, busy: 0, cooling: 0, exhausted: 1 },
};

const mount = () => {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <I18nProvider>
        <AiMonitoringPage />
      </I18nProvider>
    </QueryClientProvider>,
  );
};

beforeEach(() => {
  const store = new Map<string, string>([["lexi_admin_locale", "en"]]);
  vi.stubGlobal("localStorage", {
    getItem: (k: string) => store.get(k) ?? null,
    setItem: (k: string, v: string) => void store.set(k, v),
    removeItem: (k: string) => void store.delete(k),
  });
  api.getChatMonitoring.mockResolvedValue(chat());
  api.getLlmKeyMonitoring.mockResolvedValue(keys);
  api.getSpoolMonitoring.mockResolvedValue(spool);
});
afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

describe("AiMonitoringPage", () => {
  it("shows a loading skeleton before the first response", () => {
    api.getChatMonitoring.mockReturnValue(new Promise(() => {}));
    mount();
    expect(document.querySelector('[aria-busy="true"]')).toBeTruthy();
    expect(screen.queryByText("Cache hit rate")).toBeNull();
  });

  it("renders KPIs, cache, key pool and the spool from a populated response", async () => {
    mount();
    expect(await screen.findByText("Cache hit rate")).toBeTruthy();
    expect(screen.getByText("120")).toBeTruthy();
    expect(screen.getByText("5.0%")).toBeTruthy();
    expect(screen.getByText("25.0%")).toBeTruthy();
    expect(screen.getByText("2,400 ms")).toBeTruthy();
    expect(screen.getByText("Learner facts")).toBeTruthy();
    expect(await screen.findByText("Key 1")).toBeTruthy();
    expect(screen.getByText("Exhausted")).toBeTruthy();
    expect(screen.getByText("Learner observation queue")).toBeTruthy();
    expect(screen.getAllByText("400").length).toBeGreaterThan(0);
  });

  it("says so when the window has no turns, and still shows the key pool", async () => {
    api.getChatMonitoring.mockResolvedValue(chat({ turns: 0 }));
    mount();
    expect(await screen.findByText("No chat turns in this window")).toBeTruthy();
    expect(await screen.findByText("Key 0")).toBeTruthy();
    expect(await screen.findByText("Learner observation queue")).toBeTruthy();
  });

  it("offers a retry when the chat request fails", async () => {
    api.getChatMonitoring.mockRejectedValueOnce(new Error("boom"));
    mount();
    expect(await screen.findByText("Failed to load AI monitoring data")).toBeTruthy();
    expect(screen.getByText("boom")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Try again" }));
    expect(await screen.findByText("Cache hit rate")).toBeTruthy();
    expect(api.getChatMonitoring).toHaveBeenCalledTimes(2);
  });

  it("labels partial usage as understating and unrecorded rows as not recorded", async () => {
    mount();
    expect(await screen.findByText("Partial (understates)")).toBeTruthy();
    expect(screen.getByText("Not recorded")).toBeTruthy();
    expect(screen.getByText("100 turns measured, 8 partial (a floor)")).toBeTruthy();
    expect(screen.getAllByText("Excludes 10 topic-chat turns").length).toBeGreaterThan(0);
  });

  it("still shows the queue when the chat metrics fail", async () => {
    api.getChatMonitoring.mockRejectedValue(new Error("boom"));
    mount();
    expect(await screen.findByText("Failed to load AI monitoring data")).toBeTruthy();
    expect(await screen.findByText("Learner observation queue")).toBeTruthy();
    expect(await screen.findByText("Receiver off")).toBeTruthy();
  });

  it("shows a queue error with its own retry", async () => {
    api.getSpoolMonitoring.mockRejectedValue(new Error("no"));
    mount();
    expect(await screen.findByText("Failed to load queue state")).toBeTruthy();
    expect(await screen.findByText("Cache hit rate")).toBeTruthy();
  });

  it("keeps the page up when only the key pool fails", async () => {
    api.getLlmKeyMonitoring.mockRejectedValue(new Error("nope"));
    mount();
    expect(await screen.findByText("Cache hit rate")).toBeTruthy();
    expect(await screen.findByText("Failed to load key pool state")).toBeTruthy();
  });

  it("refetches for the chosen window", async () => {
    mount();
    await screen.findByText("Cache hit rate");
    fireEvent.click(screen.getByRole("button", { name: "7 days" }));
    await waitFor(() => expect(api.getChatMonitoring).toHaveBeenLastCalledWith("7d"));
  });
});
