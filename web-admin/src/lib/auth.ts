import { ENV } from "./env";

export type Role = "admin" | "super_admin";

export type UserProfile = {
  id: string;
  email: string;
  username: string;
  display_name?: string | null;
  avatar_url?: string | null;
  is_active?: boolean;
  is_verified?: boolean;
  role?: string;
  role_slug?: string;
  is_admin?: boolean;
  is_super_admin?: boolean;
};

const ACCESS_TOKEN_KEY = "lexi_admin_access";
const REFRESH_TOKEN_KEY = "lexi_admin_refresh";
const USER_KEY = "lexi_admin_user";
const ROLE_KEY = "lexi_admin_role";

export const authStore = {
  get accessToken(): string | null {
    return localStorage.getItem(ACCESS_TOKEN_KEY);
  },
  set accessToken(value: string | null) {
    if (value) localStorage.setItem(ACCESS_TOKEN_KEY, value);
    else localStorage.removeItem(ACCESS_TOKEN_KEY);
  },
  get refreshToken(): string | null {
    return localStorage.getItem(REFRESH_TOKEN_KEY);
  },
  set refreshToken(value: string | null) {
    if (value) localStorage.setItem(REFRESH_TOKEN_KEY, value);
    else localStorage.removeItem(REFRESH_TOKEN_KEY);
  },
  get user(): UserProfile | null {
    const raw = localStorage.getItem(USER_KEY);
    return raw ? (JSON.parse(raw) as UserProfile) : null;
  },
  set user(value: UserProfile | null) {
    if (value) localStorage.setItem(USER_KEY, JSON.stringify(value));
    else localStorage.removeItem(USER_KEY);
  },
  get role(): Role | null {
    return (localStorage.getItem(ROLE_KEY) as Role | null) ?? null;
  },
  set role(value: Role | null) {
    if (value) localStorage.setItem(ROLE_KEY, value);
    else localStorage.removeItem(ROLE_KEY);
  },
  clear() {
    localStorage.removeItem(ACCESS_TOKEN_KEY);
    localStorage.removeItem(REFRESH_TOKEN_KEY);
    localStorage.removeItem(USER_KEY);
    localStorage.removeItem(ROLE_KEY);
  }
};

export const resolveRole = (user: UserProfile): Role | null => {
  if (!user) return null;

  const effectiveRole = user.role || user.role_slug;
  if (effectiveRole === "super_admin" || user.is_super_admin) return "super_admin";
  if (effectiveRole === "admin" || user.is_admin) return "admin";

  const email = user.email?.toLowerCase?.() ?? "";
  const hasRoleConfig = ENV.adminEmails.length > 0 || ENV.superAdminEmails.length > 0;

  if (!hasRoleConfig) {
    return "admin";
  }

  if (ENV.superAdminEmails.map((e) => e.toLowerCase()).includes(email)) {
    return "super_admin";
  }

  if (ENV.adminEmails.map((e) => e.toLowerCase()).includes(email)) {
    return "admin";
  }

  return null;
};
