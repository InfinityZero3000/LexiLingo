import React, { useEffect, useState } from "react";
import { StatCard } from "../components/StatCard";
import { SectionHeader } from "../components/SectionHeader";
import { StatusPill } from "../components/StatusPill";
import { Skeleton } from "../components/Skeleton";
import { BentoRingGauge } from "../components/dashboard/BentoChartPrimitives";
import { getMonitoringDashboard, MonitoringDashboard } from "../lib/aiApi";
import { getSystemInfo, type SystemInfo } from "../lib/adminApi";
import { checkBackendHealth, checkAiHealth } from "../lib/healthApi";
import { useI18n } from "../lib/i18n";

type HealthStatus = { status?: string; message?: string; version?: string; services?: Record<string, string> };

const AI_MODELS = [
  {
    name: "Gemini 2.0 Flash",
    desc: "Chat, Grammar, Topic • Cloud API",
    runtime: "Cloud API",
    tone: "info" as const,
  },
  {
    name: "Whisper Base",
    desc: "Speech-to-Text • Local CPU",
    runtime: "Local CPU",
    tone: "success" as const,
  },
  {
    name: "Piper TTS",
    desc: "Text-to-Speech • en_US-lessac",
    runtime: "en_US-lessac",
    tone: "neutral" as const,
  },
  {
    name: "TRACECAG",
    desc: "Knowledge Graph • Custom Pipeline",
    runtime: "Knowledge Graph",
    tone: "info" as const,
  },
];

