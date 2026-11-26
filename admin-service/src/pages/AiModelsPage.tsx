import React, { useEffect, useState } from "react";
import { Activity, AlertTriangle, Bot, Cpu, HardDrive } from "lucide-react";
import { SectionHeader } from "../components/SectionHeader";
import { StatCard } from "../components/StatCard";
import { StatusPill } from "../components/StatusPill";
import { LiveAiModels } from "../components/LiveAiModels";
import { getLlmKeyMonitoring, getMonitoringDashboard, type LlmKeyMonitoring, type MonitoringDashboard } from "../lib/aiApi";
import { useI18n } from "../lib/i18n";

export const AiModelsPage = () => {
  const [monitor, setMonitor] = useState<MonitoringDashboard | null>(null);
  const [llm, setLlm] = useState<LlmKeyMonitoring | null>(null);
  const [loading, setLoading] = useState(true);
  const { t } = useI18n();

  useEffect(() => {
    setLoading(true);

    Promise.allSettled([
      getMonitoringDashboard(),
      getLlmKeyMonitoring(),
    ])
      .then(([monRes, llmRes]) => {
        if (monRes.status === "fulfilled") setMonitor(monRes.value);
        if (llmRes.status === "fulfilled") setLlm(llmRes.value);
      })
      .finally(() => setLoading(false));
  }, []);

  if (loading) return <div className="loading">{t.common.loading}</div>;

  const sys = monitor?.system;
  const cpuPercent = sys ? (sys.cpu_percent ?? sys.cpu?.percent) : undefined;
  const memoryPercent = sys ? (sys.memory_percent ?? sys.memory?.percent) : undefined;
  const diskPercent = sys ? (sys.disk_percent ?? sys.disk?.percent) : undefined;
  const proc = monitor?.process;
  const aiOk = monitor !== null;
  const warnings = monitor?.health?.warnings || [];

  return (
    <div className="stack">
      <SectionHeader
        title={t.aiModelsPage.title}
        description={t.aiModelsPage.description}
      />

      {/* System Resource Cards */}
      <div className="card-grid">
        <StatCard
          label={t.aiModelsPage.aiService}
          value={aiOk ? t.common.online : t.common.offline}
          variant="blue"
          icon={<Bot size={18} />}
        />
        <StatCard
          label={t.aiModelsPage.cpuUsage}
          value={cpuPercent !== undefined ? `${cpuPercent.toFixed(1)}%` : "--"}
          accent={cpuPercent && cpuPercent > 80 ? "berry" : "teal"}
          icon={<Cpu size={18} />}
        />
        <StatCard
          label={t.aiModelsPage.memory}
          value={memoryPercent !== undefined ? `${memoryPercent.toFixed(1)}%` : "--"}
          accent={memoryPercent && memoryPercent > 80 ? "berry" : "teal"}
          icon={<Activity size={18} />}
        />
        <StatCard
          label={t.aiModelsPage.disk}
          value={diskPercent !== undefined ? `${diskPercent.toFixed(1)}%` : "--"}
          variant="dark"
          icon={<HardDrive size={18} />}
        />
      </div>

      {/* Warnings */}
      {warnings.length > 0 && (
        <div
          className="panel"
          style={{
            padding: 18,
            background: "rgba(245, 158, 11, 0.1)",
            border: "1px solid rgba(245, 158, 11, 0.32)",
            gap: 8,
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: 8, color: "var(--warn)" }}>
            <AlertTriangle size={18} />
            <h4 style={{ margin: 0 }}>{t.aiModelsPage.warningsTitle} ({warnings.length})</h4>
          </div>
          {warnings.map((w, i) => (
            <p key={i} style={{ margin: 0, fontSize: 13, color: "var(--text)" }}>{w.message}</p>
          ))}
        </div>
      )}

      {/* AI Models */}
      <div className="panel panel--pad">
        <h3 className="panel-title">{t.aiModelsPage.aiModelsTitle}</h3>
        <LiveAiModels llm={llm} monitor={monitor} />
      </div>

      {/* Process Info */}
      {proc && (
        <div className="panel panel--pad">
          <h3 className="panel-title">{t.aiModelsPage.processInfo}</h3>
          <div className="stack" style={{ gap: 10 }}>
            <div
              style={{
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                padding: "12px 16px",
                borderRadius: "var(--radius-inner)",
                background: "var(--panel-soft-2)",
                border: "1px solid var(--line)",
              }}
            >
              <span className="text-small text-muted">{t.aiModelsPage.processMemory}</span>
              <StatusPill tone="info" label={proc.memory_percent != null ? `${proc.memory_percent.toFixed(2)}%` : "N/A"} />
            </div>
            <div
              style={{
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                padding: "12px 16px",
                borderRadius: "var(--radius-inner)",
                background: "var(--panel-soft-2)",
                border: "1px solid var(--line)",
              }}
            >
              <span className="text-small text-muted">{t.aiModelsPage.threads}</span>
              <span style={{ fontWeight: 600 }}>{proc.num_threads ?? "N/A"}</span>
            </div>
            {sys?.load_avg && (
              <div
                style={{
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "space-between",
                  padding: "12px 16px",
                  borderRadius: "var(--radius-inner)",
                  background: "var(--panel-soft-2)",
                  border: "1px solid var(--line)",
                }}
              >
                <span className="text-small text-muted">{t.aiModelsPage.loadAvg}</span>
                <span className="mono text-small" style={{ fontWeight: 600 }}>
                  {sys.load_avg.map((l) => l.toFixed(2)).join(" / ")}
                </span>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
};
