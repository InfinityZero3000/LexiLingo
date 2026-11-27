import React, { useCallback, useEffect, useRef, useState } from "react";
import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  BarChart,
  Bar,
  Legend,
} from "recharts";
import { Activity, CheckCircle, AlertTriangle, XCircle, RefreshCw, Pause, Play, Database, Server, Wifi } from "lucide-react";
import { SectionHeader } from "../components/SectionHeader";
import { StatCard } from "../components/StatCard";
import { BentoTooltip } from "../components/dashboard/BentoChartPrimitives";
import {
  getServicesHealth,
  getDbStats,
  getRequestStats,
  type ServicesHealth,
  type DbStats,
  type RequestStats,
} from "../lib/aiApi";
import { useI18n } from "../lib/i18n";

// ─── Types ────────────────────────────────────────────────────────────────────

type TimePoint = {
  time: string;
  connections: number;
  requests: number;
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

const nowLabel = () =>
  new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });

const fill = (text: string, vars: Record<string, string | number>) =>
  text.replace(/\{(\w+)\}/g, (_, k) => String(vars[k] ?? ""));

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

  const [services, setServices] = useState<ServicesHealth | null>(null);
  const [db, setDb] = useState<DbStats | null>(null);
  const [reqStats, setReqStats] = useState<RequestStats | null>(null);
  const [history, setHistory] = useState<TimePoint[]>([]);
  const [loadState, setLoadState] = useState<LoadingState>("idle");
  const [lastUpdated, setLastUpdated] = useState<string>("");
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const [paused, setPaused] = useState(false);

  const fetchAll = useCallback(async () => {
    setLoadState("loading");
    try {
      const [svc, dbSt, rq] = await Promise.allSettled([
        getServicesHealth(),
        getDbStats(),
        getRequestStats(),
      ]);

      const svcVal = svc.status === "fulfilled" ? svc.value : null;
      const dbVal = dbSt.status === "fulfilled" ? dbSt.value : null;
      const rqVal = rq.status === "fulfilled" ? rq.value : null;

      setServices(svcVal);
      setDb(dbVal);
      setReqStats(rqVal);

      const label = nowLabel();
      setHistory((prev) => {
        const point: TimePoint = {
          time: label,
          connections: rqVal?.active_connections ?? 0,
          requests: rqVal?.requests_last_minute ?? 0,
        };
        const next = [...prev, point];
        return next.length > HISTORY_MAX ? next.slice(-HISTORY_MAX) : next;
      });

      setLastUpdated(label);
      // All three telemetry calls failed: say so instead of rendering calm "Unknown" cards.
      setLoadState([svc, dbSt, rq].every((r) => r.status === "rejected") ? "error" : "ok");
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

  const dbCounts = db?.counts;
  const m = t.monitoring;
  const statusLabel = (status: string) => {
    const tone = toneOf(status);
    return tone === "healthy" ? m.statusHealthy
      : tone === "unhealthy" ? m.statusUnhealthy
      : tone === "unreachable" ? m.statusUnreachable
      : m.statusUnknown;
  };
  const backendStatus = services ? "healthy" : "unknown";

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

      {loadState === "error" && (
        <div className="form-error" role="alert">
          {m.loadFailed}
        </div>
      )}

      <div className="card-grid">
        <StatCard
          label={m.backendStatus}
          value={statusLabel(backendStatus)}
          variant="blue"
          icon={<Server size={16} aria-hidden="true" />}
        />
        <StatCard
          label={m.dbStatus}
          value={statusLabel(services?.postgres ?? "unknown")}
          accent="teal"
          icon={<Database size={16} aria-hidden="true" />}
        />
        <StatCard
          label={m.aiStatus}
          value={statusLabel(services?.ai_service ?? "unknown")}
          accent="berry"
          icon={<Activity size={16} aria-hidden="true" />}
        />
        <StatCard
          label={m.connections}
          value={reqStats?.active_connections !== undefined ? String(reqStats.active_connections) : "--"}
          note={reqStats?.requests_last_minute !== undefined ? fill(m.reqPerMin, { n: reqStats.requests_last_minute }) : undefined}
          accent="ink"
          icon={<Wifi size={16} aria-hidden="true" />}
        />
      </div>

      {history.length > 0 && (
        <div className="card bento-card--dark">
          <div className="mon-card-title mon-card-title--plain" style={{ color: "#F8FAFC" }}>
            {m.connections} & {m.requests} ({HISTORY_MAX})
          </div>
          <ResponsiveContainer width="100%" height={200}>
            <AreaChart data={history} margin={{ top: 5, right: 10, left: -10, bottom: 0 }}>
              <defs>
                <linearGradient id="gradConn" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#FF4D00" stopOpacity={0.45} />
                  <stop offset="95%" stopColor="#FF4D00" stopOpacity={0} />
                </linearGradient>
                <linearGradient id="gradReq" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#FF9F43" stopOpacity={0.38} />
                  <stop offset="95%" stopColor="#FF9F43" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="4 4" vertical={false} stroke="rgba(148, 163, 184, 0.16)" />
              <XAxis dataKey="time" tick={{ fontSize: 11, fill: "#94A3B8" }} axisLine={false} tickLine={false} interval="preserveStartEnd" />
              <YAxis tick={{ fontSize: 11, fill: "#94A3B8" }} axisLine={false} tickLine={false} allowDecimals={false} />
              <Tooltip content={<BentoTooltip dark />} />
              <Legend wrapperStyle={{ fontSize: 12, color: "#CBD5E1" }} />
              <Area type="monotone" dataKey="connections" name={m.connections} stroke="#FF4D00" fill="url(#gradConn)" strokeWidth={2.5} dot={false} />
              <Area type="monotone" dataKey="requests" name={m.requests} stroke="#FF9F43" fill="url(#gradReq)" strokeWidth={2.5} dot={false} />
            </AreaChart>
          </ResponsiveContainer>
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
                <CartesianGrid strokeDasharray="4 4" vertical={false} stroke="var(--line)" />
                <XAxis dataKey="name" tick={{ fontSize: 11, fill: "var(--muted)" }} axisLine={false} tickLine={false} />
                <YAxis tick={{ fontSize: 11, fill: "var(--muted)" }} axisLine={false} tickLine={false} />
                <Tooltip content={<BentoTooltip dark={false} />} cursor={{ fill: "rgba(148, 163, 184, 0.1)" }} />
                <Bar dataKey="count" name={m.rows} fill="var(--accent)" radius={[10, 10, 10, 10]} />
              </BarChart>
            </ResponsiveContainer>
          ) : (
            <div className="mon-empty">{m.noDbStats}</div>
          )}
        </div>
      </div>
    </div>
  );
};
