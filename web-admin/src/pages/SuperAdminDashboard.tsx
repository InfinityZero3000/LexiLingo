import React, { useEffect, useState } from "react";
import { StatCard } from "../components/StatCard";
import { SectionHeader } from "../components/SectionHeader";
import { StatusPill } from "../components/StatusPill";
import { getMonitoringDashboard, MonitoringDashboard } from "../lib/aiApi";

export const SuperAdminDashboard = () => {
  const [monitor, setMonitor] = useState<MonitoringDashboard | null>(null);

  useEffect(() => {
    getMonitoringDashboard().then(setMonitor).catch(() => null);
  }, []);

  const healthy = monitor?.health?.healthy;

  return (
    <div className="stack">
      <div className="card-grid">
        <StatCard label="AI Models đang tải" value="3" note="Qwen, Piper, Whisper" />
        <StatCard label="Pipeline latency" value="320ms" trend="-12%" accent="teal" />
        <StatCard label="DB hoạt động" value="99.98%" trend="30 ngày" accent="berry" />
        <StatCard
          label="Resource health"
          value={healthy === undefined ? "--" : healthy ? "Ổn" : "Cảnh báo"}
          accent={healthy ? "teal" : "orange"}
        />
      </div>

      <div className="grid-2">
        <div className="panel">
          <SectionHeader
            title="AI Model Control"
            description="Theo dõi trạng thái model và cấu hình"
          />
          <div className="mini-list">
            <div>
              <div className="mini-title">Qwen / Chat</div>
              <div className="mini-desc">Primary • Load on demand</div>
            </div>
            <div>
              <div className="mini-title">Whisper / STT</div>
              <div className="mini-desc">Base model • CPU</div>
            </div>
            <div>
              <div className="mini-title">Piper / TTS</div>
              <div className="mini-desc">Voice: en_US-lessac</div>
            </div>
          </div>
        </div>

        <div className="panel">
          <SectionHeader title="DB Operations" description="Theo dõi kết nối và sao lưu" />
          <div className="pill-grid">
            <div className="pill-item">
              <div>
                <div className="pill-title">PostgreSQL</div>
                <div className="pill-desc">Backend service • OK</div>
              </div>
              <StatusPill tone="success" label="Healthy" />
            </div>
            <div className="pill-item">
              <div>
                <div className="pill-title">MongoDB</div>
                <div className="pill-desc">AI service • Connected</div>
              </div>
              <StatusPill tone="info" label="Connected" />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
