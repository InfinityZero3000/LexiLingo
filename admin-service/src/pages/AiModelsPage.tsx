import React, { useEffect, useState } from "react";
import { SectionHeader } from "../components/SectionHeader";
import { StatCard } from "../components/StatCard";
import { StatusPill } from "../components/StatusPill";
import { DataTable } from "../components/DataTable";
import { getMonitoringDashboard, type MonitoringDashboard } from "../lib/aiApi";
import { ENV } from "../lib/env";

type AiHealth = {
  status?: string;
  services?: Record<string, string>;
  warnings?: string[];
};

const AI_MODELS = [
  { name: "Gemini 2.0 Flash", type: "LLM / Chat", provider: "Google AI", mode: "API Cloud", usage: "Chat, Grammar Check, Topic Conversation" },
  { name: "Whisper Base", type: "STT (Speech-to-Text)", provider: "OpenAI", mode: "Local CPU", usage: "Phát âm, Listening exercises" },
  { name: "Piper TTS", type: "TTS (Text-to-Speech)", provider: "Piper", mode: "Local CPU", usage: "Phát âm từ vựng, đọc câu" },
  { name: "GraphCAG", type: "Knowledge Graph", provider: "Custom", mode: "Local", usage: "Trả lời câu hỏi ngữ pháp, context-aware" },
];

const PIPELINES = [
  { name: "Chat Pipeline", components: "Gemini → Response Filter → Cache", status: "active" },
  { name: "Voice Pipeline", components: "Whisper STT → Gemini → Piper TTS", status: "active" },
  { name: "Grammar Check", components: "Input → Gemini → Correction → Score", status: "active" },
  { name: "GraphCAG Query", components: "Query → Graph Lookup → LLM Synthesis", status: "active" },
];

