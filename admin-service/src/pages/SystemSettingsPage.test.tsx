// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { I18nProvider } from "../lib/i18n";
import { SystemSettingsPage } from "./SystemSettingsPage";

const ops = vi.hoisted(() => ({
  DIGEST_INTERVALS: [15, 30, 60, 180, 360, 720, 1440],
  getErrorReportSettings: vi.fn(),
  updateErrorReportSettings: vi.fn(),
  sendTestErrorReport: vi.fn(),
}));
vi.mock("../lib/opsApi", () => ({ ...ops }));
vi.mock("../lib/adminApi", () => ({ getSystemInfo: vi.fn().mockResolvedValue({ data: null }) }));
vi.mock("../lib/gemLimitsApi", () => ({ getGemLimits: vi.fn().mockResolvedValue({ usage: null }), updateGemLimits: vi.fn() }));
const auth = vi.hoisted(() => ({ role: "super_admin" }));
vi.mock("../components/AuthProvider", () => ({ useAuth: () => ({ user: { id: "me" }, role: auth.role }) }));

const settings = (over = {}) => ({
  enabled: true, recipients: ["support@lexilingo.me"], digest_interval_minutes: 60,
  spike_threshold: 20, client_spike_threshold: 200, cooldown_minutes: 60, last_digest_at: null, ...over,
});

beforeEach(() => {
  const store = new Map<string, string>([["lexi_admin_locale", "en"]]);
  vi.stubGlobal("localStorage", {
    getItem: (k: string) => store.get(k) ?? null,
    setItem: (k: string, v: string) => void store.set(k, v),
    removeItem: (k: string) => void store.delete(k),
  });
  [ops.getErrorReportSettings, ops.updateErrorReportSettings, ops.sendTestErrorReport].forEach((fn) => fn.mockReset());
  auth.role = "super_admin";
  ops.getErrorReportSettings.mockResolvedValue(settings());
});
afterEach(cleanup);

const mount = () =>
  render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <I18nProvider>
        <SystemSettingsPage />
      </I18nProvider>
    </QueryClientProvider>,
  );

const panel = async () => within(await screen.findByRole("heading", { name: "Error report emails" }).then((h) => h.closest(".panel") as HTMLElement));

describe("SystemSettingsPage error report panel", () => {
  it("blocks a malformed recipient before calling the API", async () => {
    mount();
    const p = await panel();
    await p.findByText("support@lexilingo.me");

    const input = p.getByLabelText("Recipients");
    fireEvent.change(input, { target: { value: "not-an-email" } });
    fireEvent.keyDown(input, { key: "Enter" });
    fireEvent.click(p.getByRole("button", { name: "Save" }));

    expect(await p.findByText("Invalid email: not-an-email")).toBeTruthy();
    expect(ops.updateErrorReportSettings).not.toHaveBeenCalled();
  });

  it("saves the edited settings", async () => {
    ops.updateErrorReportSettings.mockResolvedValue(settings({ spike_threshold: 5 }));
    mount();
    const p = await panel();
    await p.findByText("support@lexilingo.me");

    fireEvent.change(p.getByLabelText(/5xx spike threshold/), { target: { value: "5" } });
    fireEvent.change(p.getByLabelText("Digest interval"), { target: { value: "180" } });
    fireEvent.click(p.getByRole("button", { name: "Save" }));

    await waitFor(() =>
      expect(ops.updateErrorReportSettings).toHaveBeenCalledWith({
        enabled: true, recipients: ["support@lexilingo.me"], digest_interval_minutes: 180,
        spike_threshold: 5, client_spike_threshold: 200, cooldown_minutes: 60,
      }),
    );
    expect(await p.findByText("Error report settings saved")).toBeTruthy();
  });

  it("reports who the test email went to, and why it failed when SMTP is missing", async () => {
    ops.sendTestErrorReport.mockResolvedValueOnce({ sent_to: ["support@lexilingo.me"], groups: 3 });
    mount();
    const p = await panel();
    await p.findByText("support@lexilingo.me");

    fireEvent.click(p.getByRole("button", { name: "Send test report" }));
    expect(await p.findByText("Sent to support@lexilingo.me (3 error groups)")).toBeTruthy();

    ops.sendTestErrorReport.mockRejectedValueOnce(new Error("SMTP is not configured"));
    fireEvent.click(p.getByRole("button", { name: "Send test report" }));
    expect(await p.findByText("SMTP is not configured")).toBeTruthy();
  });

  it("is read-only for a plain admin", async () => {
    auth.role = "admin";
    mount();
    const p = await panel();
    await p.findByText("support@lexilingo.me");

    expect(p.queryByRole("button", { name: "Save" })).toBeNull();
    expect(p.queryByRole("button", { name: "Send test report" })).toBeNull();
    expect(p.getByText("Only a super admin can change these settings.")).toBeTruthy();
  });
});
