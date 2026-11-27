// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { I18nProvider } from "../lib/i18n";
import { MonitoringPage } from "./MonitoringPage";

const api = vi.hoisted(() => ({
  getServicesHealth: vi.fn(),
  getDbStats: vi.fn(),
  getRequestStats: vi.fn(),
}));
vi.mock("../lib/aiApi", () => api);
vi.mock("recharts", () => {
  const Stub = () => null;
  return {
    AreaChart: Stub, Area: Stub, XAxis: Stub, YAxis: Stub, CartesianGrid: Stub, Tooltip: Stub,
    ResponsiveContainer: Stub, BarChart: Stub, Bar: Stub, Legend: Stub,
  };
});

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
  api.getServicesHealth.mockResolvedValue({ postgres: "healthy", redis: "unreachable", ai_service: "weird" });
  api.getDbStats.mockResolvedValue({ counts: { users: 3 } });
  api.getRequestStats.mockResolvedValue({ active_connections: 4, requests_last_minute: 9 });
});
afterEach(() => {
  cleanup();
  vi.useRealTimers();
  vi.clearAllMocks();
});

describe("MonitoringPage", () => {
  it("labels each service with a translated status, not the raw API string", async () => {
    mount();
    expect((await screen.findAllByText("Healthy")).length).toBeGreaterThan(0);
    expect(screen.getAllByText("Unreachable").length).toBeGreaterThan(0);
    expect(screen.getAllByText("Unknown").length).toBeGreaterThan(0);
    expect(screen.queryByText("weird")).toBeNull();
  });

  it("shows active connections and request rate without host CPU/RAM/Disk metrics", async () => {
    mount();
    await screen.findAllByText("Healthy");
    expect(screen.getByText("4")).toBeTruthy();
    expect(screen.getByText("9 req/min")).toBeTruthy();
    expect(screen.queryByText("CPU")).toBeNull();
  });

  it("stops polling while paused and resumes afterwards", async () => {
    vi.useFakeTimers();
    mount();
    await act(async () => {});
    const calls = () => api.getServicesHealth.mock.calls.length;
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

  it("displays an error alert when all three monitoring endpoints fail", async () => {
    api.getServicesHealth.mockRejectedValueOnce(new Error("down"));
    api.getDbStats.mockRejectedValueOnce(new Error("down"));
    api.getRequestStats.mockRejectedValueOnce(new Error("down"));
    mount();
    expect((await screen.findByRole("alert")).textContent).toContain("Failed to load monitoring data");
  });
});
