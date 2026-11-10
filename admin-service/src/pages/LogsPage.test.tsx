// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { I18nProvider } from "../lib/i18n";
import { LogsPage } from "./LogsPage";

const api = vi.hoisted(() => ({
  getAuditLogs: vi.fn(),
  getAuditFacets: vi.fn(),
  exportAuditLogs: vi.fn(),
}));
vi.mock("../lib/rbacApi", () => ({ ...api }));

const entry = (over: Record<string, unknown> = {}) => ({
  id: "1", user_id: "u1", actor: { username: "boss", email: "boss@x.io" }, action: "gift",
  resource_type: "user", resource_id: "abcdef1234", details: '{"amount":10}', ip_address: "1.2.3.4",
  user_agent: "ua", created_at: "2026-11-10T03:00:00Z", ...over,
});

beforeEach(() => {
  const store = new Map<string, string>([["lexi_admin_locale", "en"]]);
  vi.stubGlobal("localStorage", {
    getItem: (k: string) => store.get(k) ?? null,
    setItem: (k: string, v: string) => void store.set(k, v),
    removeItem: (k: string) => void store.delete(k),
  });
  Object.values(api).forEach((fn) => fn.mockReset());
  api.getAuditFacets.mockResolvedValue({ actions: ["gift", "update"], resource_types: ["user", "courses"] });
  api.getAuditLogs.mockResolvedValue({ logs: [entry()], total: 1, page: 1, per_page: 30 });
});
afterEach(cleanup);

const renderPage = () =>
  render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <I18nProvider>
        <LogsPage />
      </I18nProvider>
    </QueryClientProvider>,
  );

describe("LogsPage", () => {
  it("shows who did what, with a readable action label", async () => {
    renderPage();

    await waitFor(() => expect(screen.getByText("boss")).toBeTruthy());
    const table = within(screen.getByRole("table"));
    expect(table.getByText("Gift")).toBeTruthy();
    expect(table.getByText("1.2.3.4")).toBeTruthy();
  });

  it("labels a row whose admin was deleted as system/deleted", async () => {
    api.getAuditLogs.mockResolvedValue({ logs: [entry({ actor: null, user_id: null })], total: 1, page: 1, per_page: 30 });

    renderPage();

    await waitFor(() => expect(screen.getByText("System / deleted")).toBeTruthy());
  });

  it("offers only the actions that exist and filters by the chosen one", async () => {
    renderPage();
    await waitFor(() => expect(screen.getByRole("option", { name: "Update" })).toBeTruthy());

    fireEvent.change(screen.getByLabelText("Action"), { target: { value: "update" } });

    await waitFor(() =>
      expect(api.getAuditLogs).toHaveBeenLastCalledWith(expect.objectContaining({ action: "update", page: 1 })),
    );
  });

  it("passes a search term and a date range to the server", async () => {
    renderPage();
    await waitFor(() => expect(screen.getByText("boss")).toBeTruthy());

    fireEvent.change(screen.getByLabelText("Search"), { target: { value: "boss" } });
    fireEvent.submit(screen.getByLabelText("Search").closest("form")!);
    fireEvent.change(screen.getByLabelText("From date"), { target: { value: "2026-11-01" } });

    await waitFor(() =>
      expect(api.getAuditLogs).toHaveBeenLastCalledWith(
        expect.objectContaining({ q: "boss", date_from: "2026-11-01T00:00:00" }),
      ),
    );
  });

  it("reports an export failure instead of failing silently", async () => {
    api.exportAuditLogs.mockRejectedValue(new Error("too many rows"));
    renderPage();
    await waitFor(() => expect(screen.getByText("boss")).toBeTruthy());

    fireEvent.click(screen.getByText("Export CSV"));

    await waitFor(() => expect(screen.getByRole("alert").textContent).toBe("too many rows"));
  });
});
