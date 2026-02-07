import { apiFetch } from "./api";
import { ENV } from "./env";

/* ─── Types ─────────────────────────────────────── */

export type Role = {
  id: string;
  name: string;
  slug: string;
  description: string;
  level: number;
  is_system: boolean;
  is_active: boolean;
  created_at: string;
};

export type Permission = {
  id: string;
  name: string;
  slug: string;
  resource: string;
  action: string;
  description: string;
  created_at: string;
};

export type RoleWithPermissions = Role & {
  permissions: Permission[];
};

export type AdminUser = {
  id: string;
  username: string;
  email: string;
  display_name: string;
  role: string;
  is_active: boolean;
  is_verified: boolean;
  numeric_level: number;
  total_xp: number;
  created_at: string;
};

export type UsersListResponse = {
  users: AdminUser[];
  total: number;
  page: number;
  per_page: number;
  pages: number;
};

export type AuditLogEntry = {
  id: string;
  user_id: string | null;
  action: string;
  resource_type: string;
  resource_id: string | null;
  details: string | null;
  ip_address: string | null;
  created_at: string;
};

export type AuditLogsResponse = {
  logs: AuditLogEntry[];
  total: number;
  page: number;
  per_page: number;
};

export type DashboardStats = {
  dashboard: {
    total_users: number;
    active_users: number;
    users_by_role: Record<string, number>;
    total_achievements: number;
    total_unlocks: number;
    recent_actions: Array<{
      action: string;
      resource_type: string;
      created_at: string;
    }>;
  };
};

/* ─── API Functions ─────────────────────────────── */

const base = () => ENV.backendUrl;

export const getRoles = () =>
  apiFetch<Role[]>(`${base()}/admin/rbac/roles`);

export const getRoleWithPermissions = (slug: string) =>
  apiFetch<RoleWithPermissions>(`${base()}/admin/rbac/roles/${slug}`);

export const getPermissions = () =>
  apiFetch<Permission[]>(`${base()}/admin/rbac/permissions`);

export const getUsers = (params: {
  page?: number;
  per_page?: number;
  role_slug?: string;
  search?: string;
}) => {
  const qs = new URLSearchParams();
  if (params.page) qs.set("page", String(params.page));
  if (params.per_page) qs.set("per_page", String(params.per_page));
  if (params.role_slug) qs.set("role_slug", params.role_slug);
  if (params.search) qs.set("search", params.search);
  return apiFetch<UsersListResponse>(`${base()}/admin/rbac/users?${qs}`);
};

export const assignRole = (userId: string, roleSlug: string) =>
  apiFetch<{ message: string; user_id: string; username: string; old_role: string; new_role: string }>(
    `${base()}/admin/rbac/users/assign-role`,
    {
      method: "POST",
      body: JSON.stringify({ user_id: userId, role_slug: roleSlug }),
    }
  );

export const deactivateUser = (userId: string) =>
  apiFetch<{ message: string }>(`${base()}/admin/rbac/users/${userId}/deactivate`, { method: "POST" });

export const activateUser = (userId: string) =>
  apiFetch<{ message: string }>(`${base()}/admin/rbac/users/${userId}/activate`, { method: "POST" });

export const getAuditLogs = (params: {
  page?: number;
  per_page?: number;
  action?: string;
  resource_type?: string;
}) => {
  const qs = new URLSearchParams();
  if (params.page) qs.set("page", String(params.page));
  if (params.per_page) qs.set("per_page", String(params.per_page));
  if (params.action) qs.set("action", params.action);
  if (params.resource_type) qs.set("resource_type", params.resource_type);
  return apiFetch<AuditLogsResponse>(`${base()}/admin/rbac/audit-logs?${qs}`);
};

export const getDashboardStats = () =>
  apiFetch<DashboardStats>(`${base()}/admin/rbac/dashboard`);