export const AiModelsPage = () => {
  const [monitor, setMonitor] = useState<MonitoringDashboard | null>(null);
  const [health, setHealth] = useState<AiHealth | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    setLoading(true);
    const aiBase = ENV.aiUrl.replace("/api/v1", "");

    Promise.allSettled([
      getMonitoringDashboard(),
      fetch(`${aiBase}/health`).then((r) => r.json()),
    ])
      .then(([monRes, healthRes]) => {
        if (monRes.status === "fulfilled") setMonitor(monRes.value);
        if (healthRes.status === "fulfilled") setHealth(healthRes.value);
      })
      .finally(() => setLoading(false));
  }, []);

  if (loading) return <div className="loading">Đang tải thông tin AI...</div>;

  const sys = monitor?.system;
  const proc = monitor?.process;
  const aiOk = health?.status === "healthy" || health?.status === "ok";
  const warnings = monitor?.health?.warnings || [];

  return (
    <div className="stack">
      <SectionHeader
        title="AI Models & Pipelines"
        description="Giám sát model, tài nguyên hệ thống và pipeline xử lý"
      />

      {/* System Resource Cards */}
      <div className="card-grid">
        <StatCard
          label="AI Service"
          value={aiOk ? "Online" : "Offline"}
          accent={aiOk ? "teal" : "orange"}
          note={health?.status || "Unknown"}
        />
        <StatCard
          label="CPU Usage"
          value={sys?.cpu_percent != null ? `${sys.cpu_percent.toFixed(1)}%` : "--"}
          accent={sys?.cpu_percent && sys.cpu_percent > 80 ? "orange" : "teal"}
        />
        <StatCard
          label="Memory"
          value={sys?.memory_percent != null ? `${sys.memory_percent.toFixed(1)}%` : "--"}
          accent={sys?.memory_percent && sys.memory_percent > 80 ? "orange" : "berry"}
        />
        <StatCard
          label="Disk"
          value={sys?.disk_percent != null ? `${sys.disk_percent.toFixed(1)}%` : "--"}
          accent={sys?.disk_percent && sys.disk_percent > 90 ? "orange" : "ink"}
        />
      </div>

      {/* Warnings */}
      {warnings.length > 0 && (
        <div className="panel" style={{ padding: 16, background: "#FFF7ED", border: "1px solid #FDBA74" }}>
          <h4 style={{ margin: "0 0 8px", color: "#C2410C" }}>⚠️ Cảnh báo ({warnings.length})</h4>
          {warnings.map((w, i) => (
            <p key={i} style={{ margin: "4px 0", fontSize: 14, color: "#9A3412" }}>{w}</p>
          ))}
        </div>
      )}

      {/* Service Connections */}
      {health?.services && (
        <div className="panel" style={{ padding: 20 }}>
          <h3 style={{ margin: "0 0 16px" }}>Kết nối dịch vụ</h3>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <tbody>
              {Object.entries(health.services).map(([svc, status]) => (
                <tr key={svc} style={{ borderBottom: "1px solid var(--border, #eee)" }}>
                  <td style={{ padding: "10px 12px", fontWeight: 500, fontSize: 14, textTransform: "capitalize" }}>{svc}</td>
                  <td style={{ padding: "10px 12px" }}>
                    <StatusPill
                      tone={status === "connected" ? "success" : status === "not_configured" ? "info" : "danger"}
                      label={status}
                    />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* AI Models */}
      <div className="panel">
        <h3 style={{ padding: "16px 16px 0" }}>AI Models</h3>
        <DataTable
          columns={[
            { header: "Model", render: (r) => <span className="table-title">{r.name}</span> },
            { header: "Loại", render: (r) => <StatusPill tone="info" label={r.type} /> },
            { header: "Provider", render: (r) => <span className="table-meta">{r.provider}</span> },
            { header: "Mode", render: (r) => (
              <StatusPill
                tone={r.mode.includes("Cloud") ? "warning" : "success"}
                label={r.mode}
              />
            ), align: "center" },
            { header: "Sử dụng cho", render: (r) => <span className="table-meta" style={{ fontSize: 13 }}>{r.usage}</span> },
          ]}
          rows={AI_MODELS}
        />
      </div>

      {/* Pipelines */}
      <div className="panel">
        <h3 style={{ padding: "16px 16px 0" }}>Processing Pipelines</h3>
        <DataTable
          columns={[
            { header: "Pipeline", render: (r) => <span className="table-title">{r.name}</span> },
            { header: "Components", render: (r) => (
              <span className="table-meta" style={{ fontFamily: "monospace", fontSize: 13 }}>{r.components}</span>
            ) },
            { header: "Trạng thái", render: (r) => <StatusPill tone="success" label="Active" />, align: "center" },
          ]}
          rows={PIPELINES}
        />
      </div>

      {/* Process Info */}
      {proc && (
        <div className="panel" style={{ padding: 20 }}>
          <h3 style={{ margin: "0 0 16px" }}>Process Info</h3>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <tbody>
              <tr style={{ borderBottom: "1px solid var(--border, #eee)" }}>
                <td style={{ padding: "10px 12px", color: "var(--muted, #666)", width: "40%", fontSize: 14 }}>Process Memory</td>
                <td style={{ padding: "10px 12px", fontWeight: 500, fontSize: 14 }}>
                  {proc.memory_percent != null ? `${proc.memory_percent.toFixed(2)}%` : "N/A"}
                </td>
              </tr>
              <tr style={{ borderBottom: "1px solid var(--border, #eee)" }}>
                <td style={{ padding: "10px 12px", color: "var(--muted, #666)", width: "40%", fontSize: 14 }}>Threads</td>
                <td style={{ padding: "10px 12px", fontWeight: 500, fontSize: 14 }}>
                  {proc.num_threads ?? "N/A"}
                </td>
              </tr>
              {sys?.load_avg && (
                <tr style={{ borderBottom: "1px solid var(--border, #eee)" }}>
                  <td style={{ padding: "10px 12px", color: "var(--muted, #666)", width: "40%", fontSize: 14 }}>Load Average</td>
                  <td style={{ padding: "10px 12px", fontWeight: 500, fontSize: 14, fontFamily: "monospace" }}>
                    {sys.load_avg.map((l) => l.toFixed(2)).join(" / ")}
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
};
