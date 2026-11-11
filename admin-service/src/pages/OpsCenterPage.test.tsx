// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { I18nProvider } from "../lib/i18n";
import { ConfirmProvider } from "../components/ConfirmDialog";
import { OpsCenterPage } from "./OpsCenterPage";

const api = vi.hoisted(() => ({
  getIntegrationHealth: vi.fn(),
  getQuotaUsage: vi.fn(),
  resetQuota: vi.fn(),
  getReminderOverview: vi.fn(),
  getProductEventOverview: vi.fn(),
  getContentAgentOverview: vi.fn(),
  getCeleryOverview: vi.fn(),
  getBackupOverview: vi.fn(),
}));
vi.mock("../lib/opsApi", () => ({ ...api }));
const auth = vi.hoisted(() => ({ role: "super_admin" }));
vi.mock("../components/AuthProvider", () => ({ useAuth: () => ({ user: { id: "me" }, role: auth.role }) }));
vi.mock("recharts", () => {
  const Stub = () => null;
  return { BarChart: Stub, Bar: Stub, XAxis: Stub, YAxis: Stub, CartesianGrid: Stub, Tooltip: Stub, Legend: Stub, ResponsiveContainer: Stub };
});

const quota = (over = {}) => ({
  api: "newsapi", used: 90, budget: 100, remaining: 10, usage_percent: 90, status: "critical",
  warning_at: 70, critical_at: 90, resets_in: "3h 10m", ...over,
});

beforeEach(() => {
  const store = new Map<string, string>([["lexi_admin_locale", "en"]]);
  vi.stubGlobal("localStorage", {
    getItem: (k: string) => store.get(k) ?? null,
    setItem: (k: string, v: string) => void store.set(k, v),
    removeItem: (k: string) => void store.delete(k),
  });
  Object.values(api).forEach((fn) => fn.mockReset());
  auth.role = "super_admin";
  api.getQuotaUsage.mockResolvedValue({ apis: [quota()], reset_in: "3h 10m" });
  api.getReminderOverview.mockResolvedValue({
    days: 14, enabled: true, dry_run: true, totals: { sent: 5, failed: 1 }, by_day: [{ date: "2026-11-10", sent: 5, failed: 1 }], by_channel: [],
  });
  api.getProductEventOverview.mockResolvedValue({
    days: 14, total: 12, events: [{ event_name: "lesson_start", count: 12, last_at: "2026-11-10T01:00:00Z" }], by_day: [],
  });
  api.getCeleryOverview.mockResolvedValue({
    worker: { reachable: true, online: true, nodes: ["celery@w1"] }, beat_alive: false, queue_depth: 3, reminders_enabled: false,
    tasks: [
      { name: "prune-refresh-tokens", task: "t1", schedule: "every day", status: "failed", last_run_at: "2026-11-10T02:15:00Z", last_state: "FAILURE", runtime: null, error: "boom" },
      { name: "send-word-of-day", task: "t2", schedule: "every day", status: "never", last_run_at: null, last_state: null, runtime: null, error: null },
    ],
  });
  api.getBackupOverview.mockResolvedValue({
    state: "stale", backup: { result: "ok", at: "2026-11-09T00:00:00Z", postgres_bytes: 2097152, mongo_bytes: 1048576, sets_kept: 12, offsite: false, age_seconds: 90000 },
    verify: { state: "failed", result: "failed", age_seconds: 3600 }, failure_marker_at: "2026-11-09T06:00:00Z",
  });
  api.getContentAgentOverview.mockResolvedValue({ by_status: { completed: 3, failed: 1 }, recent_failures: [{ id: "abcdef123456", status: "failed", error: "quota", updated_at: null }] });
});
afterEach(cleanup);

const mount = () =>
  render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <I18nProvider>
        <ConfirmProvider>
          <OpsCenterPage />
        </ConfirmProvider>
      </I18nProvider>
    </QueryClientProvider>,
  );

