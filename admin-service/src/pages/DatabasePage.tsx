import React, { useEffect, useState } from "react";
import { SectionHeader } from "../components/SectionHeader";
import { StatCard } from "../components/StatCard";
import { StatusPill } from "../components/StatusPill";
import { DataTable } from "../components/DataTable";
import { getSystemInfo, type SystemInfo } from "../lib/adminApi";
import { ENV } from "../lib/env";
import { useI18n } from "../lib/i18n";

type HealthStatus = { status: string; message?: string; version?: string };

const MIGRATIONS = [
  { id: "001", name: "add_rbac_system", description: "Hệ thống phân quyền RBAC", status: "applied" },
  { id: "002", name: "add_admin_content_and_seed_roles", description: "Nội dung admin & role mặc định", status: "applied" },
  { id: "003", name: "add_level_rank_system", description: "Hệ thống cấp bậc & rank", status: "applied" },
  { id: "004", name: "add_proficiency_assessment", description: "Bảng đánh giá trình độ", status: "applied" },
  { id: "005", name: "merge_level_rank_heads", description: "Merge migration heads", status: "applied" },
  { id: "006", name: "add_phase_3_vocabulary_srs", description: "Từ vựng & SRS tables", status: "applied" },
  { id: "007", name: "add_phase_4_gamification", description: "Gamification tables", status: "applied" },
];

export const DatabasePage = () => {
  const [info, setInfo] = useState<SystemInfo | null>(null);
  const [backendHealth, setBackendHealth] = useState<HealthStatus | null>(null);
  const [aiHealth, setAiHealth] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const { t } = useI18n();

  useEffect(() => {
    setLoading(true);
    const backendBase = ENV.backendUrl.replace("/api/v1", "");
    const aiBase = ENV.aiUrl.replace("/api/v1", "");

    Promise.allSettled([
      getSystemInfo(),
      fetch(`${backendBase}/health`).then((r) => r.json()),
      fetch(`${aiBase}/health`).then((r) => r.json()),
    ])
      .then(([sysRes, beRes, aiRes]) => {
        if (sysRes.status === "fulfilled") setInfo(sysRes.value.data || null);
        if (beRes.status === "fulfilled") setBackendHealth(beRes.value);
        if (aiRes.status === "fulfilled") setAiHealth(aiRes.value);
      })
      .finally(() => setLoading(false));
  }, []);

  if (loading) return <div className="loading">{t.common.loading}</div>;

  const tables = [
    { name: "users", label: t.database.users, count: info?.totals.users || 0 },
    { name: "courses", label: t.database.coursesLabel, count: info?.totals.courses || 0 },
    { name: "vocabulary_items", label: t.database.vocabLabel, count: info?.totals.vocabulary || 0 },
    { name: "achievements", label: t.database.achievementsLabel, count: info?.totals.achievements || 0 },
  ];

  const totalRecords = tables.reduce((s, t) => s + t.count, 0);
  const beOk = backendHealth?.status === "healthy";
  const aiOk = aiHealth?.status === "healthy" || aiHealth?.status === "ok";

  return (
    <div className="stack">
      <SectionHeader
        title={t.database.title}
        description={t.database.description}
      />

      {/* Connection Status Cards */}
      <div className="card-grid">
        <StatCard label="PostgreSQL" value={beOk ? t.common.connected : t.common.error} accent={beOk ? "teal" : "orange"} note="Backend Service" />
        <StatCard label="MongoDB" value={aiOk ? t.common.connected : t.common.error} accent={aiOk ? "teal" : "orange"} note="AI Service" />
        <StatCard label={t.database.totalRecords} value={totalRecords.toLocaleString()} accent="berry" />
        <StatCard label="Migrations" value={String(MIGRATIONS.length)} accent="ink" note={t.database.applied} />
      </div>

      {/* Connection Details */}
      <div className="grid-2">
        <div className="panel" style={{ padding: 20 }}>
          <h3 style={{ margin: "0 0 16px" }}>{t.database.backendDb}</h3>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <tbody>
              <ConfigRow label={t.database.statusLabel} value={<StatusPill tone={beOk ? "success" : "danger"} label={beOk ? t.common.healthy : t.common.offline} />} />
              <ConfigRow label={t.database.version} value={backendHealth?.version || "N/A"} />
              <ConfigRow label={t.database.environment} value={info?.app_env || "N/A"} />
              <ConfigRow label={t.database.engine} value="SQLAlchemy 2.0 Async" />
              <ConfigRow label={t.database.migrationTool} value="Alembic" />
            </tbody>
          </table>
        </div>

        <div className="panel" style={{ padding: 20 }}>
          <h3 style={{ margin: "0 0 16px" }}>{t.database.aiDb}</h3>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <tbody>
              <ConfigRow label={t.database.statusLabel} value={<StatusPill tone={aiOk ? "success" : "danger"} label={aiOk ? t.common.connected : t.common.offline} />} />
              <ConfigRow label="Redis Cache" value={
                <StatusPill
                  tone={aiHealth?.services?.redis === "connected" ? "success" : "warning"}
                  label={aiHealth?.services?.redis || "Unknown"}
                />
              } />
              <ConfigRow label={t.database.driver} value="Motor (async)" />
              <ConfigRow label={t.database.usageLabel} value="GraphCAG, Chat History, Analytics" />
            </tbody>
          </table>
        </div>
      </div>

      {/* Table Overview */}
      <div className="panel">
        <h3 style={{ padding: "16px 16px 0" }}>{t.database.tableOverview}</h3>
        <DataTable
          columns={[
            { header: t.database.tableCol, render: (r) => <span className="table-title">{r.name}</span> },
            { header: t.database.descriptionCol, render: (r) => <span className="table-meta">{r.label}</span> },
            { header: t.database.recordCount, render: (r) => <span style={{ fontWeight: 600 }}>{r.count.toLocaleString()}</span>, align: "center" },
          ]}
          rows={tables}
        />
      </div>

      {/* Migration History */}
      <div className="panel">
        <h3 style={{ padding: "16px 16px 0" }}>{t.database.migrationHistory}</h3>
        <DataTable
          columns={[
            { header: "#", render: (r) => <span className="table-meta">{r.id}</span>, align: "center" },
            { header: t.database.migrationCol, render: (r) => <span className="table-title" style={{ fontFamily: "monospace", fontSize: 13 }}>{r.name}</span> },
            { header: t.database.descriptionCol, render: (r) => <span className="table-meta">{r.description}</span> },
            { header: t.database.migrationStatus, render: (r) => <StatusPill tone="success" label={t.database.applied} />, align: "center" },
          ]}
          rows={MIGRATIONS}
        />
      </div>
    </div>
  );
};

const ConfigRow = ({ label, value }: { label: string; value: React.ReactNode }) => (
  <tr style={{ borderBottom: "1px solid var(--border, #eee)" }}>
    <td style={{ padding: "10px 12px", color: "var(--muted, #666)", width: "40%", fontSize: 14 }}>{label}</td>
    <td style={{ padding: "10px 12px", fontWeight: 500, fontSize: 14 }}>{value}</td>
  </tr>
);
