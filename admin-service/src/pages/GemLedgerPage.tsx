import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { SectionHeader } from "../components/SectionHeader";
import { DataTable, Column } from "../components/DataTable";
import { EmptyState } from "../components/EmptyState";
import { Pagination } from "../components/Pagination";
import { StatCard } from "../components/StatCard";
import { StatusPill } from "../components/StatusPill";
import { TableSkeleton } from "../components/Skeleton";
import { GemGrant, getGemLimits, listGemGrants } from "../lib/gemLimitsApi";
import { useI18n } from "../lib/i18n";

const PAGE_SIZE = 20;
const messageOf = (err: unknown, fallback: string) => (err instanceof Error && err.message ? err.message : fallback);

export const GemLedgerPage = () => {
  const { t, locale } = useI18n();
  const [page, setPage] = useState(1);
  const [kind, setKind] = useState("");
  const [dateFrom, setDateFrom] = useState("");
  const [dateTo, setDateTo] = useState("");

  const limits = useQuery({ queryKey: ["gem-limits"], queryFn: getGemLimits });
  const grants = useQuery({
    queryKey: ["gem-grants", kind, dateFrom, dateTo, page],
    queryFn: () => listGemGrants({ kind, date_from: dateFrom, date_to: dateTo }, PAGE_SIZE, (page - 1) * PAGE_SIZE),
  });

  const usage = limits.data?.usage;
  const rows = grants.data?.items ?? [];
  const pages = Math.max(1, Math.ceil((grants.data?.total ?? 0) / PAGE_SIZE));
  const reset = (set: (v: string) => void) => (e: { target: { value: string } }) => {
    set(e.target.value);
    setPage(1);
  };

  const columns: Column<GemGrant>[] = [
    {
      header: t.gemLedger.when,
      sortValue: (g) => g.created_at ?? "",
      render: (g) => (g.created_at ? new Date(g.created_at).toLocaleString(locale === "vi" ? "vi-VN" : "en-GB") : "—"),
    },
    { header: t.gemLedger.actor, render: (g) => g.actor.username ?? "—" },
    { header: t.gemLedger.learner, render: (g) => g.user.email ?? g.user.username ?? "—" },
    { header: t.gemLedger.kind, align: "center", render: (g) => <StatusPill tone={g.kind === "gift" ? "success" : "info"} label={t.gemLedger.kinds[g.kind]} /> },
    { header: t.gemLedger.amount, align: "right", sortValue: (g) => g.amount, render: (g) => <span className={g.amount < 0 ? "text-danger" : undefined}>{g.amount > 0 ? `+${g.amount}` : g.amount}</span> },
    { header: t.gemLedger.reason, render: (g) => <span className="text-muted">{g.reason}</span> },
  ];

  return (
    <div className="stack">
      <SectionHeader title={t.gemLedger.title} description={t.gemLedger.description} />

      {usage && (
        <div className="card-grid">
          <StatCard label={t.gemLedger.maxPerAction} value={usage.max_per_action.toLocaleString()} />
          <StatCard label={t.gemLedger.spentToday} value={usage.spent_today.toLocaleString()} />
          <StatCard
            label={t.gemLedger.remainingToday}
            value={usage.remaining_today.toLocaleString()}
            note={t.gemLedger.ofBudget.replace("{budget}", usage.daily_budget.toLocaleString())}
          />
        </div>
      )}

      <div className="panel filter-panel">
        <div className="filter-bar">
          <select className="filter-select" value={kind} onChange={reset(setKind)} aria-label={t.gemLedger.kind}>
            <option value="">{t.gemLedger.allKinds}</option>
            <option value="gift">{t.gemLedger.kinds.gift}</option>
            <option value="adjust">{t.gemLedger.kinds.adjust}</option>
          </select>
          <label className="filter-date">
            <span>{t.logs.dateFrom}</span>
            <input type="date" value={dateFrom} onChange={reset(setDateFrom)} />
          </label>
          <label className="filter-date">
            <span>{t.logs.dateTo}</span>
            <input type="date" value={dateTo} onChange={reset(setDateTo)} />
          </label>
        </div>
      </div>

      {grants.error && <div className="form-error" role="alert">{messageOf(grants.error, t.gemLedger.loadFailed)}</div>}

      <div className="panel">
        {grants.isLoading ? (
          <TableSkeleton rows={6} cols={6} />
        ) : rows.length === 0 ? (
          <EmptyState title={t.gemLedger.emptyTitle} description={t.gemLedger.emptyDescription} />
        ) : (
          <DataTable columns={columns} rows={rows} rowKey={(g) => g.id} />
        )}
      </div>
      <Pagination page={page} pages={pages} total={grants.data?.total} onChange={setPage} />
    </div>
  );
};
