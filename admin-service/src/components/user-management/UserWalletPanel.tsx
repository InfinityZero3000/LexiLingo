import { useState } from "react";
import { useMutation, useQuery, useQueryClient, keepPreviousData } from "@tanstack/react-query";
import { DataTable, Column } from "../DataTable";
import { EmptyState } from "../EmptyState";
import { Pagination } from "../Pagination";
import { StatCard } from "../StatCard";
import { TableSkeleton } from "../Skeleton";
import { useAuth } from "../AuthProvider";
import { ReasonDialog } from "./ReasonDialog";
import {
  adjustUserWallet, getUserInventory, getUserWallet, getUserXp, InventoryItem, WalletTx, XpTx,
} from "../../lib/userSupportApi";
import { useI18n } from "../../lib/i18n";

const PAGE = 10;
type View = "gems" | "xp" | "items";

const when = (iso: string | null, locale: string) =>
  iso ? new Date(iso).toLocaleString(locale === "vi" ? "vi-VN" : "en-GB", { dateStyle: "short", timeStyle: "short" }) : "—";

const signed = (n: number) => (n > 0 ? `+${n}` : String(n));
const failure = (err: unknown, fallback: string) => (err instanceof Error && err.message ? err.message : fallback);

export const UserWalletPanel = ({ userId }: { userId: string }) => {
  const { t, locale } = useI18n();
  const { role } = useAuth();
  const queryClient = useQueryClient();
  const [view, setView] = useState<View>("gems");
  const [page, setPage] = useState(1);
  const [adjusting, setAdjusting] = useState(false);
  const [delta, setDelta] = useState("");
  const [error, setError] = useState<string | null>(null);

  const offset = (page - 1) * PAGE;
  const wallet = useQuery({
    queryKey: ["support-wallet", userId, page], queryFn: () => getUserWallet(userId, PAGE, offset),
    enabled: view === "gems", placeholderData: keepPreviousData,
  });
  const xp = useQuery({
    queryKey: ["support-xp", userId, page], queryFn: () => getUserXp(userId, PAGE, offset),
    enabled: view === "xp", placeholderData: keepPreviousData,
  });
  const inventory = useQuery({ queryKey: ["support-inventory", userId], queryFn: () => getUserInventory(userId), enabled: view === "items" });

  const adjust = useMutation({
    mutationFn: (body: { delta: number; reason: string }) => adjustUserWallet(userId, body),
    onSuccess: () => {
      setAdjusting(false);
      setDelta("");
      setError(null);
      queryClient.invalidateQueries({ queryKey: ["support-wallet", userId] });
    },
    onError: (err) => setError(failure(err, t.support.adjustFailed)),
  });

  const amount = Number(delta);
  const validDelta = Number.isInteger(amount) && amount !== 0;

  const walletColumns: Column<WalletTx>[] = [
    { header: t.support.time, render: (r) => <span className="mono text-small">{when(r.created_at, locale)}</span> },
    { header: t.support.source, render: (r) => r.source || r.type },
    { header: t.support.amount, align: "right", render: (r) => <strong className={r.amount < 0 ? "text-danger" : undefined}>{signed(r.amount)}</strong> },
    { header: t.support.balanceAfter, align: "right", render: (r) => r.balance_after },
    { header: t.support.note, render: (r) => r.description || "—" },
  ];
  const xpColumns: Column<XpTx>[] = [
    { header: t.support.time, render: (r) => <span className="mono text-small">{when(r.created_at, locale)}</span> },
    { header: t.support.source, render: (r) => [r.source, r.source_detail].filter(Boolean).join(" · ") },
    { header: t.support.amount, align: "right", render: (r) => <strong>{signed(r.amount)}</strong> },
    { header: t.support.multiplier, align: "right", render: (r) => `×${r.multiplier}` },
  ];
  const itemColumns: Column<InventoryItem>[] = [
    { header: t.support.item, render: (r) => r.name },
    { header: t.support.itemType, render: (r) => r.item_type },
    { header: t.support.quantity, align: "right", render: (r) => r.quantity },
    { header: t.support.expires, render: (r) => when(r.expires_at, locale) },
  ];

  const active = view === "gems" ? wallet : view === "xp" ? xp : inventory;
  const total = view === "gems" ? wallet.data?.total ?? 0 : view === "xp" ? xp.data?.total ?? 0 : 0;

  return (
    <div className="stack">
      <div className="card-grid">
        <StatCard label={t.support.balance} value={String(wallet.data?.balance ?? "—")} accent="teal" loading={wallet.isLoading} />
        <StatCard label={t.support.earned} value={String(wallet.data?.total_earned ?? "—")} accent="ink" loading={wallet.isLoading} />
        <StatCard label={t.support.spent} value={String(wallet.data?.total_spent ?? "—")} accent="ink" loading={wallet.isLoading} />
        <StatCard label={t.support.totalXp} value={String(xp.data?.total_xp ?? "—")} accent="orange" loading={xp.isLoading && view === "xp"} />
      </div>

      <div className="cluster cluster--between">
        <div className="tab-row" role="tablist">
          {(["gems", "xp", "items"] as const).map((v) => (
            <button
              key={v} role="tab" aria-selected={view === v}
              className={`tab ${view === v ? "active" : ""}`}
              onClick={() => { setView(v); setPage(1); }}
            >
              {t.support[`view_${v}` as const]}
            </button>
          ))}
        </div>
        {role === "super_admin" && view === "gems" && (
          <button className="ghost-button" onClick={() => { setError(null); setAdjusting(true); }}>{t.support.adjust}</button>
        )}
      </div>

      {active.error && <div className="form-error" role="alert">{failure(active.error, t.support.loadFailed)}</div>}

      {active.isLoading ? (
        <TableSkeleton rows={4} cols={4} />
      ) : view === "gems" ? (
        (wallet.data?.transactions.length ?? 0) === 0 ? <EmptyState title={t.support.noTransactions} /> :
          <DataTable columns={walletColumns} rows={wallet.data!.transactions} rowKey={(r) => r.id} />
      ) : view === "xp" ? (
        (xp.data?.transactions.length ?? 0) === 0 ? <EmptyState title={t.support.noXp} /> :
          <DataTable columns={xpColumns} rows={xp.data!.transactions} rowKey={(r) => r.id} />
      ) : (inventory.data?.items.length ?? 0) === 0 ? (
        <EmptyState title={t.support.noItems} />
      ) : (
        <DataTable columns={itemColumns} rows={inventory.data!.items} rowKey={(r) => r.id} />
      )}

      {view !== "items" && <Pagination page={page} pages={Math.ceil(total / PAGE)} total={total} onChange={setPage} />}

      {adjusting && (
        <ReasonDialog
          title={t.support.adjustTitle}
          description={t.support.adjustHint}
          confirmLabel={t.support.adjustConfirm}
          busy={adjust.isPending}
          error={error}
          canSubmit={validDelta}
          onClose={() => setAdjusting(false)}
          onSubmit={(reason) => adjust.mutate({ delta: amount, reason })}
        >
          <label>
            {t.support.deltaLabel}
            <input type="number" step={1} value={delta} onChange={(e) => setDelta(e.target.value)} required />
          </label>
        </ReasonDialog>
      )}
    </div>
  );
};