export const SuperAdminDashboard = () => {
  const [monitor, setMonitor] = useState<MonitoringDashboard | null>(null);
  const [sysInfo, setSysInfo] = useState<SystemInfo | null>(null);
  const [backendHealth, setBackendHealth] = useState<HealthStatus | null>(null);
  const [aiHealth, setAiHealth] = useState<HealthStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const { t } = useI18n();

  useEffect(() => {
    setLoading(true);

    Promise.allSettled([
      getMonitoringDashboard(),
      getSystemInfo(),
      checkBackendHealth().then((r) => r.json()),
      checkAiHealth().then((r) => r.json()),
    ])
      .then(([monRes, sysRes, beRes, aiRes]) => {
        if (monRes.status === "fulfilled") setMonitor(monRes.value);
        if (sysRes.status === "fulfilled") setSysInfo(sysRes.value.data || null);
        if (beRes.status === "fulfilled") setBackendHealth(beRes.value);
        if (aiRes.status === "fulfilled") setAiHealth(aiRes.value);
      })
      .finally(() => setLoading(false));
  }, []);

  const healthy = monitor?.health?.healthy;
  const sys = monitor?.system;
  const cpuPercent = sys ? (sys.cpu_percent ?? sys.cpu?.percent) : undefined;
  const memoryPercent = sys ? (sys.memory_percent ?? sys.memory?.percent) : undefined;
  const diskPercent = sys ? (sys.disk_percent ?? sys.disk?.percent) : undefined;

  const beOk = backendHealth?.status === "healthy";
  const aiOk = aiHealth?.status === "healthy" || aiHealth?.status === "ok";
  const warnCount = monitor?.health?.warning_count || 0;
  const critCount = monitor?.health?.critical_count || 0;

  if (loading) {
    return (
      <div className="stack dashboard-view">
        <SectionHeader title={t.superDashboard.title} description={t.superDashboard.loadingDashboard} />
        <div className="card-grid dashboard-card-grid">
          <StatCard label={t.superDashboard.users} value="--" variant="blue" loading />
          <StatCard label={t.superDashboard.cpuMemory} value="--" accent="teal" loading />
          <StatCard label={t.superDashboard.diskUsage} value="--" accent="berry" loading />
          <StatCard label={t.superDashboard.systemHealth} value="--" variant="dark" accent="ink" loading />
        </div>
        <div className="grid-2 dashboard-grid-2">
          <div className="panel"><Skeleton height={260} /></div>
          <div className="panel"><Skeleton height={260} /></div>
        </div>
      </div>
    );
  }

  const ringItems = [
    {
      label: "CPU",
      value: cpuPercent ?? 0,
      display: cpuPercent !== undefined ? `${cpuPercent.toFixed(0)}%` : "--",
      tone: (cpuPercent && cpuPercent > 80 ? "amber" : "blue") as "amber" | "blue",
      detail: cpuPercent !== undefined ? (cpuPercent > 80 ? "High load" : "Nominal") : "Awaiting telemetry",
    },
    {
      label: "Memory",
      value: memoryPercent ?? 0,
      display: memoryPercent !== undefined ? `${memoryPercent.toFixed(0)}%` : "--",
      tone: (memoryPercent && memoryPercent > 85 ? "amber" : "lime") as "amber" | "lime",
      detail: memoryPercent !== undefined ? (memoryPercent > 85 ? "Elevated" : "Healthy") : "Awaiting telemetry",
    },
    {
      label: "Disk",
      value: diskPercent ?? 0,
      display: diskPercent !== undefined ? `${diskPercent.toFixed(1)}%` : "--",
      tone: (diskPercent && diskPercent > 90 ? "amber" : "indigo") as "amber" | "indigo",
      detail: diskPercent !== undefined ? (diskPercent > 90 ? "Near capacity" : "Available") : "Awaiting telemetry",
    },
  ];

  return (
    <div className="stack dashboard-view">
      <SectionHeader title={t.superDashboard.title} description={t.superDashboard.subtitle} />

      {/* Primary Stats */}
      <div className="card-grid dashboard-card-grid">
        <StatCard
          label={t.superDashboard.users}
          value={String(sysInfo?.totals.users || 0)}
          note={`${sysInfo?.totals.courses || 0} ${t.superDashboard.coursesCount}`}
          variant="blue"
          accent="orange"
        />
        <StatCard
          label={t.superDashboard.cpuMemory}
          value={cpuPercent !== undefined && memoryPercent !== undefined ? `${cpuPercent.toFixed(0)}% / ${memoryPercent.toFixed(0)}%` : "--"}
          accent={cpuPercent && cpuPercent > 80 ? "orange" : "teal"}
        />
        <StatCard
          label={t.superDashboard.diskUsage}
          value={diskPercent !== undefined ? `${diskPercent.toFixed(1)}%` : "--"}
          accent={diskPercent && diskPercent > 90 ? "orange" : "berry"}
        />
        <StatCard
          label={t.superDashboard.systemHealth}
          value={healthy === undefined ? "--" : healthy ? t.common.healthy : `${critCount} ${t.superDashboard.errors}`}
          variant={healthy ? "dark" : "dark"}
          accent={healthy ? "teal" : "orange"}
          note={warnCount > 0 ? `${warnCount} ${t.superDashboard.warnings}` : undefined}
        />
      </div>

      {/* Bento Resource Ring Row */}
      <div className="panel bento-card--dark">
        <SectionHeader
          title={`${t.superDashboard.cpuMemory} & ${t.superDashboard.diskUsage}`}
          description={t.superDashboard.systemHealth}
          action={
            <StatusPill
              tone={healthy === false ? "danger" : warnCount > 0 ? "warning" : "success"}
              label={healthy === undefined ? t.common.unknown : healthy ? t.common.healthy : `${critCount} ${t.superDashboard.errors}`}
            />
          }
        />
        <div
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(auto-fit, minmax(190px, 1fr))",
            gap: 16,
          }}
        >
          {ringItems.map((item) => (
            <div
              key={item.label}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 16,
                padding: "14px 16px",
                borderRadius: 18,
                background: "rgba(255, 255, 255, 0.04)",
                border: "1px solid rgba(255, 255, 255, 0.08)",
              }}
            >
              <BentoRingGauge
                value={item.value}
                centerPrimary={item.display}
                centerSecondary={item.label}
                tone={item.tone}
                dark
                size={88}
                strokeWidth={9}
              />
              <div style={{ minWidth: 0 }}>
                <div style={{ fontWeight: 700, fontSize: 14, color: "#F8FAFC" }}>{item.label}</div>
                <div style={{ fontSize: 12, color: "#94A3B8", marginTop: 2 }}>{item.detail}</div>
              </div>
            </div>
          ))}
        </div>
      </div>

      <div className="grid-2 dashboard-grid-2">
        {/* Service Status */}
        <div className="panel">
          <SectionHeader title={t.superDashboard.serviceStatus} description={t.superDashboard.serviceStatusDesc} />
          <div className="pill-grid">
            <div className="pill-item">
              <div>
                <div className="pill-title">{t.superDashboard.backendApi}</div>
                <div className="pill-desc">FastAPI • {backendHealth?.version || "v?"}</div>
              </div>
              <StatusPill tone={beOk ? "success" : "danger"} label={beOk ? t.common.healthy : t.common.offline} />
            </div>
            <div className="pill-item">
              <div>
                <div className="pill-title">{t.superDashboard.aiService}</div>
                <div className="pill-desc">FastAPI • Gemini + Voice</div>
              </div>
              <StatusPill tone={aiOk ? "success" : "danger"} label={aiOk ? t.common.online : t.common.offline} />
            </div>
            <div className="pill-item">
              <div>
                <div className="pill-title">{t.superDashboard.postgresql}</div>
                <div className="pill-desc">{t.superDashboard.backendDatabase}</div>
              </div>
              <StatusPill tone={beOk ? "success" : "warning"} label={beOk ? t.common.connected : t.common.unknown} />
            </div>
            <div className="pill-item">
              <div>
                <div className="pill-title">{t.superDashboard.mongodb}</div>
                <div className="pill-desc">{t.superDashboard.aiDataStore}</div>
              </div>
              <StatusPill
                tone={aiHealth?.services?.mongodb === "connected" ? "success" : "warning"}
                label={aiHealth?.services?.mongodb || "Unknown"}
              />
            </div>
            {aiHealth?.services?.redis && (
              <div className="pill-item">
                <div>
                  <div className="pill-title">{t.superDashboard.redis}</div>
                  <div className="pill-desc">{t.superDashboard.cacheLayer}</div>
                </div>
                <StatusPill
                  tone={aiHealth.services.redis === "connected" ? "success" : "warning"}
                  label={aiHealth.services.redis}
                />
              </div>
            )}
          </div>
        </div>

        {/* AI Models */}
        <div className="panel">
          <SectionHeader title={t.superDashboard.aiModels} description={t.superDashboard.aiModelsDesc} />
          <div className="mini-list">
            {AI_MODELS.map((model) => (
              <div className="pill-item" key={model.name} style={{ gap: 12 }}>
                <div style={{ minWidth: 0 }}>
                  <div className="mini-title">{model.name}</div>
                  <div className="mini-desc">{model.desc}</div>
                </div>
                <StatusPill tone={model.tone} label={model.runtime} />
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* System Config Quick View */}
      {sysInfo && (
        <div className="panel dashboard-config-panel">
          <h3>{t.superDashboard.quickConfig}</h3>
          <div className="dashboard-config-grid">
            <ConfigChip label="Env" value={sysInfo.app_env} />
            <ConfigChip label="Debug" value={sysInfo.debug ? "ON" : "OFF"} active={sysInfo.debug} />
            <ConfigChip label="Log" value={sysInfo.log_level} />
            <ConfigChip label="Token" value={`${sysInfo.token_expire_minutes}m`} />
            <ConfigChip label="OAuth" value={sysInfo.google_oauth ? "YES" : "NO"} active={sysInfo.google_oauth} />
            <ConfigChip label="Firebase" value={sysInfo.firebase ? "YES" : "NO"} active={sysInfo.firebase} />
          </div>
        </div>
      )}

      {/* System Warnings */}
      {monitor?.health?.warnings && monitor.health.warnings.length > 0 && (
        <div className="panel dashboard-warning">
          <h4>{t.superDashboard.systemWarnings}</h4>
          {monitor.health.warnings.map((w, i) => (
            <p key={i}>{w.message}</p>
          ))}
        </div>
      )}
    </div>
  );
};

const ConfigChip = ({ label, value, active }: { label: string; value: string; active?: boolean }) => (
  <span
    className="dashboard-config-chip"
    style={{
      border: "1px solid var(--line)",
      borderRadius: 12,
      padding: "10px 14px",
    }}
  >
    <span>{label}</span>
    <strong style={active ? { color: "var(--ink-teal)" } : undefined}>{value}</strong>
  </span>
);
