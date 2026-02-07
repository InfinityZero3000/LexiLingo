import React, { useEffect, useState } from "react";
import { StatCard } from "../components/StatCard";
import { SectionHeader } from "../components/SectionHeader";
import { StatusPill } from "../components/StatusPill";
import { getMonitoringDashboard, MonitoringDashboard } from "../lib/aiApi";
import { getDashboardStats, DashboardStats } from "../lib/rbacApi";

const fmtDate = (iso: string) => {
  const d = new Date(iso);
  return d.toLocaleString("vi-VN", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
};

export const AdminDashboard = () => {
  const [monitor, setMonitor] = useState<MonitoringDashboard | null>(null);
  const [monitorError, setMonitorError] = useState<string | null>(null);
  const [stats, setStats] = useState<DashboardStats["dashboard"] | null>(null);
  const [statsError, setStatsError] = useState<string | null>(null);

  useEffect(() => {
    getMonitoringDashboard()
      .then(setMonitor)
      .catch((err) => setMonitorError(err?.message || "Không lấy được dữ liệu monitoring"));

    getDashboardStats()
      .then((res) => setStats(res.dashboard))
      .catch((err) => setStatsError(err?.message || "Không lấy được thống kê"));
  }, []);

  const health = monitor?.health?.healthy;
  const cpu = monitor?.system?.cpu_percent;
  const memory = monitor?.system?.memory_percent;

  return (
    <div className="stack">
      <div className="card-grid">
        <StatCard
          label="Tổng người dùng"
          value={stats ? stats.total_users.toLocaleString() : "--"}
          trend={stats ? `${stats.active_users} đang hoạt động` : undefined}
          note={statsError || undefined}
        />
        <StatCard
          label="Achievements"
          value={stats ? String(stats.total_achievements) : "--"}
          trend={stats ? `${stats.total_unlocks} lượt mở khoá` : undefined}
          accent="teal"
        />
        <StatCard
          label="Phân bổ vai trò"
          value={stats ? Object.values(stats.users_by_role).reduce((a, b) => a + b, 0).toString() : "--"}
          trend={stats ? Object.entries(stats.users_by_role).map(([r, c]) => `${r}: ${c}`).join(" · ") : undefined}
          accent="berry"
        />
        <StatCard
          label="Sức khoẻ hệ thống"
          value={health === undefined ? "--" : health ? "Ổn định" : "Cảnh báo"}
          note={monitorError || "AI service monitoring"}
          accent={health ? "teal" : "orange"}
        />
      </div>

      <div className="grid-2">
        <div className="panel">
          <SectionHeader
            title="Hoạt động Admin gần đây"
            description="Audit trail từ hệ thống RBAC"
          />
          {stats && stats.recent_actions.length > 0 ? (
            <div className="pill-grid">
              {stats.recent_actions.map((a, i) => (
                <div className="pill-item" key={i}>
                  <div>
                    <div className="pill-title">{a.action}</div>
                    <div className="pill-desc">{a.resource_type} • {fmtDate(a.created_at)}</div>
                  </div>
                  <StatusPill
                    tone={a.action === "deactivate" ? "danger" : a.action === "assign_role" ? "warning" : "info"}
                    label={a.action}
                  />
                </div>
              ))}
            </div>
          ) : (
            <div className="loading-text">Chưa có hoạt động</div>
          )}
        </div>

        <div className="panel">
          <SectionHeader title="Tình trạng hạ tầng" description="CPU, RAM từ AI service" />
          <div className="pill-grid">
            <div className="pill-item">
              <div>
                <div className="pill-title">CPU</div>
                <div className="pill-desc">{cpu ? `${cpu.toFixed(1)}%` : "--"}</div>
              </div>
              <StatusPill tone={cpu && cpu > 80 ? "danger" : "success"} label={cpu ? `${cpu.toFixed(0)}%` : "--"} />
            </div>
            <div className="pill-item">
              <div>
                <div className="pill-title">RAM</div>
                <div className="pill-desc">{memory ? `${memory.toFixed(1)}%` : "--"}</div>
              </div>
              <StatusPill tone={memory && memory > 80 ? "danger" : "success"} label={memory ? `${memory.toFixed(0)}%` : "--"} />
            </div>
            <div className="pill-item">
              <div>
                <div className="pill-title">Trạng thái chung</div>
                <div className="pill-desc">AI Service Health Check</div>
              </div>
              <StatusPill tone={health ? "success" : "danger"} label={health ? "Healthy" : "Cảnh báo"} />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
