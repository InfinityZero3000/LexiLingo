import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { SectionHeader } from "../components/SectionHeader";
import { DataTable, Column } from "../components/DataTable";
import { Dialog } from "../components/Dialog";
import { EmptyState } from "../components/EmptyState";
import { StatusPill } from "../components/StatusPill";
import { TableSkeleton } from "../components/Skeleton";
import { useConfirm } from "../components/ConfirmDialog";
import { CreatedPartnerKey, PartnerKey, createPartnerKey, listPartnerKeys, revokePartnerKey } from "../lib/partnerKeysApi";
import { useI18n } from "../lib/i18n";

const LIFETIMES = [0, 30, 90, 365];
const messageOf = (err: unknown, fallback: string) => (err instanceof Error && err.message ? err.message : fallback);
const TONES = { active: "success", revoked: "danger", expired: "neutral" } as const;

export const PartnerKeysPage = () => {
  const { t, locale } = useI18n();
  const confirm = useConfirm();
  const queryClient = useQueryClient();
  const [creating, setCreating] = useState(false);
  const [owner, setOwner] = useState("");
  const [lifetime, setLifetime] = useState(90);
  const [formError, setFormError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [created, setCreated] = useState<CreatedPartnerKey | null>(null);
  const [copied, setCopied] = useState(false);

  const keys = useQuery({ queryKey: ["partner-keys"], queryFn: listPartnerKeys });
  const refresh = () => queryClient.invalidateQueries({ queryKey: ["partner-keys"] });

  const create = useMutation({
    mutationFn: (input: { owner: string; expires_in_days?: number }) => createPartnerKey(input),
    onSuccess: (key) => {
      setCreating(false);
      setOwner("");
      setFormError(null);
      setCopied(false);
      setCreated(key);
      refresh();
    },
    onError: (err) => setFormError(messageOf(err, t.partnerKeys.createFailed)),
  });
  const revoke = useMutation({
    mutationFn: (id: string) => revokePartnerKey(id),
    onMutate: () => setError(null),
    onSuccess: refresh,
    onError: (err) => setError(messageOf(err, t.partnerKeys.revokeFailed)),
  });

  const askRevoke = async (key: PartnerKey) => {
    const ok = await confirm({
      title: t.partnerKeys.revokeTitle,
      message: t.partnerKeys.revokeMessage.replace("{owner}", key.owner),
      confirmLabel: t.partnerKeys.revoke,
      danger: true,
      requireText: key.key_id,
    });
    if (ok) revoke.mutate(key.id);
  };

  const copy = async () => {
    if (!created) return;
    try {
      await navigator.clipboard.writeText(created.key);
      setCopied(true);
    } catch {
      setCopied(false);
    }
  };

  const date = (iso: string | null) =>
    iso ? new Date(iso).toLocaleDateString(locale === "vi" ? "vi-VN" : "en-GB") : "—";

  const columns: Column<PartnerKey>[] = [
    { header: t.partnerKeys.keyId, render: (k) => <span className="mono">{k.key_id}</span> },
    { header: t.partnerKeys.owner, sortValue: (k) => k.owner, render: (k) => k.owner },
    { header: t.partnerKeys.scope, render: (k) => k.scope },
    { header: t.common.status, align: "center", render: (k) => <StatusPill tone={TONES[k.status]} label={t.partnerKeys.statuses[k.status]} /> },
    { header: t.partnerKeys.created, sortValue: (k) => k.created_at ?? "", render: (k) => date(k.created_at) },
    { header: t.partnerKeys.expires, render: (k) => (k.expires_at ? date(k.expires_at) : t.partnerKeys.never) },
    {
      header: t.common.actions,
      align: "right",
      render: (k) =>
        k.status === "active" ? (
          <button className="ghost-button small danger" onClick={() => askRevoke(k)} disabled={revoke.isPending}>
            {t.partnerKeys.revoke}
          </button>
        ) : null,
    },
  ];

  return (
    <div className="stack">
      <SectionHeader
        title={t.partnerKeys.title}
        description={t.partnerKeys.description}
        action={<button className="primary-button" onClick={() => { setFormError(null); setCreating(true); }}>{t.partnerKeys.create}</button>}
      />

      {(error || keys.error) && <div className="form-error" role="alert">{error ?? messageOf(keys.error, t.partnerKeys.loadFailed)}</div>}

      <div className="panel">
        {keys.isLoading ? (
          <TableSkeleton rows={4} cols={6} />
        ) : (keys.data?.length ?? 0) === 0 ? (
          <EmptyState title={t.partnerKeys.emptyTitle} description={t.partnerKeys.emptyDescription} />
        ) : (
          <DataTable columns={columns} rows={keys.data!} rowKey={(k) => k.id} />
        )}
      </div>

      {creating && (
        <Dialog onClose={() => setCreating(false)} maxWidth={460}>
          <h3>{t.partnerKeys.create}</h3>
          <form
            className="form"
            onSubmit={(e) => {
              e.preventDefault();
              create.mutate({ owner: owner.trim(), expires_in_days: lifetime || undefined });
            }}
          >
            <label>
              {t.partnerKeys.owner}
              <input value={owner} onChange={(e) => setOwner(e.target.value)} minLength={2} maxLength={255} required />
              <span className="form-hint">{t.partnerKeys.ownerHint}</span>
            </label>
            <label>
              {t.partnerKeys.lifetime}
              <select value={lifetime} onChange={(e) => setLifetime(Number(e.target.value))}>
                {LIFETIMES.map((d) => (
                  <option key={d} value={d}>{d === 0 ? t.partnerKeys.never : `${d} ${t.ops.days}`}</option>
                ))}
              </select>
            </label>
            <p className="text-small text-muted">{t.partnerKeys.readOnlyNote}</p>
            {formError && <div className="form-error" role="alert">{formError}</div>}
            <div className="table-actions">
              <button type="button" className="ghost-button" onClick={() => setCreating(false)}>{t.common.cancel}</button>
              <button type="submit" className="primary-button" disabled={create.isPending || owner.trim().length < 2}>
                {create.isPending ? t.common.saving : t.common.create}
              </button>
            </div>
          </form>
        </Dialog>
      )}

      {created && (
        <Dialog onClose={() => setCreated(null)} maxWidth={560}>
          <h3>{t.partnerKeys.createdTitle}</h3>
          <div className="form-error" role="alert">{t.partnerKeys.shownOnce}</div>
          <label className="form">
            {t.partnerKeys.apiKey}
            <input readOnly value={created.key} className="mono" onFocus={(e) => e.currentTarget.select()} />
          </label>
          <p className="text-small text-muted">{t.partnerKeys.usage}</p>
          <div className="table-actions">
            <button className="ghost-button" onClick={copy}>{copied ? t.partnerKeys.copied : t.partnerKeys.copy}</button>
            <button className="primary-button" onClick={() => setCreated(null)}>{t.partnerKeys.done}</button>
          </div>
        </Dialog>
      )}
    </div>
  );
};
