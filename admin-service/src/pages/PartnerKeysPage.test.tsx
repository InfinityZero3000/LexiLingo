// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { I18nProvider } from "../lib/i18n";
import { ConfirmProvider } from "../components/ConfirmDialog";
import { PartnerKeysPage } from "./PartnerKeysPage";

const api = vi.hoisted(() => ({
  listPartnerKeys: vi.fn(),
  createPartnerKey: vi.fn(),
  revokePartnerKey: vi.fn(),
}));
vi.mock("../lib/partnerKeysApi", () => ({ ...api }));

const key = (over = {}) => ({
  id: "k1", key_id: "pk_abc123", owner: "Acme", scope: "read", status: "active",
  created_at: "2026-11-01T00:00:00Z", expires_at: null, revoked_at: null, ...over,
});

beforeEach(() => {
  const store = new Map<string, string>([["lexi_admin_locale", "en"]]);
  vi.stubGlobal("localStorage", {
    getItem: (k: string) => store.get(k) ?? null,
    setItem: (k: string, v: string) => void store.set(k, v),
    removeItem: (k: string) => void store.delete(k),
  });
  Object.values(api).forEach((fn) => fn.mockReset());
  api.listPartnerKeys.mockResolvedValue([key(), key({ id: "k2", key_id: "pk_old999", owner: "Old Co", status: "revoked" })]);
});
afterEach(cleanup);

const mount = () =>
  render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <I18nProvider>
        <ConfirmProvider>
          <PartnerKeysPage />
        </ConfirmProvider>
      </I18nProvider>
    </QueryClientProvider>,
  );

describe("PartnerKeysPage", () => {
  it("offers revoke only for keys that are still active", async () => {
    mount();
    await waitFor(() => expect(screen.getByText("pk_abc123")).toBeTruthy());

    expect(screen.getAllByRole("button", { name: "Revoke" })).toHaveLength(1);
    expect(screen.getByText("Revoked")).toBeTruthy();
  });

  it("requires typing the key id before it revokes", async () => {
    api.revokePartnerKey.mockResolvedValue(key({ status: "revoked" }));
    mount();
    fireEvent.click(await screen.findByRole("button", { name: "Revoke" }));
    const dialog = within(await screen.findByRole("dialog"));
    const confirm = dialog.getByRole("button", { name: "Revoke" }) as HTMLButtonElement;
    expect(confirm.disabled).toBe(true);

    fireEvent.change(dialog.getByRole("textbox"), { target: { value: "pk_abc123" } });
    expect(confirm.disabled).toBe(false);
    fireEvent.click(confirm);

    await waitFor(() => expect(api.revokePartnerKey).toHaveBeenCalledWith("k1"));
  });

  it("shows the new key exactly once", async () => {
    api.createPartnerKey.mockResolvedValue(key({ id: "k3", key_id: "pk_new", key: "pk_new.SECRETVALUE" }));
    mount();
    fireEvent.click(await screen.findByRole("button", { name: "Create key" }));
    const form = within(await screen.findByRole("dialog"));
    fireEvent.change(form.getByLabelText(/Owner/), { target: { value: "Beta Labs" } });
    fireEvent.click(form.getByRole("button", { name: "Create" }));

    await waitFor(() => expect(api.createPartnerKey).toHaveBeenCalledWith({ owner: "Beta Labs", expires_in_days: 90 }));
    const reveal = within(await screen.findByRole("dialog"));
    expect((reveal.getByLabelText("API key") as HTMLInputElement).value).toBe("pk_new.SECRETVALUE");
    expect(reveal.getByRole("alert").textContent).toMatch(/only once/);

    fireEvent.click(reveal.getByRole("button", { name: "Done" }));
    await waitFor(() => expect(screen.queryByDisplayValue("pk_new.SECRETVALUE")).toBeNull());
  });

  it("sends no expiry when the key should never expire", async () => {
    api.createPartnerKey.mockResolvedValue(key({ key: "pk_x.y" }));
    mount();
    fireEvent.click(await screen.findByRole("button", { name: "Create key" }));
    const form = within(await screen.findByRole("dialog"));
    fireEvent.change(form.getByLabelText(/Owner/), { target: { value: "Beta Labs" } });
    fireEvent.change(form.getByLabelText("Lifetime"), { target: { value: "0" } });
    fireEvent.click(form.getByRole("button", { name: "Create" }));

    await waitFor(() => expect(api.createPartnerKey).toHaveBeenCalledWith({ owner: "Beta Labs", expires_in_days: undefined }));
  });

  it("surfaces a creation failure in the form", async () => {
    api.createPartnerKey.mockRejectedValue(new Error("Super admin privileges required"));
    mount();
    fireEvent.click(await screen.findByRole("button", { name: "Create key" }));
    const form = within(await screen.findByRole("dialog"));
    fireEvent.change(form.getByLabelText(/Owner/), { target: { value: "Beta Labs" } });
    fireEvent.click(form.getByRole("button", { name: "Create" }));

    await waitFor(() => expect(form.getByRole("alert").textContent).toBe("Super admin privileges required"));
  });
});
