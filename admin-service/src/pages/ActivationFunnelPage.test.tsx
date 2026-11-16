// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { I18nProvider } from "../lib/i18n";
import { ActivationFunnelPage } from "./ActivationFunnelPage";

const api = vi.hoisted(() => ({ getActivationFunnel: vi.fn() }));
vi.mock("../lib/analyticsApi", () => ({ ...api }));

const step = (key: string, count: number, first: number | null, prev: number | null, extra = {}) => ({
  key, label: key, definition: `def ${key}`, count, pct_of_first: first, pct_of_previous: prev, ...extra,
});
const cell = (eligible: number, retained: number) => ({ eligible, retained, rate: eligible ? Math.round((retained / eligible) * 1000) / 10 : null });

const payload = (over = {}) => ({
  window_days: 90,
  retention_definition: "Dn definition",
  steps: [
    step("signed_up", 20, 100, null),
    step("email_verified", 10, 50, 50, { breakdown: { with_google_provider: 8, without_google_provider: 2 } }),
    step("onboarding_completed", 8, 40, 80),
    step("enrolled", 5, 25, 62.5),
    step("lesson_started", 4, 20, 80),
    step("lesson_completed", 2, 10, 50),
  ],
  cohorts: [{ week_start: "2026-11-09", size: 7, d1: cell(7, 2), d7: cell(0, 0), d30: cell(0, 0) }],
  ...over,
});

beforeEach(() => {
  const store = new Map<string, string>([["lexi_admin_locale", "en"]]);
  vi.stubGlobal("localStorage", {
    getItem: (k: string) => store.get(k) ?? null,
    setItem: (k: string, v: string) => void store.set(k, v),
    removeItem: (k: string) => void store.delete(k),
  });
  api.getActivationFunnel.mockReset();
});
afterEach(cleanup);

const mount = () =>
  render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <I18nProvider>
        <ActivationFunnelPage />
      </I18nProvider>
    </QueryClientProvider>,
  );

describe("ActivationFunnelPage", () => {
  it("shows every step with counts and percentages, and null retention as a dash", async () => {
    api.getActivationFunnel.mockResolvedValue(payload());
    mount();
    expect(await screen.findByText("Email verified")).toBeTruthy();
    expect(screen.getByText("Completed a lesson")).toBeTruthy();
    expect(screen.getAllByText(/50% of previous step/).length).toBe(2);
    expect(screen.getByText(/8 with a Google provider/)).toBeTruthy();
    expect(screen.getByText("28.6%")).toBeTruthy();
    expect(screen.getAllByText("—").length).toBe(2);
  });

  it("shows the empty state when nobody signed up", async () => {
    api.getActivationFunnel.mockResolvedValue(payload({ steps: [step("signed_up", 0, null, null)], cohorts: [] }));
    mount();
    expect(await screen.findByText("No signups in this window")).toBeTruthy();
  });

  it("shows the error with a retry", async () => {
    api.getActivationFunnel.mockRejectedValue(new Error("boom"));
    mount();
    await waitFor(() => expect(screen.getByRole("alert").textContent).toContain("boom"));
    expect(screen.getByText("Retry")).toBeTruthy();
  });
});
