import React, { useEffect, useState } from "react";
import { Database, GitBranch, Layers, Server } from "lucide-react";
import { SectionHeader } from "../components/SectionHeader";
import { StatCard } from "../components/StatCard";
import { StatusPill } from "../components/StatusPill";
import { DataTable } from "../components/DataTable";
import { getSystemInfo, type SystemInfo } from "../lib/adminApi";
import { checkBackendHealth, checkAiHealth } from "../lib/healthApi";
import { useI18n } from "../lib/i18n";

type HealthStatus = { status: string; message?: string; version?: string };

export const DatabasePage = () => {
  const [info, setInfo] = useState<SystemInfo | null>(null);
  const [backendHealth, setBackendHealth] = useState<HealthStatus | null>(null);
  const [aiHealth, setAiHealth] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const { t } = useI18n();

  useEffect(() => {
    setLoading(true);

    Promise.allSettled([
      getSystemInfo(),
      checkBackendHealth().then((r) => r.json()),
      checkAiHealth().then((r) => r.json()),
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
  const migration = info?.migration;
  const revisions = (list?: string[] | null) => (list && list.length ? list.join(", ") : "—");
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
        <StatCard
          label="PostgreSQL"
          value={beOk ? t.common.connected : t.common.error}
          variant="blue"
          note="Backend Service"
          icon={<Database size={18} />}
        />
        <StatCard
          label="MongoDB"
          value={aiOk ? t.common.connected : t.common.error}
          accent={aiOk ? "teal" : "berry"}
          note="AI Service"
          icon={<Server size={18} />}
        />
        <StatCard
          label={t.database.totalRecords}
          value={totalRecords.toLocaleString()}
          variant="dark"
          icon={<Layers size={18} />}
        />
        <StatCard
          label="Migrations"
          value={migration?.up_to_date == null ? t.database.migrationUnknown : migration.up_to_date ? t.database.applied : t.database.migrationPending}
          accent={migration?.up_to_date === false ? "berry" : "teal"}
          icon={<GitBranch size={18} />}
        />
      </div>

      {/* Connection Details */}
      <div className="grid-2">
        <div className="panel panel--pad">
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12 }}>
            <h3 className="panel-title" style={{ margin: 0 }}>{t.database.backendDb}</h3>
            <StatusPill tone={beOk ? "success" : "danger"} label={beOk ? t.common.healthy : t.common.offline} />
          </div>
          <div className="stack" style={{ gap: 10 }}>
            <ConfigRow label={t.database.statusLabel} value={<StatusPill tone={beOk ? "success" : "danger"} label={beOk ? t.common.healthy : t.common.offline} />} />
            <ConfigRow label={t.database.version} value={backendHealth?.version || "N/A"} />
            <ConfigRow label={t.database.environment} value={<StatusPill tone="info" label={info?.app_env || "N/A"} />} />
            <ConfigRow label={t.database.engine} value="SQLAlchemy 2.0 Async" />
            <ConfigRow label={t.database.migrationTool} value="Alembic" />
          </div>
        </div>

        <div className="panel panel--pad">
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12 }}>
            <h3 className="panel-title" style={{ margin: 0 }}>{t.database.aiDb}</h3>
            <StatusPill tone={aiOk ? "success" : "danger"} label={aiOk ? t.common.connected : t.common.offline} />
          </div>
          <div className="stack" style={{ gap: 10 }}>
            <ConfigRow label={t.database.statusLabel} value={<StatusPill tone={aiOk ? "success" : "danger"} label={aiOk ? t.common.connected : t.common.offline} />} />
            <ConfigRow
              label="Redis Cache"
              value={
                <StatusPill
                  tone={aiHealth?.services?.redis === "connected" ? "success" : "warning"}
                  label={aiHealth?.services?.redis || "Unknown"}
                />
              }
            />
            <ConfigRow label={t.database.driver} value="Motor (async)" />
            <ConfigRow label={t.database.usageLabel} value="TRACECAG, Chat History, Analytics" />
          </div>
        </div>
      </div>

      {/* Table Overview */}
      <div className="panel">
        <h3 className="panel-heading">{t.database.tableOverview}</h3>
        <DataTable
          columns={[
            { header: t.database.tableCol, render: (r) => <span className="table-title mono">{r.name}</span> },
            { header: t.database.descriptionCol, render: (r) => <span className="table-meta">{r.label}</span> },
            {
              header: t.database.recordCount,
              render: (r) => <StatusPill tone="info" label={r.count.toLocaleString()} />,
              align: "center",
            },
          ]}
          rows={tables}
        />
      </div>

      {/* Migration state: what the database is at versus what the deployed code ships */}
      <div className="panel panel--pad">
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12 }}>
          <h3 className="panel-title" style={{ margin: 0 }}>{t.database.migrationHistory}</h3>
          <StatusPill
            tone={migration?.up_to_date == null ? "neutral" : migration.up_to_date ? "success" : "warning"}
            label={migration?.up_to_date == null ? t.database.migrationUnknown : migration.up_to_date ? t.database.applied : t.database.migrationPending}
          />
        </div>
        <div className="stack" style={{ gap: 10 }}>
          <ConfigRow label={t.database.migrationCurrent} value={<span className="mono text-small">{revisions(migration?.current)}</span>} />
          <ConfigRow label={t.database.migrationHead} value={<span className="mono text-small">{revisions(migration?.head)}</span>} />
          <ConfigRow
            label={t.database.migrationStatus}
            value={
              <StatusPill
                tone={migration?.up_to_date == null ? "neutral" : migration.up_to_date ? "success" : "warning"}
                label={migration?.up_to_date == null ? t.database.migrationUnknown : migration.up_to_date ? t.database.applied : t.database.migrationPending}
              />
            }
          />
        </div>
      </div>
    </div>
  );
};

const ConfigRow = ({ label, value }: { label: string; value: React.ReactNode }) => (
  <div
    style={{
      display: "flex",
      alignItems: "center",
      justifyContent: "space-between",
      gap: 12,
      flexWrap: "wrap",
      padding: "12px 16px",
      borderRadius: "var(--radius-inner)",
      background: "var(--panel-soft-2)",
      border: "1px solid var(--line)",
    }}
  >
    <span style={{ fontSize: 13, fontWeight: 500, color: "var(--muted)" }}>{label}</span>
    <span style={{ fontSize: 14, fontWeight: 600, color: "var(--text)" }}>{value}</span>
  </div>
);
