import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { StatusPill } from "../StatusPill";
import { useAuth } from "../AuthProvider";
import { ReasonDialog } from "./ReasonDialog";
import { getUserEntitlement, grantPremium, revokePremium } from "../../lib/userSupportApi";
import { useI18n } from "../../lib/i18n";

const DURATIONS = [7, 30, 90, 365];
const failure = (err: unknown, fallback: string) => (err instanceof Error && err.message ? err.message : fallback);

export const UserPremiumPanel = ({ userId }: { userId: string }) => {
  const { t, locale } = useI18n();
  const { role } = useAuth();
  const queryClient = useQueryClient();
  const [dialog, setDialog] = useState<"grant" | "revoke" | null>(null);
  const [days, setDays] = useState(30);
  const [error, setError] = useState<string | null>(null);

  const entitlement = useQuery({ queryKey: ["support-entitlement", userId], queryFn: () => getUserEntitlement(userId) });
  const done = () => {
    setDialog(null);
    setError(null);
    queryClient.invalidateQueries({ queryKey: ["support-entitlement", userId] });
  };
  const grant = useMutation({
    mutationFn: (reason: string) => grantPremium(userId, { days, reason }),
    onSuccess: done,
    onError: (err) => setError(failure(err, t.support.grantFailed)),
  });
  const revoke = useMutation({
    mutationFn: (reason: string) => revokePremium(userId, { reason }),
    onSuccess: done,
    onError: (err) => setError(failure(err, t.support.revokeFailed)),
  });

  const e = entitlement.data;
  const adminGrant = e?.source === "admin";
  const paid = !!e && e.source !== "admin" && e.is_active;
  const expires = e?.expires_at ? new Date(e.expires_at).toLocaleDateString(locale === "vi" ? "vi-VN" : "en-GB") : "—";
  const isSuper = role === "super_admin";

  return (
    <div className="stack">
      {entitlement.error && <div className="form-error" role="alert">{failure(entitlement.error, t.support.loadFailed)}</div>}
      {entitlement.isLoading && <p className="text-muted">{t.common.loading}</p>}

      {e && (
        <div className="panel stack">
          <div className="cluster">
            <StatusPill tone={e.is_active ? "success" : "neutral"} label={e.is_active ? t.support.premiumActive : t.support.premiumInactive} />
            {e.force_enabled && <StatusPill tone="warning" label={t.support.forceEnabled} />}
          </div>
          <table className="kv-table">
            <tbody>
              <tr><th scope="row">{t.support.premiumSource}</th><td>{e.source ? (adminGrant ? t.support.sourceAdmin : t.support.sourceStore) : "—"}</td></tr>
              <tr><th scope="row">{t.support.premiumProduct}</th><td>{e.product_id || "—"}</td></tr>
              <tr><th scope="row">{t.support.premiumExpires}</th><td>{expires}</td></tr>
            </tbody>
          </table>
          {e.force_enabled && <p className="text-small text-muted">{t.support.forceEnabledHint}</p>}
          {paid && isSuper && <p className="text-small text-muted">{t.support.paidHint}</p>}
        </div>
      )}

      {isSuper && e && !paid && (
        <div className="cluster">
          <button className="primary-button" onClick={() => { setError(null); setDialog("grant"); }}>{t.support.grant}</button>
          {adminGrant && e.is_active && (
            <button className="ghost-button danger" onClick={() => { setError(null); setDialog("revoke"); }}>{t.support.revoke}</button>
          )}
        </div>
      )}

      {dialog === "grant" && (
        <ReasonDialog
          title={t.support.grantTitle}
          description={t.support.grantHint}
          confirmLabel={t.support.grant}
          busy={grant.isPending}
          error={error}
          onClose={() => setDialog(null)}
          onSubmit={(reason) => grant.mutate(reason)}
        >
          <label>
            {t.support.duration}
            <select value={days} onChange={(ev) => setDays(Number(ev.target.value))}>
              {DURATIONS.map((d) => <option key={d} value={d}>{d} {t.ops.days}</option>)}
            </select>
          </label>
        </ReasonDialog>
      )}
      {dialog === "revoke" && (
        <ReasonDialog
          title={t.support.revokeTitle}
          description={t.support.revokeHint}
          confirmLabel={t.support.revoke}
          danger
          busy={revoke.isPending}
          error={error}
          onClose={() => setDialog(null)}
          onSubmit={(reason) => revoke.mutate(reason)}
        />
      )}
    </div>
  );
};