describe("OpsCenterPage", () => {
  it("does not probe third-party APIs until asked", async () => {
    mount();
    await waitFor(() => expect(screen.getByText("newsapi")).toBeTruthy());
    expect(api.getIntegrationHealth).not.toHaveBeenCalled();

    api.getIntegrationHealth.mockResolvedValue({
      healthy: false, checked: 2, broken: 1,
      integrations: [
        { integration: "youtube", env_var: "YOUTUBE_API_KEY", feature: "videos", state: "ok", detail: "" },
        { integration: "gemini", env_var: "GEMINI_API_KEY", feature: "content agent", state: "dead", detail: "HTTP 403" },
      ],
    });
    fireEvent.click(screen.getByText("Check now"));

    await waitFor(() => expect(screen.getByText("1 integrations failing")).toBeTruthy());
    expect(screen.getByText("Key rejected")).toBeTruthy();
  });

  it("shows the quota meter and lets only a super admin reset it, after confirmation", async () => {
    api.resetQuota.mockResolvedValue({});
    mount();
    await waitFor(() => expect(screen.getByRole("progressbar", { name: "newsapi" })).toBeTruthy());
    expect(screen.getByText("Critical")).toBeTruthy();

    fireEvent.click(screen.getByRole("button", { name: "Reset" }));
    const dialog = await screen.findByRole("dialog");
    expect(api.resetQuota).not.toHaveBeenCalled();
    fireEvent.click(within(dialog).getByRole("button", { name: "Reset" }));

    await waitFor(() => expect(api.resetQuota).toHaveBeenCalledWith("newsapi"));
  });

  it("hides the reset button from a plain admin", async () => {
    auth.role = "admin";
    mount();
    await waitFor(() => expect(screen.getByText("newsapi")).toBeTruthy());
    expect(screen.queryByRole("button", { name: "Reset" })).toBeNull();
  });

  it("flags a dry-run reminder setup and lists product events and agent errors", async () => {
    mount();
    await waitFor(() => expect(screen.getByText("Dry run (nothing is sent)")).toBeTruthy());
    expect(screen.getByText("lesson_start")).toBeTruthy();
    expect(screen.getByText(/failed: 1/)).toBeTruthy();
    expect(screen.getByText(/abcdef12/)).toBeTruthy();
  });

  it("reports a failed reset instead of failing silently", async () => {
    api.resetQuota.mockRejectedValue(new Error("Redis unavailable"));
    mount();
    await waitFor(() => expect(screen.getByRole("button", { name: "Reset" })).toBeTruthy());

    fireEvent.click(screen.getByRole("button", { name: "Reset" }));
    fireEvent.click(within(await screen.findByRole("dialog")).getByRole("button", { name: "Reset" }));

    await waitFor(() => expect(screen.getAllByRole("alert").some((a) => a.textContent === "Redis unavailable")).toBe(true));
  });

  it("shows worker and beat health and the last result of every scheduled task", async () => {
    mount();
    expect(await screen.findByText("Worker: running")).toBeTruthy();
    expect(screen.getByText("Beat: no heartbeat")).toBeTruthy();
    expect(screen.getByText("Queue: 3")).toBeTruthy();
    const tasks = within(screen.getByRole("region", { name: "Background tasks" }));
    expect(tasks.getByText("boom")).toBeTruthy();
    expect(tasks.getByText("Failed")).toBeTruthy();
    expect(tasks.getByText("Never ran")).toBeTruthy();
  });

  it("shows backup age, the failed restore test, and an unrecovered failure alert", async () => {
    mount();
    expect(await screen.findByText("Newest backup: Overdue")).toBeTruthy();
    expect(screen.getByText("Restore test: Failed")).toBeTruthy();
    expect(screen.getByText("Stored on this machine only")).toBeTruthy();
    expect(screen.getByText(/no newer backup has succeeded/)).toBeTruthy();
    expect(screen.getByText("25 h")).toBeTruthy();
  });

  it("says the backup status is unavailable instead of pretending it is fine", async () => {
    api.getBackupOverview.mockResolvedValue({ state: "unavailable", backup: null, verify: { state: "never" }, failure_marker_at: null });
    mount();
    expect(await screen.findByText(/cannot see the backup status directory/)).toBeTruthy();
  });
});
