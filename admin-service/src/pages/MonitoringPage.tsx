import React, { useCallback, useEffect, useRef, useState } from "react";
import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  RadialBarChart,
  RadialBar,
  BarChart,
  Bar,
  Legend,
  PolarAngleAxis,
} from "recharts";
import { Activity, CheckCircle, AlertTriangle, XCircle, RefreshCw, Database, Cpu, HardDrive, Server, Wifi } from "lucide-react";
import { SectionHeader } from "../components/SectionHeader";
import { StatCard } from "../components/StatCard";
import {
  getSystemMetrics,
  getServicesHealth,
  getDbStats,
  getRequestStats,
  getMonitoringDashboard,
  type SystemMetrics,
  type ServicesHealth,
  type DbStats,
  type RequestStats,
  type MonitoringDashboard,
} from "../lib/aiApi";
import { useI18n } from "../lib/i18n";

// ─── Types ────────────────────────────────────────────────────────────────────

type TimePoint = {
  time: string;
  cpu: number;
  memory: number;
  connections: number;
};

type LoadingState = "idle" | "loading" | "ok" | "error";

// ─── Helpers ──────────────────────────────────────────────────────────────────

const statusColor = (s: string) => {
  if (s === "healthy") return "var(--accent-2)";
  if (s === "unhealthy") return "var(--accent)";
  if (s === "unreachable") return "#e55";
  return "var(--muted)";
};

const StatusIcon = ({ status }: { status: string }) => {
  if (status === "healthy")
    return <CheckCircle size={16} color="var(--accent-2)" />;
  if (status === "unhealthy" || status === "unreachable")
    return <XCircle size={16} color="var(--accent)" />;
  return <AlertTriangle size={16} color="#f90" />;
};

const fmt = (n: number | undefined, dec = 1) =>
  n !== undefined ? n.toFixed(dec) : "--";

const nowLabel = () =>
  new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });

// ─── GaugeBar ─────────────────────────────────────────────────────────────────

const GaugeBar = ({
  label,
  value,
  max = 100,
  unit = "%",
  color = "var(--accent-2)",
}: {
  label: string;
  value: number;
  max?: number;
  unit?: string;
  color?: string;
}) => {
  const pct = Math.min(100, (value / max) * 100);
  const barColor =
    pct > 85 ? "var(--accent)" : pct > 60 ? "#f90" : color;

  return (
    <div style={{ marginBottom: 12 }}>
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          fontSize: 12,
          marginBottom: 4,
          color: "var(--muted)",
        }}
      >
        <span>{label}</span>
        <span style={{ fontWeight: 600, color: "var(--text)" }}>
          {fmt(value, unit === "%" ? 1 : 2)}
          {unit}
        </span>
      </div>
      <div
        style={{
          height: 8,
          borderRadius: 4,
          background: "var(--line)",
          overflow: "hidden",
        }}
      >
        <div
          style={{
            height: "100%",
            width: `${pct}%`,
            background: barColor,
            borderRadius: 4,
            transition: "width 0.6s ease",
          }}
        />
      </div>
    </div>
  );
};

// ─── ServiceBadge ─────────────────────────────────────────────────────────────

const ServiceBadge = ({ name, status, icon }: { name: string; status: string; icon: React.ReactNode }) => (
  <div
    style={{
      display: "flex",
      alignItems: "center",
      gap: 10,
      padding: "10px 14px",
      borderRadius: 10,
      background: "var(--panel-soft-2)",
      border: `1px solid var(--line)`,
    }}
  >
    <div style={{ color: statusColor(status) }}>{icon}</div>
    <div style={{ flex: 1 }}>
      <div style={{ fontSize: 13, fontWeight: 600 }}>{name}</div>
      <div style={{ fontSize: 11, color: statusColor(status), textTransform: "capitalize" }}>
        {status}
      </div>
    </div>
    <StatusIcon status={status} />
  </div>
);

// ─── Main Page ────────────────────────────────────────────────────────────────

const HISTORY_MAX = 30;
const REFRESH_MS = 30_000;

