import React, { useEffect, useState } from "react";
import { StatCard } from "../components/StatCard";
import { SectionHeader } from "../components/SectionHeader";
import { StatusPill } from "../components/StatusPill";
import { Skeleton } from "../components/Skeleton";
import { getMonitoringDashboard, MonitoringDashboard } from "../lib/aiApi";
import { getSystemInfo, type SystemInfo } from "../lib/adminApi";
import { checkBackendHealth, checkAiHealth } from "../lib/healthApi";
import { useI18n } from "../lib/i18n";

type HealthStatus = { status?: string; message?: string; version?: string; services?: Record<string, string> };

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
          <StatCard label={t.superDashboard.users} value="--" loading />
          <StatCard label={t.superDashboard.cpuMemory} value="--" accent="teal" loading />
          <StatCard label={t.superDashboard.diskUsage} value="--" accent="berry" loading />
          <StatCard label={t.superDashboard.systemHealth} value="--" accent="ink" loading />
        </div>
        <div className="grid-2 dashboard-grid-2">
          <div className="panel"><Skeleton height={260} /></div>
          <div className="panel"><Skeleton height={260} /></div>
        </div>
      </div>
    );
  }

  return (
    <div className="stack dashboard-view">
      <SectionHeader title={t.superDashboard.title} description={t.superDashboard.subtitle} />

      {/* Primary Stats */}
      <div className="card-grid dashboard-card-grid">
        <StatCard
          label={t.superDashboard.users}
          value={String(sysInfo?.totals.users || 0)}
          note={`${sysInfo?.totals.courses || 0} ${t.superDashboard.coursesCount}`}
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
          accent={healthy ? "teal" : "orange"}
          note={warnCount > 0 ? `${warnCount} ${t.superDashboard.warnings}` : undefined}
        />
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
            <div>
              <div className="mini-title">Gemini 2.0 Flash</div>
              <div className="mini-desc">Chat, Grammar, Topic • Cloud API</div>
            </div>
            <div>
              <div className="mini-title">Whisper Base</div>
              <div className="mini-desc">Speech-to-Text • Local CPU</div>
            </div>
            <div>
              <div className="mini-title">Piper TTS</div>
              <div className="mini-desc">Text-to-Speech • en_US-lessac</div>
            </div>
            <div>
              <div className="mini-title">TRACECAG</div>
              <div className="mini-desc">Knowledge Graph • Custom Pipeline</div>
            </div>
          </div>
        </div>
      </div>

      {/* System Config Quick View */}
      {sysInfo && (
        <div className="panel dashboard-config-panel">
          <h3>{t.superDashboard.quickConfig}</h3>
          <div className="dashboard-config-grid">
            <ConfigChip label="Env" value={sysInfo.app_env} />
            <ConfigChip label="Debug" value={sysInfo.debug ? "ON" : "OFF"} />
            <ConfigChip label="Log" value={sysInfo.log_level} />
            <ConfigChip label="Token" value={`${sysInfo.token_expire_minutes}m`} />
            <ConfigChip label="OAuth" value={sysInfo.google_oauth ? "YES" : "NO"} />
            <ConfigChip label="Firebase" value={sysInfo.firebase ? "YES" : "NO"} />
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

const ConfigChip = ({ label, value }: { label: string; value: string }) => (
  <span className="dashboard-config-chip">
    <span>{label}:</span>
    <strong>{value}</strong>
  </span>
);
