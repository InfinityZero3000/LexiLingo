// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { I18nProvider } from "../lib/i18n";
import { GemLedgerPage } from "./GemLedgerPage";

const api = vi.hoisted(() => ({ getGemLimits: vi.fn(), listGemGrants: vi.fn(), updateGemLimits: vi.fn() }));
vi.mock("../lib/gemLimitsApi", () => ({ ...api }));

const grant = (over = {}) => ({
  id: "g1", kind: "gift", amount: 50, reason: "support goodwill", created_at: "2026-11-10T08:00:00Z",
  actor: { id: "a1", username: "boss" }, user: { id: "u1", username: "learner", email: "l@x.io" }, ...over,
});

beforeEach(() => {
  const store = new Map<string, string>([["lexi_admin_locale", "en"]]);
  vi.stubGlobal("localStorage", {
    getItem: (k: string) => store.get(k) ?? null,
    setItem: (k: string, v: string) => void store.set(k, v),
    removeItem: (k: string) => void store.delete(k),
  });
  Object.values(api).forEach((fn) => fn.mockReset());
  api.getGemLimits.mockResolvedValue({
    usage: { role: "admin", max_per_action: 500, daily_budget: 2000, spent_today: 150, remaining_today: 1850, item_gift_max_qty: 100 },
  });
  api.listGemGrants.mockResolvedValue({ total: 2, items: [grant(), grant({ id: "g2", kind: "adjust", amount: -20, reason: "refund error" })] });
});
afterEach(cleanup);

const mount = () =>
  render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <I18nProvider>
        <GemLedgerPage />
      </I18nProvider>
    </QueryClientProvider>,
  );

describe("GemLedgerPage", () => {
  it("shows today's budget and the grants with who, whom and why", async () => {
    mount();
    expect(await screen.findByText("support goodwill")).toBeTruthy();
    expect(screen.getByText("1,850")).toBeTruthy();
    expect(screen.getByText("of a 2,000/day budget")).toBeTruthy();
    expect(screen.getByText("−20".replace("−", "-"))).toBeTruthy();
    expect(screen.getAllByText("l@x.io")).toHaveLength(2);
  });

  it("filters by type and goes back to the first page", async () => {
    mount();
    await screen.findByText("support goodwill");
    fireEvent.change(screen.getByLabelText("Type"), { target: { value: "adjust" } });

    await waitFor(() =>
      expect(api.listGemGrants).toHaveBeenLastCalledWith({ kind: "adjust", date_from: "", date_to: "" }, 20, 0),
    );
  });

  it("explains an empty ledger", async () => {
    api.listGemGrants.mockResolvedValue({ total: 0, items: [] });
    mount();
    expect(await screen.findByText("No grants yet")).toBeTruthy();
  });
});
