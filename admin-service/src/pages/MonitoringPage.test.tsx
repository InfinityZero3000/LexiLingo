// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { I18nProvider } from "../lib/i18n";
import { MonitoringPage } from "./MonitoringPage";

const api = vi.hoisted(() => ({
  getSystemMetrics: vi.fn(),
  getServicesHealth: vi.fn(),
  getDbStats: vi.fn(),
  getRequestStats: vi.fn(),
  getMonitoringDashboard: vi.fn(),
}));
vi.mock("../lib/aiApi", () => api);
vi.mock("recharts", () => {
  const Stub = () => null;
  return {
    AreaChart: Stub, Area: Stub, XAxis: Stub, YAxis: Stub, CartesianGrid: Stub, Tooltip: Stub,
    ResponsiveContainer: Stub, RadialBarChart: Stub, RadialBar: Stub, BarChart: Stub, Bar: Stub,
    Legend: Stub, PolarAngleAxis: Stub,
  };
});

const system = {
  cpu_percent: 42,
  memory: { percent: 70, used_mb: 2048, total_mb: 4096 },
  disk: { percent: 90, used_gb: 90, total_gb: 100 },
  load_avg: { "1m": 0.5, "5m": 0.4, "15m": 0.3 },
  network: { bytes_sent_mb: 1024, bytes_recv_mb: 2048, packets_sent: 10, packets_recv: 20 },
  disk_io: { read_mb: 5, write_mb: 7 },
};

const mount = () =>
  render(
    <I18nProvider>
      <MonitoringPage />
    </I18nProvider>,
  );

beforeEach(() => {
  const store = new Map<string, string>([["lexi_admin_locale", "en"]]);
  vi.stubGlobal("localStorage", {
    getItem: (k: string) => store.get(k) ?? null,
    setItem: (k: string, v: string) => void store.set(k, v),
    removeItem: (k: string) => void store.delete(k),
  });
  api.getSystemMetrics.mockResolvedValue(system);
  api.getServicesHealth.mockResolvedValue({ postgres: "healthy", redis: "unreachable", ai_service: "weird" });
  api.getDbStats.mockResolvedValue({ counts: { users: 3 } });
  api.getRequestStats.mockResolvedValue({ active_connections: 4, requests_last_minute: 9 });
  api.getMonitoringDashboard.mockResolvedValue(null);
});
afterEach(() => {
  cleanup();
  vi.useRealTimers();
  vi.clearAllMocks();
});

describe("MonitoringPage", () => {
  it("labels each service with a translated status, not the raw API string", async () => {
    mount();
    expect(await screen.findByText("Healthy")).toBeTruthy();
    expect(screen.getByText("Unreachable")).toBeTruthy();
    expect(screen.getAllByText("Unknown").length).toBeGreaterThan(0);
    expect(screen.queryByText("weird")).toBeNull();
  });

  it("exposes usage bars as meters with their value", async () => {
    mount();
    await screen.findByText("Healthy");
    const disk = screen.getAllByRole("meter", { name: "Disk" })[0];
    expect(disk.getAttribute("aria-valuenow")).toBe("90");
    expect(disk.getAttribute("aria-valuemax")).toBe("100");
    expect(screen.getByText("9 req/min")).toBeTruthy();
  });

  it("stops polling while paused and resumes afterwards", async () => {
    vi.useFakeTimers();
    mount();
    await act(async () => {});
    const calls = () => api.getSystemMetrics.mock.calls.length;
    expect(calls()).toBe(1);

    await act(async () => { vi.advanceTimersByTime(30_000); });
    expect(calls()).toBe(2);

    fireEvent.click(screen.getByRole("button", { name: "Pause auto-refresh" }));
    await act(async () => { vi.advanceTimersByTime(90_000); });
    expect(calls()).toBe(2);

    fireEvent.click(screen.getByRole("button", { name: "Resume auto-refresh" }));
    await act(async () => { vi.advanceTimersByTime(30_000); });
    expect(calls()).toBe(3);
  });
});
