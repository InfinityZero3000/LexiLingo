import React, { useEffect, useState, useCallback } from "react";
import { SectionHeader } from "../components/SectionHeader";
import { StatusPill } from "../components/StatusPill";
import { DataTable, Column } from "../components/DataTable";
import { getAuditLogs, AuditLogEntry } from "../lib/rbacApi";

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
      setError(err?.message || "Không tải được audit logs");
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
      header: "Thời gian",
      render: (l) => <span className="mono text-small">{fmtDate(l.created_at)}</span>,
    },
    {
      header: "Hành động",
      render: (l) => (
        <StatusPill tone={ACTION_TONES[l.action] || "neutral"} label={l.action} />
      ),
    },
    { header: "Đối tượng", render: (l) => l.resource_type },
    {
      header: "Resource ID",
      render: (l) => l.resource_id ? <span className="mono text-small">{l.resource_id.slice(0, 8)}…</span> : "—",
    },
    { header: "Chi tiết", render: (l) => l.details || "—" },
    {
      header: "Admin ID",
      render: (l) => l.user_id ? <span className="mono text-small">{l.user_id.slice(0, 8)}…</span> : "—",
    },
  ];

  return (
    <div className="stack">
      <SectionHeader
        title="Audit Logs"
        description={`${total} bản ghi hành động admin • Trang ${page}/${pages || 1}`}
      />

      <div className="filter-bar">
        <select
          className="filter-select"
          value={actionFilter}
          onChange={(e) => { setActionFilter(e.target.value); setPage(1); }}
        >
          <option value="">Tất cả hành động</option>
          <option value="assign_role">Gán role</option>
          <option value="deactivate">Vô hiệu hoá</option>
          <option value="activate">Kích hoạt</option>
          <option value="create">Tạo mới</option>
          <option value="update">Cập nhật</option>
          <option value="delete">Xoá</option>
        </select>
        <select
          className="filter-select"
          value={resourceFilter}
          onChange={(e) => { setResourceFilter(e.target.value); setPage(1); }}
        >
          <option value="">Tất cả đối tượng</option>
          <option value="user">User</option>
          <option value="course">Course</option>
          <option value="role">Role</option>
        </select>
      </div>

      {error && <div className="form-error">{error}</div>}

      <div className="panel">
        {loading ? (
          <div className="loading-text">Đang tải...</div>
        ) : logs.length === 0 ? (
          <div className="loading-text">Chưa có bản ghi audit nào</div>
        ) : (
          <DataTable columns={columns} rows={logs} />
        )}
      </div>

      {pages > 1 && (
        <div className="pagination">
          <button disabled={page <= 1} onClick={() => setPage(page - 1)}>← Trước</button>
          <span className="page-info">Trang {page} / {pages}</span>
          <button disabled={page >= pages} onClick={() => setPage(page + 1)}>Sau →</button>
        </div>
      )}
    </div>
  );
};