export const MonitoringPage = () => {
  const { t } = useI18n();

  const [system, setSystem] = useState<SystemMetrics | null>(null);
  const [services, setServices] = useState<ServicesHealth | null>(null);
  const [db, setDb] = useState<DbStats | null>(null);
  const [reqStats, setReqStats] = useState<RequestStats | null>(null);
  const [aiDash, setAiDash] = useState<MonitoringDashboard | null>(null);
  const [history, setHistory] = useState<TimePoint[]>([]);
  const [loadState, setLoadState] = useState<LoadingState>("idle");
  const [lastUpdated, setLastUpdated] = useState<string>("");
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const fetchAll = useCallback(async () => {
    setLoadState("loading");
    try {
      const [sys, svc, dbSt, rq, ai] = await Promise.allSettled([
        getSystemMetrics(),
        getServicesHealth(),
        getDbStats(),
        getRequestStats(),
        getMonitoringDashboard(),
      ]);

      const sysVal = sys.status === "fulfilled" ? sys.value : null;
      const svcVal = svc.status === "fulfilled" ? svc.value : null;
      const dbVal = dbSt.status === "fulfilled" ? dbSt.value : null;
      const rqVal = rq.status === "fulfilled" ? rq.value : null;
      const aiVal = ai.status === "fulfilled" ? ai.value : null;

      setSystem(sysVal);
      setServices(svcVal);
      setDb(dbVal);
      setReqStats(rqVal);
      setAiDash(aiVal);

      const label = nowLabel();
      setHistory((prev) => {
        const point: TimePoint = {
          time: label,
          cpu: sysVal?.cpu_percent ?? aiVal?.system?.cpu?.percent ?? aiVal?.system?.cpu_percent ?? 0,
          memory: sysVal?.memory?.percent ?? aiVal?.system?.memory?.percent ?? aiVal?.system?.memory_percent ?? 0,
          connections: rqVal?.active_connections ?? 0,
        };
        const next = [...prev, point];
        return next.length > HISTORY_MAX ? next.slice(-HISTORY_MAX) : next;
      });

      setLastUpdated(label);
      setLoadState("ok");
    } catch {
      setLoadState("error");
    }
  }, []);

  useEffect(() => {
    fetchAll();
    intervalRef.current = setInterval(fetchAll, REFRESH_MS);
    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
  }, [fetchAll]);

  // ── Derived values ──────────────────────────────────────────────────────────

  const cpu = system?.cpu_percent ?? aiDash?.system?.cpu?.percent ?? aiDash?.system?.cpu_percent;
  const mem = system?.memory?.percent ?? aiDash?.system?.memory?.percent ?? aiDash?.system?.memory_percent;
  const disk = system?.disk?.percent ?? aiDash?.system?.disk?.percent ?? aiDash?.system?.disk_percent;
  const load1 = system?.load_avg?.["1m"] ?? (aiDash?.system?.load_avg?.[0]);
  const load5 = system?.load_avg?.["5m"] ?? (aiDash?.system?.load_avg?.[1]);
  const load15 = system?.load_avg?.["15m"] ?? (aiDash?.system?.load_avg?.[2]);

  const radialData = [
    { name: "CPU", value: cpu ?? 0, fill: "#ff4d00" },
    { name: "Memory", value: mem ?? 0, fill: "#2aa7a1" },
    { name: "Disk", value: disk ?? 0, fill: "#6f3fa3" },
  ];

  const dbCounts = db?.counts;

  return (
    <div className="stack">
      {/* Header */}
      <SectionHeader
        title={t.monitoring.title}
        description={t.monitoring.description}
        action={
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            {lastUpdated && (
              <span style={{ fontSize: 12, color: "var(--muted)" }}>
                Updated {lastUpdated}
              </span>
            )}
            <button
              className="btn-secondary btn-sm"
              onClick={fetchAll}
              disabled={loadState === "loading"}
              style={{ display: "flex", alignItems: "center", gap: 6 }}
            >
              <RefreshCw
                size={14}
                style={
                  loadState === "loading"
                    ? { animation: "spin 0.8s linear infinite" }
                    : undefined
                }
              />
              Refresh
            </button>
          </div>
        }
      />

      {/* ── Row 1: Stat cards ─────────────────────────────────────────────────── */}
      <div className="card-grid">
        <StatCard
          label="CPU"
          value={cpu !== undefined ? `${fmt(cpu)}%` : "--"}
          note={load1 !== undefined ? `Load: ${fmt(load1)} / ${fmt(load5)} / ${fmt(load15)}` : undefined}
        />
        <StatCard
          label={t.monitoring.memory}
          value={mem !== undefined ? `${fmt(mem)}%` : "--"}
          note={
            system?.memory
              ? `${fmt(system.memory.used_mb / 1024, 1)} / ${fmt(system.memory.total_mb / 1024, 1)} GB`
              : undefined
          }
          accent="teal"
        />
        <StatCard
          label={t.monitoring.disk}
          value={disk !== undefined ? `${fmt(disk)}%` : "--"}
          note={
            system?.disk
              ? `${fmt(system.disk.used_gb, 1)} / ${fmt(system.disk.total_gb, 1)} GB`
              : undefined
          }
          accent="berry"
        />
        <StatCard
          label="Connections"
          value={reqStats?.active_connections !== undefined ? String(reqStats.active_connections) : "--"}
          note={reqStats?.requests_last_minute !== undefined ? `${reqStats.requests_last_minute} req/min` : undefined}
          accent="ink"
        />
      </div>

      {/* ── Row 2: Time-series chart + Gauge ──────────────────────────────────── */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 320px", gap: 20 }}>
        {/* Area chart */}
        <div className="card" style={{ padding: 20 }}>
          <div style={{ fontWeight: 600, marginBottom: 12, fontSize: 14 }}>
            CPU &amp; Memory — last {HISTORY_MAX} samples
          </div>
          <ResponsiveContainer width="100%" height={220}>
            <AreaChart data={history} margin={{ top: 5, right: 10, left: -10, bottom: 0 }}>
              <defs>
                <linearGradient id="gradCpu" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#ff4d00" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="#ff4d00" stopOpacity={0} />
                </linearGradient>
                <linearGradient id="gradMem" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#2aa7a1" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="#2aa7a1" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--line)" />
              <XAxis dataKey="time" tick={{ fontSize: 11 }} interval="preserveStartEnd" />
              <YAxis domain={[0, 100]} unit="%" tick={{ fontSize: 11 }} />
              <Tooltip formatter={(v: any) => `${Number(v).toFixed(1)}%`} />
              <Legend />
              <Area
                type="monotone"
                dataKey="cpu"
                name="CPU %"
                stroke="#ff4d00"
                fill="url(#gradCpu)"
                strokeWidth={2}
                dot={false}
              />
              <Area
                type="monotone"
                dataKey="memory"
                name="Memory %"
                stroke="#2aa7a1"
                fill="url(#gradMem)"
                strokeWidth={2}
                dot={false}
              />
            </AreaChart>
          </ResponsiveContainer>
        </div>

        {/* Radial gauge */}
        <div className="card" style={{ padding: 20 }}>
          <div style={{ fontWeight: 600, marginBottom: 8, fontSize: 14 }}>
            Resource Usage
          </div>
          <ResponsiveContainer width="100%" height={160}>
            <RadialBarChart
              cx="50%"
              cy="50%"
              innerRadius="30%"
              outerRadius="90%"
              data={radialData}
              startAngle={90}
              endAngle={-270}
            >
              <PolarAngleAxis type="number" domain={[0, 100]} angleAxisId={0} tick={false} />
              <RadialBar dataKey="value" background angleAxisId={0} label={{ position: "insideStart", fill: "#fff", fontSize: 10 }} />
              <Tooltip formatter={(v: any) => `${Number(v).toFixed(1)}%`} />
              <Legend iconSize={10} />
            </RadialBarChart>
          </ResponsiveContainer>
          <div style={{ marginTop: 12 }}>
            <GaugeBar label="CPU" value={cpu ?? 0} />
            <GaugeBar label="Memory" value={mem ?? 0} color="var(--accent-2)" />
            <GaugeBar label="Disk" value={disk ?? 0} color="var(--accent-3)" />
          </div>
        </div>
      </div>

      {/* ── Row 3: Network + Load + Disk I/O ──────────────────────────────────── */}
      {system && (
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 16 }}>
          <div className="card" style={{ padding: 16 }}>
            <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 12, fontWeight: 600, fontSize: 13 }}>
              <Wifi size={15} /> Network I/O
            </div>
            <GaugeBar
              label={`Sent (${fmt(system.network.bytes_sent_mb / 1024, 2)} GB total)`}
              value={system.network.packets_sent}
              max={Math.max(system.network.packets_sent, system.network.packets_recv, 1)}
              unit=" pkts"
            />
            <GaugeBar
              label={`Recv (${fmt(system.network.bytes_recv_mb / 1024, 2)} GB total)`}
              value={system.network.packets_recv}
              max={Math.max(system.network.packets_sent, system.network.packets_recv, 1)}
              unit=" pkts"
              color="var(--accent-3)"
            />
          </div>

          <div className="card" style={{ padding: 16 }}>
            <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 12, fontWeight: 600, fontSize: 13 }}>
              <Cpu size={15} /> Load Average
            </div>
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 8, textAlign: "center" }}>
              {(
                [
                  ["1 min", load1],
                  ["5 min", load5],
                  ["15 min", load15],
                ] as [string, number | undefined][]
              ).map(([label, val]) => (
                <div key={label} style={{ background: "var(--panel-soft-2)", borderRadius: 8, padding: "10px 8px" }}>
                  <div style={{ fontSize: 18, fontWeight: 700, color: "var(--text)" }}>
                    {val !== undefined ? fmt(val, 2) : "--"}
                  </div>
                  <div style={{ fontSize: 11, color: "var(--muted)", marginTop: 2 }}>{label}</div>
                </div>
              ))}
            </div>
          </div>

          <div className="card" style={{ padding: 16 }}>
            <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 12, fontWeight: 600, fontSize: 13 }}>
              <HardDrive size={15} /> Disk I/O
            </div>
            <GaugeBar
              label={`Read`}
              value={system.disk_io.read_mb}
              max={Math.max(system.disk_io.read_mb, system.disk_io.write_mb, 1)}
              unit=" MB"
            />
            <GaugeBar
              label={`Write`}
              value={system.disk_io.write_mb}
              max={Math.max(system.disk_io.read_mb, system.disk_io.write_mb, 1)}
              unit=" MB"
              color="var(--accent-3)"
            />
            <div style={{ fontSize: 11, color: "var(--muted)", marginTop: 8 }}>
              Disk: {fmt(system.disk.used_gb, 1)} / {fmt(system.disk.total_gb, 1)} GB &nbsp;
              ({fmt(system.disk.percent)}% used)
            </div>
          </div>
        </div>
      )}

      {/* ── Row 4: Services + DB stats ────────────────────────────────────────── */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 20 }}>
        <div className="card" style={{ padding: 20 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 14, fontWeight: 600, fontSize: 14 }}>
            <Server size={15} /> Service Health
          </div>
          <div style={{ display: "grid", gap: 8 }}>
            <ServiceBadge
              name="PostgreSQL"
              status={services?.postgres ?? "unknown"}
              icon={<Database size={18} />}
            />
            <ServiceBadge
              name="Redis"
              status={services?.redis ?? "unknown"}
              icon={<Activity size={18} />}
            />
            <ServiceBadge
              name="AI Service"
              status={services?.ai_service ?? "unknown"}
              icon={<Activity size={18} />}
            />
            <ServiceBadge
              name="Backend"
              status={aiDash?.health?.healthy !== undefined
                ? (aiDash.health.healthy ? "healthy" : "unhealthy")
                : "unknown"}
              icon={<Server size={18} />}
            />
          </div>
          {aiDash?.health?.warnings && aiDash.health.warnings.length > 0 && (
            <div style={{ marginTop: 12, fontSize: 12, color: "var(--accent)" }}>
              ⚠ {aiDash.health.warnings.join(" • ")}
            </div>
          )}
        </div>

        <div className="card" style={{ padding: 20 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 14, fontWeight: 600, fontSize: 14 }}>
            <Database size={15} /> Database Overview
          </div>
          {dbCounts ? (
            <ResponsiveContainer width="100%" height={180}>
              <BarChart
                data={[
                  { name: "Users", count: dbCounts.users ?? 0 },
                  { name: "Courses", count: dbCounts.courses ?? 0 },
                  { name: "Lessons", count: dbCounts.lessons ?? 0 },
                  { name: "Vocab", count: dbCounts.vocabulary_items ?? 0 },
                ]}
                margin={{ top: 0, right: 0, left: -20, bottom: 0 }}
              >
                <CartesianGrid strokeDasharray="3 3" stroke="var(--line)" />
                <XAxis dataKey="name" tick={{ fontSize: 11 }} />
                <YAxis tick={{ fontSize: 11 }} />
                <Tooltip />
                <Bar dataKey="count" name="Rows" fill="var(--accent-2)" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          ) : (
            <div style={{ color: "var(--muted)", fontSize: 13 }}>No DB stats available</div>
          )}
        </div>
      </div>

      {/* ── Row 5: AI service metrics ──────────────────────────────────────────── */}
      {aiDash && (
        <div className="card" style={{ padding: 20 }}>
          <div style={{ fontWeight: 600, marginBottom: 14, fontSize: 14 }}>
            AI Service Metrics
          </div>
          <div className="card-grid">
            <StatCard
              label="AI CPU"
              value={(aiDash.system?.cpu?.percent ?? aiDash.system?.cpu_percent) !== undefined ? `${fmt(aiDash.system?.cpu?.percent ?? aiDash.system?.cpu_percent)}%` : "--"}
            />
            <StatCard
              label="AI Memory"
              value={(aiDash.system?.memory?.percent ?? aiDash.system?.memory_percent) !== undefined ? `${fmt(aiDash.system?.memory?.percent ?? aiDash.system?.memory_percent)}%` : "--"}
              accent="teal"
            />
            <StatCard
              label="Process Threads"
              value={aiDash.process?.num_threads !== undefined ? String(aiDash.process.num_threads) : "--"}
              accent="berry"
            />
            <StatCard
              label="AI Status"
              value={
                aiDash.health?.healthy !== undefined
                  ? aiDash.health.healthy
                    ? "Healthy"
                    : "Warning"
                  : "--"
              }
              accent={aiDash.health?.healthy ? "teal" : "orange"}
              note={
                aiDash.health
                  ? `${aiDash.health.critical_count ?? 0} critical, ${aiDash.health.warning_count ?? 0} warnings`
                  : undefined
              }
            />
          </div>
        </div>
      )}
    </div>
  );
};

