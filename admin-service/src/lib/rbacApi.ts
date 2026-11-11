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

export type AuditLogEntry = {
  id: string;
  user_id: string | null;
  actor: { username: string | null; email: string | null } | null;
  action: string;
  resource_type: string;
  resource_id: string | null;
  details: string | null;
  ip_address: string | null;
  user_agent: string | null;
  created_at: string;
};

export type AuditQuery = {
  action?: string;
  resource_type?: string;
  resource_id?: string;
  user_id?: string;
  date_from?: string;
  date_to?: string;
  q?: string;
};

export type AuditFacets = { actions: string[]; resource_types: string[] };

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

export const setRolePermissions = (slug: string, permissionSlugs: string[]) =>
  apiFetch<RoleWithPermissions>(`${base()}/admin/rbac/roles/${slug}/permissions`, {
    method: "PUT",
    body: JSON.stringify({ permission_slugs: permissionSlugs }),
  });

export type MyPermissions = { all: boolean; permissions: string[] };

export const getMyPermissions = () =>
  apiFetch<MyPermissions>(`${base()}/admin/rbac/me/permissions`);

const auditQueryString = (params: AuditQuery & { page?: number; per_page?: number }) => {
  const qs = new URLSearchParams();
  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined && value !== "") qs.set(key, String(value));
  });
  return qs.toString();
};

export const getAuditLogs = (params: AuditQuery & { page?: number; per_page?: number }) =>
  apiFetch<AuditLogsResponse>(`${base()}/admin/rbac/audit-logs?${auditQueryString(params)}`);

export const getAuditFacets = () =>
  apiFetch<AuditFacets>(`${base()}/admin/rbac/audit-logs/facets`);

/** CSV text of the same filtered view (the server caps it at 10,000 rows). */
export const exportAuditLogs = (params: AuditQuery) =>
  apiFetch<string>(`${base()}/admin/rbac/audit-logs/export?${auditQueryString(params)}`);

export const getDashboardStats = () =>
  apiFetch<DashboardStats>(`${base()}/admin/rbac/dashboard`);
