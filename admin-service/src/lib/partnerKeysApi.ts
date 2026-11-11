import { apiFetch } from "./api";
import { ENV } from "./env";

type Envelope<T> = { success: boolean; message?: string; data: T };

export type PartnerKey = {
  id: string;
  key_id: string;
  owner: string;
  scope: string;
  status: "active" | "revoked" | "expired";
  created_at: string | null;
  expires_at: string | null;
  revoked_at: string | null;
};

/** The create response is the only time the raw key exists. */
export type CreatedPartnerKey = PartnerKey & { key: string };

const base = () => `${ENV.backendUrl}/admin/partner-keys`;

export const listPartnerKeys = async () => (await apiFetch<Envelope<PartnerKey[]>>(base())).data;

export const createPartnerKey = async (input: { owner: string; expires_in_days?: number }) =>
  (await apiFetch<Envelope<CreatedPartnerKey>>(base(), { method: "POST", body: JSON.stringify(input) })).data;

export const revokePartnerKey = async (id: string) =>
  (await apiFetch<Envelope<PartnerKey>>(`${base()}/${id}/revoke`, { method: "POST" })).data;
