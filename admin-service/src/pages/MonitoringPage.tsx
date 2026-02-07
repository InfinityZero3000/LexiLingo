import React, { useEffect, useState } from "react";
import { SectionHeader } from "../components/SectionHeader";
import { StatCard } from "../components/StatCard";
import { getMonitoringDashboard, MonitoringDashboard } from "../lib/aiApi";
import { useI18n } from "../lib/i18n";

export const MonitoringPage = () => {
  const { t } = useI18n();
  const [monitor, setMonitor] = useState<MonitoringDashboard | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    getMonitoringDashboard()
      .then(setMonitor)
      .catch((err) => setError(err?.message || t.monitoring.loadFailed));
  }, []);

  return (
    <div className="stack">
      <SectionHeader title={t.monitoring.title} description={t.monitoring.description} />
      {error && <div className="form-error">{error}</div>}
      <div className="card-grid">
        <StatCard
          label={t.monitoring.cpu}
          value={monitor?.system?.cpu_percent ? `${monitor.system.cpu_percent.toFixed(1)}%` : "--"}
        />
        <StatCard
          label={t.monitoring.memory}
          value={monitor?.system?.memory_percent ? `${monitor.system.memory_percent.toFixed(1)}%` : "--"}
          accent="teal"
        />
        <StatCard
          label={t.monitoring.disk}
          value={monitor?.system?.disk_percent ? `${monitor.system.disk_percent.toFixed(1)}%` : "--"}
          accent="berry"
        />
        <StatCard
          label={t.monitoring.backendStatus}
          value={monitor?.health?.healthy === undefined ? "--" : monitor.health.healthy ? t.common.healthy : t.common.warning}
          accent={monitor?.health?.healthy ? "teal" : "orange"}
        />
      </div>
    </div>
  );
};
