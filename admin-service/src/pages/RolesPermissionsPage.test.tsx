// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { I18nProvider } from "../lib/i18n";
import { ConfirmProvider } from "../components/ConfirmDialog";
import { RolesPermissionsPage } from "./RolesPermissionsPage";

const api = vi.hoisted(() => ({
  getRoles: vi.fn(),
  getPermissions: vi.fn(),
  getRoleWithPermissions: vi.fn(),
  setRolePermissions: vi.fn(),
}));
vi.mock("../lib/rbacApi", () => ({ ...api }));
const auth = vi.hoisted(() => ({ role: "admin" }));
vi.mock("../components/AuthProvider", () => ({ useAuth: () => ({ role: auth.role }) }));

beforeEach(() => {
  const store = new Map<string, string>([["lexi_admin_locale", "en"]]);
  vi.stubGlobal("localStorage", {
    getItem: (k: string) => store.get(k) ?? null,
    setItem: (k: string, v: string) => void store.set(k, v),
    removeItem: (k: string) => void store.delete(k),
  });
  Object.values(api).forEach((fn) => fn.mockReset());
  auth.role = "admin";
});
afterEach(cleanup);

const role = (slug: string, level: number) => ({
  id: slug, name: slug, slug, description: "", level, is_system: true, is_active: true, created_at: "",
});
const permission = (slug: string, resource: string) => ({
  id: slug, name: slug, slug, resource, action: slug.split(":")[1], description: "", created_at: "",
});

const renderPage = () =>
  render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <I18nProvider>
        <ConfirmProvider>
          <RolesPermissionsPage />
        </ConfirmProvider>
      </I18nProvider>
    </QueryClientProvider>,
  );

describe("RolesPermissionsPage", () => {
  it("shows which roles hold which permission, read-only for a plain admin", async () => {
    const users = permission("users:read", "users");
    const courses = permission("courses:write", "courses");
    api.getRoles.mockResolvedValue([role("admin", 1), role("user", 0)]);
    api.getPermissions.mockResolvedValue([users, courses]);
    api.getRoleWithPermissions.mockImplementation(async (slug: string) => ({
      ...role(slug, slug === "admin" ? 1 : 0),
      permissions: slug === "admin" ? [users, courses] : [users],
    }));

    renderPage();

    await waitFor(() => expect(screen.getByText("users:read")).toBeTruthy());
    expect(screen.getByRole("note").textContent).toMatch(/set by a super admin/);
    expect(screen.queryAllByRole("checkbox")).toHaveLength(0);
    // admin holds both permissions, user holds one
    expect(screen.getAllByLabelText("Granted")).toHaveLength(3);
    expect(screen.getAllByLabelText("Not granted")).toHaveLength(1);
    // columns are ordered by level, lowest first
    const headers = screen.getAllByRole("columnheader").map((h) => h.textContent);
    expect(headers[1]).toContain("user");
    expect(headers[2]).toContain("admin");
  });

  it("explains an unseeded permission table", async () => {
    api.getRoles.mockResolvedValue([role("admin", 1)]);
    api.getPermissions.mockResolvedValue([]);
    api.getRoleWithPermissions.mockResolvedValue({ ...role("admin", 1), permissions: [] });

    renderPage();

    await waitFor(() => expect(screen.getByText("No permission data yet")).toBeTruthy());
  });

  it("surfaces a load failure", async () => {
    api.getRoles.mockRejectedValue(new Error("forbidden"));
    api.getPermissions.mockResolvedValue([]);

    renderPage();

    await waitFor(() => expect(screen.getByRole("alert").textContent).toBe("forbidden"));
  });

  it("lets a super admin untick an admin permission and saves the whole set", async () => {
    auth.role = "super_admin";
    const users = permission("users:read", "users");
    const courses = permission("courses:read", "courses");
    api.getRoles.mockResolvedValue([role("admin", 1), role("super_admin", 2)]);
    api.getPermissions.mockResolvedValue([users, courses]);
    api.getRoleWithPermissions.mockImplementation(async (slug: string) => ({
      ...role(slug, slug === "admin" ? 1 : 2),
      permissions: [users, courses],
    }));
    api.setRolePermissions.mockResolvedValue({});

    renderPage();
    const box = await screen.findByLabelText("admin: courses:read");
    expect((box as HTMLInputElement).checked).toBe(true);
    // only admin-level columns are editable
    expect(screen.queryByLabelText("super_admin: courses:read")).toBeNull();

    fireEvent.click(box);
    fireEvent.click(screen.getByRole("button", { name: "Save changes" }));
    const dialog = within(await screen.findByRole("dialog"));
    fireEvent.click(dialog.getByRole("button", { name: "Save" }));

    await waitFor(() => expect(api.setRolePermissions).toHaveBeenCalledWith("admin", ["users:read"]));
    expect(await screen.findByText("Permissions saved")).toBeTruthy();
  });
});
