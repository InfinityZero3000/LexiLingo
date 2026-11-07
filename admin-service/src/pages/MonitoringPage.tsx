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
import { Activity, CheckCircle, AlertTriangle, XCircle, RefreshCw, Pause, Play, Database, Cpu, HardDrive, Server, Wifi } from "lucide-react";
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

const KNOWN_STATUS = ["healthy", "unhealthy", "unreachable"] as const;
const toneOf = (s: string) => (KNOWN_STATUS as readonly string[]).includes(s) ? s : "unknown";

const StatusIcon = ({ status }: { status: string }) => {
  if (status === "healthy") return <CheckCircle size={16} aria-hidden="true" />;
  if (status === "unhealthy" || status === "unreachable") return <XCircle size={16} aria-hidden="true" />;
  return <AlertTriangle size={16} aria-hidden="true" />;
};

const fmt = (n: number | undefined, dec = 1) =>
  n !== undefined ? n.toFixed(dec) : "--";

const nowLabel = () =>
  new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });

const fill = (text: string, vars: Record<string, string | number>) =>
  text.replace(/\{(\w+)\}/g, (_, k) => String(vars[k] ?? ""));

// ─── GaugeBar ─────────────────────────────────────────────────────────────────

const GaugeBar = ({
  label,
  value,
  max = 100,
  unit = "%",
  color,
}: {
  label: string;
  value: number;
  max?: number;
  unit?: string;
  color?: string;
}) => {
  const pct = Math.min(100, (value / max) * 100);
  const level = pct > 85 ? "crit" : pct > 60 ? "warn" : "ok";

  return (
    <div className="mon-gauge">
      <div className="mon-gauge-head">
        <span>{label}</span>
        <span className="mon-gauge-value">
          {fmt(value, unit === "%" ? 1 : 2)}
          {unit}
        </span>
      </div>
      <div
        className="mon-gauge-track"
        role="meter"
        aria-label={label}
        aria-valuemin={0}
        aria-valuemax={max}
        aria-valuenow={value}
      >
        <div
          className={`mon-gauge-fill mon-gauge-fill--${level}`}
          style={{ width: `${pct}%`, ...(level === "ok" && color ? { "--gauge-color": color } as React.CSSProperties : {}) }}
        />
      </div>
    </div>
  );
};

// ─── ServiceBadge ─────────────────────────────────────────────────────────────

