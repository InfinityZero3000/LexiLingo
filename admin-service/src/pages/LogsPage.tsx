import { useState } from "react";
import { useQuery, keepPreviousData } from "@tanstack/react-query";
import { SectionHeader } from "../components/SectionHeader";
import { StatusPill } from "../components/StatusPill";
import { DataTable, Column } from "../components/DataTable";
import { EmptyState } from "../components/EmptyState";
import { TableSkeleton } from "../components/Skeleton";
import { Pagination } from "../components/Pagination";
import { getAuditLogs, getAuditFacets, exportAuditLogs, AuditLogEntry, AuditQuery } from "../lib/rbacApi";
import { useI18n } from "../lib/i18n";

type Tone = "success" | "warning" | "info" | "danger" | "neutral";

const DANGEROUS = /(delete|deactivate|denied|failed|revoke)/;
const ACTION_TONES: Record<string, Tone> = {
  create: "info",
  update: "info",
  activate: "success",
  login: "success",
  assign_role: "warning",
  gift: "warning",
  wallet_adjust: "warning",
  premium_grant: "warning",
  quota_reset: "warning",
};
const toneOf = (action: string): Tone => (DANGEROUS.test(action) ? "danger" : ACTION_TONES[action] || "neutral");

const PER_PAGE = 30;

const emptyFilters = { action: "", resource_type: "", q: "", date_from: "", date_to: "" };

export const LogsPage = () => {
  const { t, locale } = useI18n();
  const [filters, setFilters] = useState(emptyFilters);
  const [searchText, setSearchText] = useState("");
  const [page, setPage] = useState(1);
  const [exporting, setExporting] = useState(false);
  const [exportError, setExportError] = useState<string | null>(null);

  const query: AuditQuery = {
    action: filters.action || undefined,
    resource_type: filters.resource_type || undefined,
    q: filters.q || undefined,
    date_from: filters.date_from ? `${filters.date_from}T00:00:00` : undefined,
    date_to: filters.date_to ? `${filters.date_to}T23:59:59` : undefined,
  };

  const logsQuery = useQuery({
    queryKey: ["audit-logs", query, page],
    queryFn: () => getAuditLogs({ ...query, page, per_page: PER_PAGE }),
    placeholderData: keepPreviousData,
  });
  const facets = useQuery({ queryKey: ["audit-facets"], queryFn: getAuditFacets, staleTime: 60_000 });

  const logs = logsQuery.data?.logs ?? [];
  const total = logsQuery.data?.total ?? 0;
  const pages = Math.ceil(total / PER_PAGE);
  const labels = t.logs.actionLabels;
  const label = (action: string) => labels[action] ?? action;
  const dateLocale = locale === "vi" ? "vi-VN" : "en-GB";
  const filtered = Object.values(filters).some(Boolean);

  const update = (patch: Partial<typeof emptyFilters>) => {
    setFilters((prev) => ({ ...prev, ...patch }));
    setPage(1);
  };

  const exportCsv = async () => {
    setExporting(true);
    setExportError(null);
    try {
      const csv = await exportAuditLogs(query);
      const blob = new Blob(["﻿", csv], { type: "text/csv;charset=utf-8" });
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = `audit-logs-${new Date().toISOString().slice(0, 10)}.csv`;
      link.click();
      URL.revokeObjectURL(url);
    } catch (err: any) {
      setExportError(err?.message || t.logs.exportFailed);
    } finally {
      setExporting(false);
    }
  };

  const columns: Column<AuditLogEntry>[] = [
    {
      header: t.logs.timestamp,
      render: (l) => (
        <span className="mono text-small">
          {new Date(l.created_at).toLocaleString(dateLocale, {
            day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit",
          })}
        </span>
      ),
    },
    { header: t.logs.action, render: (l) => <StatusPill tone={toneOf(l.action)} label={label(l.action)} /> },
    {
      header: t.logs.actorCol,
      render: (l) =>
        l.actor?.username || l.actor?.email ? (
          <span title={l.actor.email ?? undefined}>{l.actor.username || l.actor.email}</span>
        ) : (
          <span className="text-muted">{t.logs.systemActor}</span>
        ),
    },
    { header: t.logs.target, render: (l) => l.resource_type },
    {
      header: t.logs.resourceId,
      render: (l) =>
        l.resource_id ? <span className="mono text-small" title={l.resource_id}>{l.resource_id.slice(0, 8)}…</span> : "—",
    },
    { header: t.logs.detail, render: (l) => l.details || "—" },
    { header: t.logs.ipCol, render: (l) => (l.ip_address ? <span className="mono text-small">{l.ip_address}</span> : "—") },
  ];

  const error = logsQuery.error ? (logsQuery.error as Error).message || t.logs.loadFailed : null;

  return (
    <div className="stack">
      <SectionHeader
        title={t.logs.title}
        description={`${total} ${t.logs.description}`}
        action={
          <button className="ghost-button" onClick={exportCsv} disabled={exporting || total === 0}>
            {exporting ? t.logs.exporting : t.logs.exportCsv}
          </button>
        }
      />

      <div className="panel filter-panel">
        <div className="filter-bar">
          <form
            className="filter-search-form"
            onSubmit={(e) => {
              e.preventDefault();
              update({ q: searchText.trim() });
            }}
          >
            <input
              className="search-input"
              type="search"
              value={searchText}
              onChange={(e) => setSearchText(e.target.value)}
              placeholder={t.logs.searchPlaceholder}
              aria-label={t.common.search}
            />
            <button type="submit" className="primary-button">{t.common.search}</button>
          </form>

          <select
            className="filter-select"
            aria-label={t.logs.action}
            value={filters.action}
            onChange={(e) => update({ action: e.target.value })}
          >
            <option value="">{t.logs.allActions}</option>
            {(facets.data?.actions ?? []).map((a) => (
              <option key={a} value={a}>{label(a)}</option>
            ))}
          </select>

          <select
            className="filter-select"
            aria-label={t.logs.target}
            value={filters.resource_type}
            onChange={(e) => update({ resource_type: e.target.value })}
          >
            <option value="">{t.logs.allTargets}</option>
            {(facets.data?.resource_types ?? []).map((r) => (
              <option key={r} value={r}>{r}</option>
            ))}
          </select>

          <label className="filter-date">
            <span>{t.logs.dateFrom}</span>
            <input type="date" value={filters.date_from} onChange={(e) => update({ date_from: e.target.value })} />
          </label>
          <label className="filter-date">
            <span>{t.logs.dateTo}</span>
            <input type="date" value={filters.date_to} onChange={(e) => update({ date_to: e.target.value })} />
          </label>

          {filtered && (
            <button
              className="ghost-button"
              onClick={() => {
                setFilters(emptyFilters);
                setSearchText("");
                setPage(1);
              }}
            >
              {t.logs.clearFilters}
            </button>
          )}
        </div>
      </div>

      {error && <div className="form-error" role="alert">{error}</div>}
      {exportError && <div className="form-error" role="alert">{exportError}</div>}

      <div className="panel">
        {logsQuery.isLoading ? (
          <TableSkeleton rows={8} cols={7} />
        ) : logs.length === 0 ? (
          <EmptyState title={t.logs.noLogs} description={t.logs.noLogsDesc} />
        ) : (
          <DataTable columns={columns} rows={logs} rowKey={(l) => l.id} />
        )}
      </div>

      <Pagination page={page} pages={pages} total={total} onChange={setPage} />
    </div>
  );
};
