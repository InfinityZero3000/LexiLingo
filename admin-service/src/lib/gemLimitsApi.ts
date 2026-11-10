import { apiFetch } from "./api";
import { ENV } from "./env";

type Envelope<T> = { success: boolean; message?: string; data: T };
const unwrap = async <T>(request: Promise<Envelope<T>>) => (await request).data;

export type GemUsage = {
  role: "admin" | "super_admin";
  max_per_action: number;
  daily_budget: number;
  spent_today: number;
  remaining_today: number;
  item_gift_max_qty: number;
};

export type GemLimitsConfig = {
  gift_max_admin: number;
  gift_max_super_admin: number;
  budget_admin: number;
  budget_super_admin: number;
  item_max_qty: number;
};

export type GemLimits = { usage: GemUsage; config?: GemLimitsConfig };

export type GemGrant = {
  id: string;
  kind: "gift" | "adjust";
  amount: number;
  reason: string;
  created_at: string | null;
  actor: { id: string | null; username: string | null };
  user: { id: string | null; username: string | null; email: string | null };
};

export type GemGrantFilters = { kind?: string; date_from?: string; date_to?: string };

const url = `${ENV.backendUrl}/admin`;

export const getGemLimits = () => unwrap(apiFetch<Envelope<GemLimits>>(`${url}/gem-limits`));

export const updateGemLimits = (patch: Partial<GemLimitsConfig>) =>
  unwrap(apiFetch<Envelope<GemLimits>>(`${url}/gem-limits`, { method: "PUT", body: JSON.stringify(patch) }));

export const listGemGrants = (filters: GemGrantFilters, limit: number, offset: number) => {
  const params = new URLSearchParams({ limit: String(limit), offset: String(offset) });
  Object.entries(filters).forEach(([k, v]) => v && params.set(k, v));
  return unwrap(apiFetch<Envelope<{ total: number; items: GemGrant[] }>>(`${url}/gem-grants?${params}`));
};