const ServiceBadge = ({ name, status, label, icon }: { name: string; status: string; label: string; icon: React.ReactNode }) => (
  <div className={`mon-service mon-tone--${toneOf(status)}`}>
    <div className="mon-service-icon">{icon}</div>
    <div className="mon-service-main">
      <div className="mon-service-name">{name}</div>
      <div className="mon-service-status">{label}</div>
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
  const [paused, setPaused] = useState(false);

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
  }, [fetchAll]);

  useEffect(() => {
    if (paused) return;
    intervalRef.current = setInterval(fetchAll, REFRESH_MS);
    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
  }, [fetchAll, paused]);

  // ── Derived values ──────────────────────────────────────────────────────────

  const cpu = system?.cpu_percent ?? aiDash?.system?.cpu?.percent ?? aiDash?.system?.cpu_percent;
  const mem = system?.memory?.percent ?? aiDash?.system?.memory?.percent ?? aiDash?.system?.memory_percent;
  const disk = system?.disk?.percent ?? aiDash?.system?.disk?.percent ?? aiDash?.system?.disk_percent;
  const load1 = system?.load_avg?.["1m"] ?? (aiDash?.system?.load_avg?.[0]);
  const load5 = system?.load_avg?.["5m"] ?? (aiDash?.system?.load_avg?.[1]);
  const load15 = system?.load_avg?.["15m"] ?? (aiDash?.system?.load_avg?.[2]);

  const radialData = [
    { name: "CPU", value: cpu ?? 0, fill: "var(--accent)" },
    { name: t.monitoring.memory, value: mem ?? 0, fill: "var(--accent-2)" },
    { name: t.monitoring.disk, value: disk ?? 0, fill: "var(--accent-3)" },
  ];

  const dbCounts = db?.counts;
  const m = t.monitoring;
  const statusLabel = (status: string) => {
    const tone = toneOf(status);
    return tone === "healthy" ? m.statusHealthy
      : tone === "unhealthy" ? m.statusUnhealthy
      : tone === "unreachable" ? m.statusUnreachable
      : m.statusUnknown;
  };
  const aiCpu = aiDash?.system?.cpu?.percent ?? aiDash?.system?.cpu_percent;
  const aiMem = aiDash?.system?.memory?.percent ?? aiDash?.system?.memory_percent;
  const backendStatus = aiDash?.health?.healthy !== undefined
    ? (aiDash.health.healthy ? "healthy" : "unhealthy")
    : "unknown";

  return (
    <div className="stack">
      <SectionHeader
        title={m.title}
        description={m.description}
        action={
          <div className="mon-actions">
            {lastUpdated && <span className="mon-updated">{fill(m.updatedAt, { time: lastUpdated })}</span>}
            <button
              className="ghost-button small with-icon"
              onClick={fetchAll}
              disabled={loadState === "loading"}
            >
              <RefreshCw size={14} className={loadState === "loading" ? "is-spinning" : undefined} aria-hidden="true" />
              {m.refresh}
            </button>
            <button
              className="ghost-button small"
              onClick={() => setPaused((p) => !p)}
              aria-pressed={paused}
              title={paused ? m.resumeAuto : m.pauseAuto}
              aria-label={paused ? m.resumeAuto : m.pauseAuto}
            >
              {paused ? <Play size={14} aria-hidden="true" /> : <Pause size={14} aria-hidden="true" />}
            </button>
          </div>
        }
      />

      <div className="card-grid">
        <StatCard
          label="CPU"
          value={cpu !== undefined ? `${fmt(cpu)}%` : "--"}
          note={load1 !== undefined ? `Load: ${fmt(load1)} / ${fmt(load5)} / ${fmt(load15)}` : undefined}
        />
        <StatCard
          label={m.memory}
          value={mem !== undefined ? `${fmt(mem)}%` : "--"}
          note={
            system?.memory
              ? `${fmt(system.memory.used_mb / 1024, 1)} / ${fmt(system.memory.total_mb / 1024, 1)} GB`
              : undefined
          }
          accent="teal"
        />
        <StatCard
          label={m.disk}
          value={disk !== undefined ? `${fmt(disk)}%` : "--"}
          note={
            system?.disk
              ? `${fmt(system.disk.used_gb, 1)} / ${fmt(system.disk.total_gb, 1)} GB`
              : undefined
          }
          accent="berry"
        />
        <StatCard
          label={m.connections}
          value={reqStats?.active_connections !== undefined ? String(reqStats.active_connections) : "--"}
          note={reqStats?.requests_last_minute !== undefined ? fill(m.reqPerMin, { n: reqStats.requests_last_minute }) : undefined}
          accent="ink"
        />
      </div>

      <div className="mon-row mon-row--chart">
        <div className="card">
          <div className="mon-card-title mon-card-title--plain">{fill(m.cpuMemChart, { n: HISTORY_MAX })}</div>
          <ResponsiveContainer width="100%" height={220}>
            <AreaChart data={history} margin={{ top: 5, right: 10, left: -10, bottom: 0 }}>
              <defs>
                <linearGradient id="gradCpu" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="var(--accent)" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="var(--accent)" stopOpacity={0} />
                </linearGradient>
                <linearGradient id="gradMem" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="var(--accent-2)" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="var(--accent-2)" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--line)" />
              <XAxis dataKey="time" tick={{ fontSize: 11 }} interval="preserveStartEnd" />
              <YAxis domain={[0, 100]} unit="%" tick={{ fontSize: 11 }} />
              <Tooltip formatter={(v: any) => `${Number(v).toFixed(1)}%`} />
              <Legend />
              <Area type="monotone" dataKey="cpu" name="CPU %" stroke="var(--accent)" fill="url(#gradCpu)" strokeWidth={2} dot={false} />
              <Area type="monotone" dataKey="memory" name={m.memoryPct} stroke="var(--accent-2)" fill="url(#gradMem)" strokeWidth={2} dot={false} />
            </AreaChart>
          </ResponsiveContainer>
        </div>

        <div className="card">
          <div className="mon-card-title mon-card-title--plain">{m.resourceUsage}</div>
          <ResponsiveContainer width="100%" height={160}>
            <RadialBarChart cx="50%" cy="50%" innerRadius="30%" outerRadius="90%" data={radialData} startAngle={90} endAngle={-270}>
              <PolarAngleAxis type="number" domain={[0, 100]} angleAxisId={0} tick={false} />
              <RadialBar dataKey="value" background angleAxisId={0} label={{ position: "insideStart", fill: "#fff", fontSize: 10 }} />
              <Tooltip formatter={(v: any) => `${Number(v).toFixed(1)}%`} />
              <Legend iconSize={10} />
            </RadialBarChart>
          </ResponsiveContainer>
          <div className="mon-gauges">
            <GaugeBar label="CPU" value={cpu ?? 0} />
            <GaugeBar label={m.memory} value={mem ?? 0} />
            <GaugeBar label={m.disk} value={disk ?? 0} color="var(--accent-3)" />
          </div>
        </div>
      </div>

      {system && (
        <div className="mon-row mon-row--thirds">
          <div className="card">
            <div className="mon-card-title mon-card-title--sm"><Wifi size={15} aria-hidden="true" /> {m.networkIo}</div>
            <GaugeBar
              label={fill(m.sent, { gb: fmt(system.network.bytes_sent_mb / 1024, 2) })}
              value={system.network.packets_sent}
              max={Math.max(system.network.packets_sent, system.network.packets_recv, 1)}
              unit={m.packets}
            />
            <GaugeBar
              label={fill(m.received, { gb: fmt(system.network.bytes_recv_mb / 1024, 2) })}
              value={system.network.packets_recv}
              max={Math.max(system.network.packets_sent, system.network.packets_recv, 1)}
              unit={m.packets}
              color="var(--accent-3)"
            />
          </div>

          <div className="card">
            <div className="mon-card-title mon-card-title--sm"><Cpu size={15} aria-hidden="true" /> {m.loadAverage}</div>
            <div className="mon-load">
              {(
                [
                  [m.minutes1, load1],
                  [m.minutes5, load5],
                  [m.minutes15, load15],
                ] as [string, number | undefined][]
              ).map(([label, val]) => (
                <div key={label} className="mon-load-cell">
                  <div className="mon-load-value">{val !== undefined ? fmt(val, 2) : "--"}</div>
                  <div className="mon-load-label">{label}</div>
                </div>
              ))}
            </div>
          </div>

          <div className="card">
            <div className="mon-card-title mon-card-title--sm"><HardDrive size={15} aria-hidden="true" /> {m.diskIo}</div>
            <GaugeBar
              label={m.read}
              value={system.disk_io.read_mb}
              max={Math.max(system.disk_io.read_mb, system.disk_io.write_mb, 1)}
              unit=" MB"
            />
            <GaugeBar
              label={m.write}
              value={system.disk_io.write_mb}
              max={Math.max(system.disk_io.read_mb, system.disk_io.write_mb, 1)}
              unit=" MB"
              color="var(--accent-3)"
            />
            <div className="mon-foot">
              {fill(m.diskUsed, { used: fmt(system.disk.used_gb, 1), total: fmt(system.disk.total_gb, 1), pct: fmt(system.disk.percent) })}
            </div>
          </div>
        </div>
      )}

      <div className="mon-row mon-row--halves">
        <div className="card">
          <div className="mon-card-title"><Server size={15} aria-hidden="true" /> {m.serviceHealth}</div>
          <div className="mon-service-list">
            {([
              ["PostgreSQL", services?.postgres ?? "unknown", <Database size={18} aria-hidden="true" />],
              ["Redis", services?.redis ?? "unknown", <Activity size={18} aria-hidden="true" />],
              ["AI Service", services?.ai_service ?? "unknown", <Activity size={18} aria-hidden="true" />],
              ["Backend", backendStatus, <Server size={18} aria-hidden="true" />],
            ] as [string, string, React.ReactNode][]).map(([name, status, icon]) => (
              <ServiceBadge key={name} name={name} status={status} label={statusLabel(status)} icon={icon} />
            ))}
          </div>
          {aiDash?.health?.warnings && aiDash.health.warnings.length > 0 && (
            <div className="monitor-warning">
              <AlertTriangle size={15} aria-hidden="true" /> {aiDash.health.warnings.join(" • ")}
            </div>
          )}
        </div>

        <div className="card">
          <div className="mon-card-title"><Database size={15} aria-hidden="true" /> {m.dbOverview}</div>
          {dbCounts ? (
            <ResponsiveContainer width="100%" height={180}>
              <BarChart
                data={[
                  { name: m.users, count: dbCounts.users ?? 0 },
                  { name: m.courses, count: dbCounts.courses ?? 0 },
                  { name: m.lessons, count: dbCounts.lessons ?? 0 },
                  { name: m.vocab, count: dbCounts.vocabulary_items ?? 0 },
                ]}
                margin={{ top: 0, right: 0, left: -20, bottom: 0 }}
              >
                <CartesianGrid strokeDasharray="3 3" stroke="var(--line)" />
                <XAxis dataKey="name" tick={{ fontSize: 11 }} />
                <YAxis tick={{ fontSize: 11 }} />
                <Tooltip />
                <Bar dataKey="count" name={m.rows} fill="var(--accent-2)" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          ) : (
            <div className="mon-empty">{m.noDbStats}</div>
          )}
        </div>
      </div>

      {aiDash && (
        <div className="card">
          <div className="mon-card-title">{m.aiMetrics}</div>
          <div className="card-grid">
            <StatCard label={m.aiCpu} value={aiCpu !== undefined ? `${fmt(aiCpu)}%` : "--"} />
            <StatCard label={m.aiMemory} value={aiMem !== undefined ? `${fmt(aiMem)}%` : "--"} accent="teal" />
            <StatCard
              label={m.threads}
              value={aiDash.process?.num_threads !== undefined ? String(aiDash.process.num_threads) : "--"}
              accent="berry"
            />
            <StatCard
              label={m.aiStatusLabel}
              value={aiDash.health?.healthy !== undefined ? (aiDash.health.healthy ? m.healthy : m.warning) : "--"}
              accent={aiDash.health?.healthy ? "teal" : "orange"}
              note={
                aiDash.health
                  ? fill(m.issueCount, { c: aiDash.health.critical_count ?? 0, w: aiDash.health.warning_count ?? 0 })
                  : undefined
              }
            />
          </div>
        </div>
      )}
    </div>
  );
};
