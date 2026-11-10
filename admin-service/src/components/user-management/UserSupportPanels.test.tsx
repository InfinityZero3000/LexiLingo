// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { I18nProvider } from "../../lib/i18n";
import { UserWalletPanel } from "./UserWalletPanel";
import { UserPremiumPanel } from "./UserPremiumPanel";

const api = vi.hoisted(() => ({
  getUserWallet: vi.fn(),
  adjustUserWallet: vi.fn(),
  getUserXp: vi.fn(),
  getUserInventory: vi.fn(),
  getUserEntitlement: vi.fn(),
  grantPremium: vi.fn(),
  revokePremium: vi.fn(),
}));
vi.mock("../../lib/userSupportApi", () => ({ ...api }));
const auth = vi.hoisted(() => ({ role: "super_admin" }));
vi.mock("../AuthProvider", () => ({ useAuth: () => ({ user: { id: "me" }, role: auth.role }) }));

const wallet = {
  balance: 120, total_earned: 200, total_spent: 80, total: 2,
  transactions: [
    { id: "1", type: "earn", amount: 50, balance_after: 120, source: "admin_adjust", description: "Lost reward", created_at: "2026-11-10T03:00:00Z" },
    { id: "2", type: "spend", amount: -30, balance_after: 70, source: "shop", description: null, created_at: "2026-11-09T03:00:00Z" },
  ],
};
const entitlement = (over = {}) => ({
  entitlement_id: "premium", exists: true, is_active: true, status: "active", source: "admin",
  product_id: "admin_grant", expires_at: "2026-12-10T00:00:00Z", synced_at: null, force_enabled: false, ...over,
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
  api.getUserWallet.mockResolvedValue(wallet);
  api.getUserXp.mockResolvedValue({ total_xp: 900, total: 0, transactions: [] });
  api.getUserEntitlement.mockResolvedValue(entitlement());
});
afterEach(cleanup);

const mount = (ui: React.ReactNode) =>
  render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <I18nProvider>{ui}</I18nProvider>
    </QueryClientProvider>,
  );

describe("UserWalletPanel", () => {
  it("shows the balance and a signed ledger", async () => {
    mount(<UserWalletPanel userId="u1" />);

    const card = await screen.findByText("Gem balance");
    await waitFor(() => expect(card.closest("article")!.textContent).toContain("120"));
    const table = within(screen.getByRole("table"));
    expect(table.getByText("+50")).toBeTruthy();
    expect(table.getByText("-30")).toBeTruthy();
    expect(table.getByText("Lost reward")).toBeTruthy();
  });

  it("offers wallet adjustments only to a super admin", async () => {
    auth.role = "admin";
    mount(<UserWalletPanel userId="u1" />);
    await screen.findByText("Gem balance");
    await waitFor(() => expect(screen.getByRole("table")).toBeTruthy());
    expect(screen.queryByRole("button", { name: "Adjust gems" })).toBeNull();
  });

  it("will not submit an adjustment without a non-zero whole number and a reason", async () => {
    api.adjustUserWallet.mockResolvedValue({ balance: 70, delta: -50 });
    mount(<UserWalletPanel userId="u1" />);
    fireEvent.click(await screen.findByRole("button", { name: "Adjust gems" }));
    const dialog = within(await screen.findByRole("dialog"));
    const submit = dialog.getByRole("button", { name: "Adjust" }) as HTMLButtonElement;
    expect(submit.disabled).toBe(true);

    fireEvent.change(dialog.getByLabelText(/Gems/), { target: { value: "0" } });
    fireEvent.change(dialog.getByLabelText("Reason"), { target: { value: "refund after bug" } });
    expect(submit.disabled).toBe(true);

    fireEvent.change(dialog.getByLabelText(/Gems/), { target: { value: "-50" } });
    fireEvent.change(dialog.getByLabelText("Reason"), { target: { value: "no" } });
    expect(submit.disabled).toBe(true);

    fireEvent.change(dialog.getByLabelText("Reason"), { target: { value: "refund after bug" } });
    expect(submit.disabled).toBe(false);
    fireEvent.click(submit);

    await waitFor(() => expect(api.adjustUserWallet).toHaveBeenCalledWith("u1", { delta: -50, reason: "refund after bug" }));
  });

  it("keeps the dialog open and shows the server's refusal", async () => {
    api.adjustUserWallet.mockRejectedValue(new Error("not enough gems"));
    mount(<UserWalletPanel userId="u1" />);
    fireEvent.click(await screen.findByRole("button", { name: "Adjust gems" }));
    const dialog = within(await screen.findByRole("dialog"));
    fireEvent.change(dialog.getByLabelText(/Gems/), { target: { value: "-999" } });
    fireEvent.change(dialog.getByLabelText("Reason"), { target: { value: "refund after bug" } });
    fireEvent.click(dialog.getByRole("button", { name: "Adjust" }));

    await waitFor(() => expect(dialog.getByRole("alert").textContent).toBe("not enough gems"));
  });
});

describe("UserPremiumPanel", () => {
  it("lets a super admin grant premium with a reason", async () => {
    api.getUserEntitlement.mockResolvedValue(entitlement({ exists: false, is_active: false, status: "none", source: null, product_id: null, expires_at: null }));
    api.grantPremium.mockResolvedValue(entitlement());
    mount(<UserPremiumPanel userId="u1" />);

    fireEvent.click(await screen.findByRole("button", { name: "Grant premium" }));
    const dialog = within(await screen.findByRole("dialog"));
    fireEvent.change(dialog.getByLabelText("Reason"), { target: { value: "support goodwill" } });
    fireEvent.click(dialog.getByRole("button", { name: "Grant premium" }));

    await waitFor(() => expect(api.grantPremium).toHaveBeenCalledWith("u1", { days: 30, reason: "support goodwill" }));
  });

  it("offers revoke only for an admin-granted premium", async () => {
    mount(<UserPremiumPanel userId="u1" />);
    expect(await screen.findByRole("button", { name: "Revoke" })).toBeTruthy();
    expect(screen.getByText("Granted by an admin")).toBeTruthy();
  });

  it("never offers grant or revoke over a paid subscription", async () => {
    api.getUserEntitlement.mockResolvedValue(entitlement({ source: "revenuecat", product_id: "yearly" }));
    mount(<UserPremiumPanel userId="u1" />);

    await waitFor(() => expect(screen.getByText("Paid plan (store)")).toBeTruthy());
    expect(screen.queryByRole("button", { name: "Grant premium" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Revoke" })).toBeNull();
  });

  it("hides the actions from a plain admin and flags the force-enabled switch", async () => {
    auth.role = "admin";
    api.getUserEntitlement.mockResolvedValue(entitlement({ force_enabled: true }));
    mount(<UserPremiumPanel userId="u1" />);

    await waitFor(() => expect(screen.getByText("Premium is on for everyone")).toBeTruthy());
    expect(screen.queryByRole("button", { name: "Revoke" })).toBeNull();
  });
});
