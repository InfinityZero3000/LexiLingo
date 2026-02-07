import React, { useEffect, useState } from "react";
import { StatCard } from "../components/StatCard";
import { SectionHeader } from "../components/SectionHeader";
import { StatusPill } from "../components/StatusPill";
import { getMonitoringDashboard, MonitoringDashboard } from "../lib/aiApi";
import { getSystemInfo, type SystemInfo } from "../lib/adminApi";
import { ENV } from "../lib/env";

type HealthStatus = { status?: string; message?: string; version?: string; services?: Record<string, string> };

export const SuperAdminDashboard = () => {
  const [monitor, setMonitor] = useState<MonitoringDashboard | null>(null);
  const [sysInfo, setSysInfo] = useState<SystemInfo | null>(null);
  const [backendHealth, setBackendHealth] = useState<HealthStatus | null>(null);
  const [aiHealth, setAiHealth] = useState<HealthStatus | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    setLoading(true);
    const backendBase = ENV.backendUrl.replace("/api/v1", "");
    const aiBase = ENV.aiUrl.replace("/api/v1", "");

    Promise.allSettled([
      getMonitoringDashboard(),
      getSystemInfo(),
      fetch(`${backendBase}/health`).then((r) => r.json()),
      fetch(`${aiBase}/health`).then((r) => r.json()),
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
  const beOk = backendHealth?.status === "healthy";
  const aiOk = aiHealth?.status === "healthy" || aiHealth?.status === "ok";
  const warnCount = monitor?.health?.warning_count || 0;
  const critCount = monitor?.health?.critical_count || 0;

  if (loading) return <div className="loading">Đang tải dashboard...</div>;

  return (
    <div className="stack">
      <SectionHeader title="Super Admin Dashboard" description="Tổng quan hệ thống, tài nguyên và dịch vụ" />

      {/* Primary Stats */}
      <div className="card-grid">
        <StatCard
          label="Người dùng"
          value={String(sysInfo?.totals.users || 0)}
          note={`${sysInfo?.totals.courses || 0} khóa học`}
          accent="orange"
        />
        <StatCard
          label="CPU / Memory"
          value={sys ? `${sys.cpu_percent?.toFixed(0)}% / ${sys.memory_percent?.toFixed(0)}%` : "--"}
          accent={sys?.cpu_percent && sys.cpu_percent > 80 ? "orange" : "teal"}
        />
        <StatCard
          label="Disk Usage"
          value={sys?.disk_percent != null ? `${sys.disk_percent.toFixed(1)}%` : "--"}
          accent={sys?.disk_percent && sys.disk_percent > 90 ? "orange" : "berry"}
        />
        <StatCard
          label="System Health"
          value={healthy === undefined ? "--" : healthy ? "Ổn định" : `${critCount} lỗi`}
          accent={healthy ? "teal" : "orange"}
          note={warnCount > 0 ? `${warnCount} cảnh báo` : undefined}
        />
      </div>

      <div className="grid-2">
        {/* Service Status */}
        <div className="panel">
          <SectionHeader title="Trạng thái dịch vụ" description="Kết nối các service trong hệ thống" />
          <div className="pill-grid">
            <div className="pill-item">
              <div>
                <div className="pill-title">Backend API</div>
                <div className="pill-desc">FastAPI • {backendHealth?.version || "v?"}</div>
              </div>
              <StatusPill tone={beOk ? "success" : "danger"} label={beOk ? "Healthy" : "Down"} />
            </div>
            <div className="pill-item">
              <div>
                <div className="pill-title">AI Service</div>
                <div className="pill-desc">FastAPI • Gemini + Voice</div>
              </div>
              <StatusPill tone={aiOk ? "success" : "danger"} label={aiOk ? "Online" : "Down"} />
            </div>
            <div className="pill-item">
              <div>
                <div className="pill-title">PostgreSQL</div>
                <div className="pill-desc">Backend database</div>
              </div>
              <StatusPill tone={beOk ? "success" : "warning"} label={beOk ? "Connected" : "Unknown"} />
            </div>
            <div className="pill-item">
              <div>
                <div className="pill-title">MongoDB</div>
                <div className="pill-desc">AI data store</div>
              </div>
              <StatusPill
                tone={aiHealth?.services?.mongodb === "connected" ? "success" : "warning"}
                label={aiHealth?.services?.mongodb || "Unknown"}
              />
            </div>
            {aiHealth?.services?.redis && (
              <div className="pill-item">
                <div>
                  <div className="pill-title">Redis</div>
                  <div className="pill-desc">Cache layer</div>
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
          <SectionHeader title="AI Models" description="Model đang hoạt động trong hệ thống" />
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
              <div className="mini-title">GraphCAG</div>
              <div className="mini-desc">Knowledge Graph • Custom Pipeline</div>
            </div>
          </div>
        </div>
      </div>

      {/* System Config Quick View */}
      {sysInfo && (
        <div className="panel" style={{ padding: 20 }}>
          <h3 style={{ margin: "0 0 16px" }}>Cấu hình nhanh</h3>
          <div style={{ display: "flex", gap: 16, flexWrap: "wrap" }}>
            <ConfigChip label="Env" value={sysInfo.app_env} />
            <ConfigChip label="Debug" value={sysInfo.debug ? "ON" : "OFF"} />
            <ConfigChip label="Log" value={sysInfo.log_level} />
            <ConfigChip label="Token" value={`${sysInfo.token_expire_minutes}m`} />
            <ConfigChip label="OAuth" value={sysInfo.google_oauth ? "✓" : "✗"} />
            <ConfigChip label="Firebase" value={sysInfo.firebase ? "✓" : "✗"} />
          </div>
        </div>
      )}

      {/* System Warnings */}
      {monitor?.health?.warnings && monitor.health.warnings.length > 0 && (
        <div className="panel" style={{ padding: 16, background: "#FFF7ED", border: "1px solid #FDBA74" }}>
          <h4 style={{ margin: "0 0 8px", color: "#C2410C" }}>⚠️ Cảnh báo hệ thống</h4>
          {monitor.health.warnings.map((w, i) => (
            <p key={i} style={{ margin: "4px 0", fontSize: 14, color: "#9A3412" }}>{w}</p>
          ))}
        </div>
      )}
    </div>
  );
};

const ConfigChip = ({ label, value }: { label: string; value: string }) => (
  <span style={{
    display: "inline-flex", gap: 6, alignItems: "center",
    padding: "6px 12px", background: "var(--bg-secondary, #f5f5f5)",
    borderRadius: 8, fontSize: 13,
  }}>
    <span style={{ color: "var(--muted, #666)" }}>{label}:</span>
    <span style={{ fontWeight: 600 }}>{value}</span>
  </span>
);
