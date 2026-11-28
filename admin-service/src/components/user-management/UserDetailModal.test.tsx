// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { I18nProvider } from "../../lib/i18n";
import { ConfirmProvider } from "../ConfirmDialog";
import UserDetailModal from "./UserDetailModal";
import { ApiError } from "../../lib/api";

const api = vi.hoisted(() => ({
  getUserDetail: vi.fn(),
  updateUser: vi.fn(),
  updateUserRole: vi.fn(),
  getUserActivity: vi.fn(),
  giftToUser: vi.fn(),
}));

vi.mock("../../lib/userManagementApi", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../../lib/userManagementApi")>()),
  ...api,
}));
const { getMyPermissions, getRoles } = vi.hoisted(() => ({ getMyPermissions: vi.fn(), getRoles: vi.fn() }));
vi.mock("../../lib/rbacApi", () => ({ getMyPermissions, getRoles }));
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
  role_slug: "user",
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
  const store = new Map<string, string>([
    ["lexi_admin_locale", "en"], ["lexi_admin_access", "test-token"],
    ["lexi_admin_user", JSON.stringify({ id: "operator-1", email: "operator@example.com", username: "operator" })],
  ]);
  getMyPermissions.mockReset();
  getMyPermissions.mockResolvedValue({ all: false, permissions: ["gifts:grant"] });
  getRoles.mockReset();
  getRoles.mockResolvedValue([]);
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
    await waitFor(() => expect(api.updateUserRole.mock.calls[0].slice(0, 2)).toEqual(["u1", { slug: "admin" }]));
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

  it("marks a test account by slug, since it shares level 0 with User", async () => {
    api.updateUserRole.mockResolvedValue({});
    mount();
    await screen.findByText("Personal info");
    fireEvent.click(screen.getByRole("button", { name: "Test" }));
    const dialog = await screen.findByText("Change this user's role to Test?");
    fireEvent.click(within(dialog.closest('[role="dialog"]') as HTMLElement).getByRole("button", { name: "Change role" }));
    await waitFor(() => expect(api.updateUserRole.mock.calls[0].slice(0, 2)).toEqual(["u1", { slug: "test" }]));
  });

  const customRole = (slug: string, name: string, is_active = true) => ({
    id: slug, slug, name, description: "", level: 1, is_system: false, is_active, created_at: "",
  });

  it("offers active custom roles and assigns one by its slug", async () => {
    getRoles.mockResolvedValue([customRole("editor", "Course Editor"), customRole("retired", "Retired", false)]);
    api.updateUserRole.mockResolvedValue({});
    mount();
    await screen.findByText("Personal info");
    fireEvent.click(await screen.findByRole("button", { name: "Course Editor" }));
    expect(screen.queryByRole("button", { name: "Retired" })).toBeNull();
    const dialog = await screen.findByText("Change this user's role to Course Editor?");
    fireEvent.click(within(dialog.closest('[role="dialog"]') as HTMLElement).getByRole("button", { name: "Change role" }));
    await waitFor(() => expect(api.updateUserRole.mock.calls[0].slice(0, 2)).toEqual(["u1", { slug: "editor" }]));
  });

  it("says why the server refused a role change", async () => {
    api.updateUserRole.mockRejectedValue(new Error("Changing another super admin needs a recent sign-in"));
    mount();
    await screen.findByText("Personal info");
    fireEvent.click(screen.getByRole("button", { name: "Admin" }));
    const dialog = await screen.findByText("Change this user's role to Admin?");
    fireEvent.click(within(dialog.closest('[role="dialog"]') as HTMLElement).getByRole("button", { name: "Change role" }));
    expect(await screen.findByText(/needs a recent sign-in/)).toBeTruthy();
  });

  const refusal = (reason: string, extra: object = {}) =>
    new ApiError("refused", 409, { error: { message: "refused", details: { reason, ...extra } } });

  it("asks before a grant removes the account's password, then sends the confirmation", async () => {
    api.updateUserRole
      .mockRejectedValueOnce(refusal("password_will_be_removed", { email: "ann@x.co" }))
      .mockResolvedValueOnce({});
    mount();
    await screen.findByText("Personal info");
    fireEvent.click(screen.getByRole("button", { name: "Admin" }));
    const first = await screen.findByText("Change this user's role to Admin?");
    fireEvent.click(within(first.closest('[role="dialog"]') as HTMLElement).getByRole("button", { name: "Change role" }));

    const warning = await screen.findByText(/ann@x\.co also signs in with a password/);
    expect(api.updateUserRole).toHaveBeenCalledTimes(1);
    fireEvent.click(within(warning.closest('[role="dialog"]') as HTMLElement).getByRole("button", { name: "Remove password and grant" }));

    await waitFor(() => expect(api.updateUserRole).toHaveBeenCalledTimes(2));
    expect(api.updateUserRole.mock.calls[1].slice(0, 2)).toEqual(["u1", { slug: "admin", remove_password: true }]);
  });

  it("keeps the password when the super admin declines", async () => {
    api.updateUserRole.mockRejectedValueOnce(refusal("password_will_be_removed", { email: "ann@x.co" }));
    mount();
    await screen.findByText("Personal info");
    fireEvent.click(screen.getByRole("button", { name: "Admin" }));
    const first = await screen.findByText("Change this user's role to Admin?");
    fireEvent.click(within(first.closest('[role="dialog"]') as HTMLElement).getByRole("button", { name: "Change role" }));
    const warning = await screen.findByText(/also signs in with a password/);
    fireEvent.click(within(warning.closest('[role="dialog"]') as HTMLElement).getByRole("button", { name: "Cancel" }));

    await waitFor(() => expect(screen.queryByText(/also signs in with a password/)).toBeNull());
    expect(api.updateUserRole).toHaveBeenCalledTimes(1);
  });

  it("explains that admin roles need a Google account", async () => {
    api.updateUserRole.mockRejectedValueOnce(refusal("google_sign_in_required"));
    mount();
    await screen.findByText("Personal info");
    fireEvent.click(screen.getByRole("button", { name: "Admin" }));
    const first = await screen.findByText("Change this user's role to Admin?");
    fireEvent.click(within(first.closest('[role="dialog"]') as HTMLElement).getByRole("button", { name: "Change role" }));
    expect(await screen.findByText(/Admin roles go only to accounts that have signed in with Google/)).toBeTruthy();
  });

  it("hides gifting without a backend grant", async () => {
    getMyPermissions.mockResolvedValue({ all: false, permissions: [] });
    mount();
    await screen.findByText("Personal info");
    await waitFor(() => expect(getMyPermissions).toHaveBeenCalledOnce());
    expect(screen.queryByRole("tab", { name: "Send gift" })).toBeNull();
    expect(api.giftToUser).not.toHaveBeenCalled();
  });

  it("rejects an empty course gift without calling the API", async () => {
    mount();
    await screen.findByText("Personal info");
    fireEvent.click(await screen.findByRole("tab", { name: "Send gift" }));
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
    fireEvent.click(await screen.findByRole("tab", { name: "Send gift" }));
    expect(await screen.findByText("Up to 500 gems per gift · 1,850/2,000 gems left today")).toBeTruthy();
    fireEvent.change(screen.getByLabelText("Reason for the gift"), { target: { value: "support goodwill" } });
    fireEvent.click(await screen.findByRole("button", { name: "Send gift" }));
    expect((await screen.findByRole("status")).textContent).toBe("Gift sent: 100 Gems");
    expect(api.giftToUser).toHaveBeenCalledWith("u1", { gift_type: "gems", amount: 100, reason: "support goodwill" });
  });

  it("will not send a gift without a written reason", async () => {
    mount();
    await screen.findByText("Personal info");
    fireEvent.click(await screen.findByRole("tab", { name: "Send gift" }));
    const form = (await screen.findByLabelText("Reason for the gift")).closest("form") as HTMLFormElement;
    fireEvent.change(screen.getByLabelText("Reason for the gift"), { target: { value: "hi" } });
    fireEvent.submit(form);
    expect((await screen.findByRole("alert")).textContent).toBe("Please enter a reason (min. 5 characters)");
    expect(api.giftToUser).not.toHaveBeenCalled();
  });

  it("requires typing Super Admin before promoting a user to Super Admin", async () => {
    api.updateUserRole.mockResolvedValue({});
    mount();
    await screen.findByText("Personal info");
    fireEvent.click(screen.getByRole("button", { name: "Super Admin" }));
    const text = await screen.findByText("Change this user's role to Super Admin?");
    const dialog = text.closest('[role="dialog"]') as HTMLElement;
    const confirmBtn = within(dialog).getByRole("button", { name: "Change role" }) as HTMLButtonElement;
    expect(confirmBtn.disabled).toBe(true);
    fireEvent.change(within(dialog).getByRole("textbox"), { target: { value: "Super Admin" } });
    expect(confirmBtn.disabled).toBe(false);
    fireEvent.click(confirmBtn);
    await waitFor(() => expect(api.updateUserRole.mock.calls[0].slice(0, 2)).toEqual(["u1", { slug: "super_admin" }]));
  });
});
