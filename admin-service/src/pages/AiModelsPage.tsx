import React, { useEffect, useState } from "react";
import { Activity, AlertTriangle, Bot, Cpu, HardDrive, Workflow } from "lucide-react";
import { SectionHeader } from "../components/SectionHeader";
import { StatCard } from "../components/StatCard";
import { StatusPill } from "../components/StatusPill";
import { getMonitoringDashboard, type MonitoringDashboard } from "../lib/aiApi";
import { checkAiHealth } from "../lib/healthApi";
import { useI18n } from "../lib/i18n";

type AiHealth = {
  status?: string;
  services?: Record<string, string>;
  warnings?: string[];
};

const AI_MODELS = [
  { name: "Qwen 3.8 27B", type: "LLM / Chat", provider: "Groq", mode: "API Cloud", usage: "Chat, Grammar Check, Topic Conversation" },
  { name: "Whisper Base", type: "STT (Speech-to-Text)", provider: "OpenAI", mode: "Local CPU", usage: "Phát âm, Listening exercises" },
  { name: "Piper TTS", type: "TTS (Text-to-Speech)", provider: "Piper", mode: "Local CPU", usage: "Phát âm từ vựng, đọc câu" },
  { name: "TRACECAG", type: "Knowledge Graph", provider: "Custom", mode: "Local", usage: "Trả lời câu hỏi ngữ pháp, context-aware" },
];

const PIPELINES = [
  { name: "Chat Pipeline", components: "LLM → Response Filter → Cache" },
  { name: "Voice Pipeline", components: "Whisper STT → LLM → Piper TTS" },
  { name: "Grammar Check", components: "Input → LLM → Correction → Score" },
  { name: "TRACECAG Query", components: "Query → Graph Lookup → LLM Synthesis" },
];

export const AiModelsPage = () => {
  const [monitor, setMonitor] = useState<MonitoringDashboard | null>(null);
  const [health, setHealth] = useState<AiHealth | null>(null);
  const [loading, setLoading] = useState(true);
  const { t } = useI18n();

  useEffect(() => {
    setLoading(true);

    Promise.allSettled([
      getMonitoringDashboard(),
      checkAiHealth().then((r) => r.json()),
    ])
      .then(([monRes, healthRes]) => {
        if (monRes.status === "fulfilled") setMonitor(monRes.value);
        if (healthRes.status === "fulfilled") setHealth(healthRes.value);
      })
      .finally(() => setLoading(false));
  }, []);

  if (loading) return <div className="loading">{t.common.loading}</div>;

  const sys = monitor?.system;
  const cpuPercent = sys ? (sys.cpu_percent ?? sys.cpu?.percent) : undefined;
  const memoryPercent = sys ? (sys.memory_percent ?? sys.memory?.percent) : undefined;
  const diskPercent = sys ? (sys.disk_percent ?? sys.disk?.percent) : undefined;
  const proc = monitor?.process;
  const aiOk = health?.status === "healthy" || health?.status === "ok";
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
          note={health?.status || t.common.unknown}
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

      {/* Service Connections */}
      {health?.services && (
        <div className="panel panel--pad">
          <h3 className="panel-title">{t.aiModelsPage.serviceConns}</h3>
          <div className="form-grid">
            {Object.entries(health.services).map(([svc, status]) => (
              <div
                key={svc}
                style={{
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "space-between",
                  gap: 12,
                  padding: "12px 16px",
                  borderRadius: "var(--radius-inner)",
                  background: "var(--panel-soft-2)",
                  border: "1px solid var(--line)",
                }}
              >
                <span className="kv-value kv-value--cap" style={{ padding: 0 }}>{svc}</span>
                <StatusPill
                  tone={status === "connected" ? "success" : status === "not_configured" ? "info" : "danger"}
                  label={status}
                />
              </div>
            ))}
          </div>
        </div>
      )}

      {/* AI Models */}
      <div className="panel panel--pad">
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12 }}>
          <h3 className="panel-title" style={{ margin: 0 }}>{t.aiModelsPage.aiModelsTitle}</h3>
          <StatusPill tone="info" label={String(AI_MODELS.length)} />
        </div>
        <div className="grid-2">
          {AI_MODELS.map((m) => (
            <div
              key={m.name}
              style={{
                display: "flex",
                flexDirection: "column",
                gap: 10,
                padding: 18,
                borderRadius: "var(--radius-inner)",
                background: "var(--panel-soft-2)",
                border: "1px solid var(--line)",
              }}
            >
              <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between", gap: 10 }}>
                <div>
                  <div className="table-title" style={{ fontSize: 16 }}>{m.name}</div>
                  <div className="text-small text-muted" style={{ marginTop: 2 }}>{m.provider}</div>
                </div>
                <StatusPill tone={m.mode.includes("Cloud") ? "info" : "success"} label={m.mode} />
              </div>
              <div style={{ display: "flex", alignItems: "center", gap: 8, flexWrap: "wrap" }}>
                <StatusPill tone="neutral" label={m.type} />
              </div>
              <p className="text-small text-muted" style={{ margin: 0, lineHeight: 1.5 }}>{m.usage}</p>
            </div>
          ))}
        </div>
      </div>

      {/* Pipelines */}
      <div className="panel panel--pad">
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <span
              style={{
                width: 34,
                height: 34,
                borderRadius: 10,
                display: "grid",
                placeItems: "center",
                background: "var(--accent-soft)",
                color: "var(--accent)",
              }}
            >
              <Workflow size={17} />
            </span>
            <h3 className="panel-title" style={{ margin: 0 }}>{t.aiModelsPage.processingPipelines}</h3>
          </div>
          <StatusPill tone={aiOk ? "success" : "danger"} label={aiOk ? t.common.active : t.common.offline} />
        </div>
        <div className="grid-2">
          {PIPELINES.map((p) => (
            <div
              key={p.name}
              style={{
                display: "flex",
                flexDirection: "column",
                gap: 10,
                padding: 16,
                borderRadius: "var(--radius-inner)",
                background: "var(--panel-soft-2)",
                border: "1px solid var(--line)",
              }}
            >
              <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 8 }}>
                <span className="table-title">{p.name}</span>
                <StatusPill tone={aiOk ? "success" : "danger"} label={aiOk ? t.common.active : t.common.offline} />
              </div>
              <div
                className="mono text-small"
                style={{
                  padding: "8px 12px",
                  borderRadius: 10,
                  background: "var(--panel)",
                  border: "1px solid var(--line)",
                  color: "var(--muted)",
                }}
              >
                {p.components}
              </div>
            </div>
          ))}
        </div>
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
