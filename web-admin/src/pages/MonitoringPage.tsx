import React, { useEffect, useState } from "react";
import { SectionHeader } from "../components/SectionHeader";
import { StatCard } from "../components/StatCard";
import { getMonitoringDashboard, MonitoringDashboard } from "../lib/aiApi";

export const MonitoringPage = () => {
  const [monitor, setMonitor] = useState<MonitoringDashboard | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    getMonitoringDashboard()
      .then(setMonitor)
      .catch((err) => setError(err?.message || "Không lấy được dữ liệu monitoring"));
  }, []);

  return (
    <div className="panel">
      <SectionHeader title="System Monitoring" description="AI service /api/v1/ai/monitoring" />
      {error && <div className="form-error">{error}</div>}
      <div className="card-grid">
        <StatCard
          label="CPU"
          value={monitor?.system?.cpu_percent ? `${monitor.system.cpu_percent.toFixed(1)}%` : "--"}
        />
        <StatCard
          label="Memory"
          value={monitor?.system?.memory_percent ? `${monitor.system.memory_percent.toFixed(1)}%` : "--"}
          accent="teal"
        />
        <StatCard
          label="Disk"
          value={monitor?.system?.disk_percent ? `${monitor.system.disk_percent.toFixed(1)}%` : "--"}
          accent="berry"
        />
        <StatCard
          label="Health"
          value={monitor?.health?.healthy === undefined ? "--" : monitor.health.healthy ? "Healthy" : "Warning"}
          accent={monitor?.health?.healthy ? "teal" : "orange"}
        />
      </div>
    </div>
  );
};
