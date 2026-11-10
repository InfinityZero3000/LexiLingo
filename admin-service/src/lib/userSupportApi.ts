import { apiFetch } from "./api";
import { ENV } from "./env";

type Envelope<T> = { success: boolean; message?: string; data: T };

const base = (userId: string) => `${ENV.backendUrl}/admin/users/${encodeURIComponent(userId)}`;
const json = (body: unknown) => ({ method: "POST", body: JSON.stringify(body) });
const unwrap = async <T>(request: Promise<Envelope<T>>) => (await request).data;

/* ─── Wallet and XP ─── */

export type WalletTx = {
  id: string;
  type: string;
  amount: number;
  balance_after: number;
  source: string | null;
  description: string | null;
  created_at: string | null;
};

export type UserWallet = {
  balance: number;
  total_earned: number;
  total_spent: number;
  total: number;
  transactions: WalletTx[];
};

export const getUserWallet = (userId: string, limit: number, offset: number) =>
  unwrap(apiFetch<Envelope<UserWallet>>(`${base(userId)}/wallet?limit=${limit}&offset=${offset}`));

export const adjustUserWallet = (userId: string, body: { delta: number; reason: string }) =>
  unwrap(apiFetch<Envelope<{ balance: number; delta: number }>>(`${base(userId)}/wallet/adjust`, json(body)));

export type XpTx = {
  id: string;
  amount: number;
  base_amount: number;
  multiplier: number;
  source: string;
  source_detail: string | null;
  created_at: string | null;
};

export type UserXp = { total_xp: number; total: number; transactions: XpTx[] };

export const getUserXp = (userId: string, limit: number, offset: number) =>
  unwrap(apiFetch<Envelope<UserXp>>(`${base(userId)}/xp-transactions?limit=${limit}&offset=${offset}`));

export type InventoryItem = {
  id: string;
  name: string;
  item_type: string;
  quantity: number;
  is_active: boolean;
  expires_at: string | null;
  purchased_at: string | null;
};

export const getUserInventory = (userId: string) =>
  unwrap(apiFetch<Envelope<{ items: InventoryItem[] }>>(`${base(userId)}/inventory`));

/* ─── Premium ─── */

export type UserEntitlement = {
  entitlement_id: string;
  exists: boolean;
  is_active: boolean;
  status: string;
  source: string | null;
  product_id: string | null;
  expires_at: string | null;
  synced_at: string | null;
  force_enabled: boolean;
};

export const getUserEntitlement = (userId: string) =>
  unwrap(apiFetch<Envelope<UserEntitlement>>(`${base(userId)}/entitlements`));

export const grantPremium = (userId: string, body: { days: number; reason: string }) =>
  unwrap(apiFetch<Envelope<UserEntitlement>>(`${base(userId)}/entitlements/grant`, json(body)));

export const revokePremium = (userId: string, body: { reason: string }) =>
  unwrap(apiFetch<Envelope<UserEntitlement>>(`${base(userId)}/entitlements/revoke`, json(body)));
