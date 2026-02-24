import React, { useEffect, useState, useCallback } from "react";
import { SectionHeader } from "../components/SectionHeader";
import { StatusPill } from "../components/StatusPill";
import { DataTable, Column } from "../components/DataTable";
import { getAuditLogs, AuditLogEntry } from "../lib/rbacApi";
import { useI18n } from "../lib/i18n";

const ACTION_TONES: Record<string, "success" | "warning" | "info" | "danger" | "neutral"> = {
  assign_role: "warning",
  deactivate: "danger",
  activate: "success",
  create: "info",
  delete: "danger",
  update: "info",
};

const fmtDate = (iso: string) => {
  const d = new Date(iso);
  return d.toLocaleString("vi-VN", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });
};

export const LogsPage = () => {
  const { t } = useI18n();
  const [logs, setLogs] = useState<AuditLogEntry[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [actionFilter, setActionFilter] = useState("");
  const [resourceFilter, setResourceFilter] = useState("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const perPage = 30;

  const fetchLogs = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await getAuditLogs({
        page,
        per_page: perPage,
        action: actionFilter || undefined,
        resource_type: resourceFilter || undefined,
      });
      setLogs(res.logs);
      setTotal(res.total);
    } catch (err: any) {
      setError(err?.message || t.logs.loadFailed);
    } finally {
      setLoading(false);
    }
  }, [page, actionFilter, resourceFilter]);

  useEffect(() => {
    fetchLogs();
  }, [fetchLogs]);

  const pages = Math.ceil(total / perPage);

  const columns: Column<AuditLogEntry>[] = [
    {
      header: t.logs.timestamp,
      render: (l) => <span className="mono text-small">{fmtDate(l.created_at)}</span>,
    },
    {
      header: t.logs.action,
      render: (l) => (
        <StatusPill tone={ACTION_TONES[l.action] || "neutral"} label={l.action} />
      ),
    },
    { header: t.logs.target, render: (l) => l.resource_type },
    {
      header: t.logs.resourceId,
      render: (l) => l.resource_id ? <span className="mono text-small">{l.resource_id.slice(0, 8)}…</span> : "—",
    },
    { header: t.logs.detail, render: (l) => l.details || "—" },
    {
      header: t.logs.adminId,
      render: (l) => l.user_id ? <span className="mono text-small">{l.user_id.slice(0, 8)}…</span> : "—",
    },
  ];

  return (
    <div className="stack">
      <SectionHeader
        title={t.logs.title}
        description={`${total} ${t.logs.description} • ${t.common.page} ${page}/${pages || 1}`}
      />

      <div className="filter-bar">
        <select
          className="filter-select"
          value={actionFilter}
          onChange={(e) => { setActionFilter(e.target.value); setPage(1); }}
        >
          <option value="">{t.logs.allActions}</option>
          <option value="assign_role">{t.logs.assignRole}</option>
          <option value="deactivate">{t.logs.deactivateAction}</option>
          <option value="activate">{t.logs.activateAction}</option>
          <option value="create">{t.logs.createAction}</option>
          <option value="update">{t.logs.updateAction}</option>
          <option value="delete">{t.logs.deleteAction}</option>
        </select>
        <select
          className="filter-select"
          value={resourceFilter}
          onChange={(e) => { setResourceFilter(e.target.value); setPage(1); }}
        >
          <option value="">{t.logs.allTargets}</option>
          <option value="user">User</option>
          <option value="course">Course</option>
          <option value="role">Role</option>
        </select>
      </div>

      {error && <div className="form-error">{error}</div>}

      <div className="panel">
        {loading ? (
          <div className="loading-text">{t.common.loading}</div>
        ) : logs.length === 0 ? (
          <div className="loading-text">{t.logs.noLogs}</div>
        ) : (
          <DataTable columns={columns} rows={logs} />
        )}
      </div>

      {pages > 1 && (
        <div className="pagination">
          <button disabled={page <= 1} onClick={() => setPage(page - 1)}>{t.common.prev}</button>
          <span className="page-info">{t.common.page} {page} / {pages}</span>
          <button disabled={page >= pages} onClick={() => setPage(page + 1)}>{t.common.next}</button>
        </div>
      )}
    </div>
  );
};
