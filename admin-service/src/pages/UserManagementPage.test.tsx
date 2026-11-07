// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { I18nProvider } from "../lib/i18n";
import { ConfirmProvider } from "../components/ConfirmDialog";
import UserManagementPage from "./UserManagementPage";

const api = vi.hoisted(() => ({
  getUsers: vi.fn(),
  updateUserStatus: vi.fn(),
  bulkUserAction: vi.fn(),
  permanentlyDeleteUser: vi.fn(),
}));

vi.mock("../lib/userManagementApi", () => ({
  ...api,
  getUserDetail: vi.fn(),
  getRoleLabel: (level: number) => (level === 2 ? "Super Admin" : level === 1 ? "Admin" : "User"),
}));
vi.mock("../lib/rbacApi", () => ({
  getDashboardStats: vi.fn().mockResolvedValue({ dashboard: { total_users: 3, active_users: 2 } }),
}));
vi.mock("../components/AuthProvider", () => ({
  useAuth: () => ({ user: { id: "me" }, role: "super_admin" }),
}));
vi.mock("../components/user-management/UserFiltersPanel", () => ({ default: () => null }));
vi.mock("../components/user-management/UserDetailModal", () => ({
  default: ({ userId }: { userId: string }) => <div role="dialog" aria-label="detail">{userId}</div>,
}));

const user = (id: string, email: string, over: Record<string, unknown> = {}) => ({
  id,
  email,
  username: id,
  display_name: null,
  is_active: true,
  is_verified: true,
  role_slug: "user",
  role_level: 0,
  created_at: "2026-01-02T00:00:00Z",
  last_login: null,
  total_xp: 500,
  streak_days: 3,
  ...over,
});

const page = (users: unknown[], extra = {}) => ({ users, total: users.length, total_pages: 1, page: 1, page_size: 20, ...extra });

const mount = () =>
  render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <I18nProvider>
        <ConfirmProvider>
          <UserManagementPage />
        </ConfirmProvider>
      </I18nProvider>
    </QueryClientProvider>,
  );

beforeEach(() => {
  // Node's experimental localStorage shadows jsdom's and is unusable without a file.
  const store = new Map<string, string>([["lexi_admin_locale", "en"]]);
  vi.stubGlobal("localStorage", {
    getItem: (k: string) => store.get(k) ?? null,
    setItem: (k: string, v: string) => void store.set(k, v),
    removeItem: (k: string) => void store.delete(k),
  });
  api.getUsers.mockResolvedValue(page([user("u1", "ann@x.co"), user("u2", "bob@x.co", { is_active: false })]));
});
afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

describe("UserManagementPage", () => {
  it("lists users in a table with translated headers and status labels", async () => {
    mount();
    expect(await screen.findByText("ann@x.co")).toBeTruthy();
    expect(screen.getByRole("columnheader", { name: /User$/ })).toBeTruthy();
    expect(screen.getByText("Paused")).toBeTruthy();
    expect(screen.getAllByText("Streak: 3 days")).toHaveLength(2);
    expect(screen.getAllByText("Never logged in")).toHaveLength(2);
  });

  it("asks the server to sort when a sortable header is clicked", async () => {
    mount();
    await screen.findByText("ann@x.co");
    fireEvent.click(screen.getByRole("button", { name: "Role" }));
    await waitFor(() =>
      expect(api.getUsers).toHaveBeenLastCalledWith(expect.objectContaining({ sort_by: "role", order: "asc", page: 1 })),
    );
    fireEvent.click(screen.getByRole("button", { name: "Role" }));
    await waitFor(() => expect(api.getUsers).toHaveBeenLastCalledWith(expect.objectContaining({ sort_by: "role", order: "desc" })));
  });

  it("selects every row from the header checkbox and offers bulk actions", async () => {
    mount();
    await screen.findByText("ann@x.co");
    const all = screen.getByLabelText("Select all users on this page") as HTMLInputElement;
    expect(all.checked).toBe(false);
    fireEvent.click(all);
    expect(await screen.findByText("2 selected")).toBeTruthy();
    expect(all.checked).toBe(true);
  });

  it("confirms before a bulk action and only then calls the API", async () => {
    api.bulkUserAction.mockResolvedValue({});
    mount();
    await screen.findByText("ann@x.co");
    fireEvent.click(screen.getByLabelText("Select all users on this page"));
    fireEvent.click(within(await screen.findByRole("region")).getByRole("button", { name: "Deactivate" }));

    const dialog = await screen.findByRole("dialog");
    expect(within(dialog).getByText("Deactivate the 2 selected users?")).toBeTruthy();
    expect(api.bulkUserAction).not.toHaveBeenCalled();
    fireEvent.click(within(dialog).getByRole("button", { name: "Deactivate" }));
    await waitFor(() => expect(api.bulkUserAction).toHaveBeenCalled());
    expect(api.bulkUserAction.mock.calls[0][0]).toEqual({ user_ids: ["u1", "u2"], action: "deactivate" });
  });

  it("requires typing the email before a permanent delete goes through", async () => {
    api.permanentlyDeleteUser.mockResolvedValue({});
    mount();
    await screen.findByText("ann@x.co");
    fireEvent.click(screen.getAllByRole("button", { name: "Delete permanently" })[0]);

    const dialog = await screen.findByRole("dialog");
    const confirmBtn = within(dialog).getByRole("button", { name: "Delete permanently" }) as HTMLButtonElement;
    expect(confirmBtn.disabled).toBe(true);
    fireEvent.change(within(dialog).getByRole("textbox"), { target: { value: "ann@x.co" } });
    expect(confirmBtn.disabled).toBe(false);
    fireEvent.click(confirmBtn);
    await waitFor(() => expect(api.permanentlyDeleteUser).toHaveBeenCalled());
    expect(api.permanentlyDeleteUser.mock.calls[0][0]).toBe("u1");
  });

  it("never offers permanent delete for the current admin or for admins", async () => {
    api.getUsers.mockResolvedValue(page([user("me", "me@x.co"), user("a1", "adm@x.co", { role_level: 1 }), user("u3", "c@x.co", { role_level: 2 })]));
    mount();
    await screen.findByText("me@x.co");
    expect(screen.getAllByRole("button", { name: "Delete permanently" })).toHaveLength(1);
  });

  it("opens the detail view from the user name", async () => {
    mount();
    fireEvent.click(await screen.findByRole("button", { name: "ann" }));
    expect((await screen.findByRole("dialog", { name: "detail" })).textContent).toBe("u1");
  });

  it("shows the empty state when nothing matches", async () => {
    api.getUsers.mockResolvedValue(page([]));
    mount();
    expect(await screen.findByText("No users found")).toBeTruthy();
  });

  it("shows pagination only when there is more than one page", async () => {
    api.getUsers.mockResolvedValue(page([user("u1", "ann@x.co")], { total: 45, total_pages: 3 }));
    mount();
    expect(await screen.findByText("Page 1 / 3 • 45 users in total")).toBeTruthy();
    expect((screen.getByRole("button", { name: "← Previous" }) as HTMLButtonElement).disabled).toBe(true);
    fireEvent.click(screen.getByRole("button", { name: "Next →" }));
    await waitFor(() => expect(api.getUsers).toHaveBeenLastCalledWith(expect.objectContaining({ page: 2 })));
  });
});
