// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { I18nProvider } from "../../lib/i18n";
import { ConfirmProvider } from "../ConfirmDialog";
import UserDetailModal from "./UserDetailModal";

const api = vi.hoisted(() => ({
  getUserDetail: vi.fn(),
  updateUser: vi.fn(),
  updateUserRole: vi.fn(),
  getUserActivity: vi.fn(),
  giftToUser: vi.fn(),
}));

vi.mock("../../lib/userManagementApi", () => ({
  ...api,
  getRoleLabel: (level: number) => (level === 2 ? "Super Admin" : level === 1 ? "Admin" : "User"),
}));
vi.mock("../../lib/gemLimitsApi", () => ({
  getGemLimits: vi.fn().mockResolvedValue({
    usage: { role: "admin", max_per_action: 500, daily_budget: 2000, spent_today: 150, remaining_today: 1850, item_gift_max_qty: 100 },
  }),
}));
vi.mock("../../lib/adminApi", () => ({
  listCoursesAdmin: vi.fn().mockResolvedValue({ data: { courses: [] } }),
  listShopItems: vi.fn().mockResolvedValue({ data: [] }),
}));

const detail = {
  id: "u1",
  email: "ann@x.co",
  display_name: "Ann",
  is_active: true,
  role_level: 0,
  total_xp: 1500,
  courses_completed: 1,
  courses_enrolled: 3,
  lessons_completed: 12,
  created_at: "2026-01-02T00:00:00Z",
  last_login: null,
  bio: null,
  language_preference: null,
  notification_enabled: true,
};

const mount = (onClose = vi.fn()) =>
  render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <I18nProvider>
        <ConfirmProvider>
          <UserDetailModal userId="u1" onClose={onClose} />
        </ConfirmProvider>
      </I18nProvider>
    </QueryClientProvider>,
  );

beforeEach(() => {
  const store = new Map<string, string>([["lexi_admin_locale", "en"]]);
  vi.stubGlobal("localStorage", {
    getItem: (k: string) => store.get(k) ?? null,
    setItem: (k: string, v: string) => void store.set(k, v),
    removeItem: (k: string) => void store.delete(k),
  });
  api.getUserDetail.mockResolvedValue(detail);
  api.getUserActivity.mockResolvedValue([]);
});
afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

describe("UserDetailModal", () => {
  it("shows the profile and marks the active tab for assistive tech", async () => {
    mount();
    expect(await screen.findByText("Personal info")).toBeTruthy();
    expect(screen.getByText("1,500")).toBeTruthy();
    expect(screen.getAllByText("Never logged in")).toHaveLength(1);
    expect(screen.getByRole("tab", { name: "Info" }).getAttribute("aria-selected")).toBe("true");
    expect(screen.getByRole("tab", { name: "Activity" }).getAttribute("aria-selected")).toBe("false");
  });

  it("offers a retry when the user cannot be loaded", async () => {
    api.getUserDetail.mockRejectedValueOnce(new Error("boom")).mockResolvedValueOnce(detail);
    mount();
    expect(await screen.findByText("boom")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Retry" }));
    expect(await screen.findByText("Personal info")).toBeTruthy();
  });

  it("changes the role only after the confirm dialog is accepted", async () => {
    api.updateUserRole.mockResolvedValue({});
    mount();
    await screen.findByText("Personal info");
    fireEvent.click(screen.getByRole("button", { name: "Admin" }));
    const dialog = await screen.findByText("Change this user's role to Admin?");
    expect(api.updateUserRole).not.toHaveBeenCalled();
    fireEvent.click(within(dialog.closest('[role="dialog"]') as HTMLElement).getByRole("button", { name: "Change role" }));
    await waitFor(() => expect(api.updateUserRole.mock.calls[0].slice(0, 2)).toEqual(["u1", { level: 1 }]));
  });

  it("leaves the role alone when the confirm dialog is cancelled", async () => {
    mount();
    await screen.findByText("Personal info");
    fireEvent.click(screen.getByRole("button", { name: "Admin" }));
    const text = await screen.findByText("Change this user's role to Admin?");
    fireEvent.click(within(text.closest('[role="dialog"]') as HTMLElement).getByRole("button", { name: "Cancel" }));
    await waitFor(() => expect(screen.queryByText("Change this user's role to Admin?")).toBeNull());
    expect(api.updateUserRole).not.toHaveBeenCalled();
  });

  it("disables the button for the role the user already has", async () => {
    mount();
    await screen.findByText("Personal info");
    expect((screen.getByRole("button", { name: "User" }) as HTMLButtonElement).disabled).toBe(true);
    expect((screen.getByRole("button", { name: "Admin" }) as HTMLButtonElement).disabled).toBe(false);
  });

  it("rejects an empty course gift without calling the API", async () => {
    mount();
    await screen.findByText("Personal info");
    fireEvent.click(screen.getByRole("tab", { name: "Send gift" }));
    fireEvent.change(screen.getByRole("combobox"), { target: { value: "course" } });
    fireEvent.change(screen.getByLabelText("Reason for the gift"), { target: { value: "welcome back" } });
    const form = (await screen.findByText("Choose a course")).closest("form") as HTMLFormElement;
    fireEvent.submit(form);
    expect((await screen.findByRole("alert")).textContent).toBe("Please choose a course");
    expect(api.giftToUser).not.toHaveBeenCalled();
  });

  it("sends a gems gift and reports success", async () => {
    api.giftToUser.mockResolvedValue({ success: true, message: "ok", data: { gift_description: "100 Gems" } });
    mount();
    await screen.findByText("Personal info");
    fireEvent.click(screen.getByRole("tab", { name: "Send gift" }));
    expect(await screen.findByText("Up to 500 gems per gift · 1,850/2,000 gems left today")).toBeTruthy();
    fireEvent.change(screen.getByLabelText("Reason for the gift"), { target: { value: "support goodwill" } });
    fireEvent.click(await screen.findByRole("button", { name: "Send gift" }));
    expect((await screen.findByRole("status")).textContent).toBe("Gift sent: 100 Gems");
    expect(api.giftToUser).toHaveBeenCalledWith("u1", { gift_type: "gems", amount: 100, reason: "support goodwill" });
  });

  it("will not send a gift without a written reason", async () => {
    mount();
    await screen.findByText("Personal info");
    fireEvent.click(screen.getByRole("tab", { name: "Send gift" }));
    const form = (await screen.findByLabelText("Reason for the gift")).closest("form") as HTMLFormElement;
    fireEvent.change(screen.getByLabelText("Reason for the gift"), { target: { value: "hi" } });
    fireEvent.submit(form);
    expect((await screen.findByRole("alert")).textContent).toBe("Please enter a reason (min. 5 characters)");
    expect(api.giftToUser).not.toHaveBeenCalled();
  });
});
