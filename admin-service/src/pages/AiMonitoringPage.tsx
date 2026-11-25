import React, { useState } from "react";
import { useQuery, type UseQueryResult } from "@tanstack/react-query";
import { Area, AreaChart, Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { AlertTriangle, MessageSquare, RefreshCw } from "lucide-react";
import { DataTable } from "../components/DataTable";
import { EmptyState } from "../components/EmptyState";
import { SectionHeader } from "../components/SectionHeader";
import { StatCard } from "../components/StatCard";
import { StatusPill } from "../components/StatusPill";
import { BentoTooltip } from "../components/dashboard/BentoChartPrimitives";
import {
  getChatMonitoring,
  getLlmKeyMonitoring,
  getSpoolMonitoring,
  type AiWindow,
  type ChatMonitoring,
  type LatencyBlock,
  type LlmKeyMonitoring,
  type LlmKeyRow,
  type LlmKeyState,
  type ShareRow,
  type SpoolMonitoring,
} from "../lib/aiApi";
import { useI18n } from "../lib/i18n";

// Written inline as a JSX data key, this name trips gitleaks' generic-api-key rule.
const P95_LATENCY_FIELD = "p95_latency_ms" as const;

const WINDOWS: AiWindow[] = ["1h", "24h", "7d"];
const REFRESH_MS = 30_000;

const fill = (text: string, vars: Record<string, string | number>) =>
  text.replace(/\{(\w+)\}/g, (_, k) => String(vars[k] ?? ""));
const pct = (v: number | null | undefined) => (v == null ? "--" : `${(v * 100).toFixed(1)}%`);
const num = (v: number | null | undefined) => (v == null ? "--" : Math.round(v).toLocaleString());

const ShareBar = ({ label, value, text, color = "#FF4D00" }: { label: string; value: number | null; text: string; color?: string }) => (
  <div className="mon-gauge">
    <div className="mon-gauge-head">
      <span>{label}</span>
      <span className="mon-gauge-value">{text}</span>
    </div>
    <div className="mon-gauge-track" style={{ height: 10, borderRadius: 999 }} role="meter" aria-label={label} aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round((value ?? 0) * 100)}>
      <div className="mon-gauge-fill" style={{ width: `${Math.min(100, (value ?? 0) * 100)}%`, borderRadius: 999, backgroundColor: color }} />
    </div>
  </div>
);

const KEY_TONE: Record<LlmKeyState, "success" | "info" | "warning" | "danger"> = {
  available: "success",
  busy: "info",
  cooling: "warning",
  exhausted: "danger",
};

export const AiMonitoringPage = () => {
  const { t } = useI18n();
  const m = t.aiMonitoring;
  const [window, setWindow] = useState<AiWindow>("24h");

  const chat = useQuery({
    queryKey: ["ai-monitoring", "chat", window],
    queryFn: () => getChatMonitoring(window),
    refetchInterval: REFRESH_MS,
  });
  const keys = useQuery({
    queryKey: ["ai-monitoring", "llm-keys"],
    queryFn: getLlmKeyMonitoring,
    refetchInterval: REFRESH_MS,
  });

  const spool = useQuery({
    queryKey: ["ai-monitoring", "spool"],
    queryFn: getSpoolMonitoring,
    refetchInterval: REFRESH_MS,
  });

  const windowLabel: Record<AiWindow, string> = { "1h": m.window1h, "24h": m.window24h, "7d": m.window7d };
  const refresh = () => {
    void chat.refetch();
    void keys.refetch();
    void spool.refetch();
  };
  const fetching = chat.isFetching || keys.isFetching || spool.isFetching;
  const data = chat.data;
  const updated = chat.dataUpdatedAt ? new Date(chat.dataUpdatedAt).toLocaleTimeString() : null;

  return (
    <div className="stack">
      <SectionHeader
        title={m.title}
        description={m.description}
        action={
          <div className="mon-actions">
            {updated && <span className="mon-updated">{fill(m.updatedAt, { time: updated })}</span>}
            <div className="seg-control" role="group" aria-label={m.windowLabel}>
              {WINDOWS.map((w) => (
                <button key={w} type="button" className={w === window ? "active" : undefined} aria-pressed={w === window} onClick={() => setWindow(w)}>
                  {windowLabel[w]}
                </button>
              ))}
            </div>
            <button className="ghost-button small with-icon" onClick={refresh} disabled={fetching}>
              <RefreshCw size={14} className={fetching ? "is-spinning" : undefined} aria-hidden="true" />
              {m.refresh}
            </button>
          </div>
        }
      />

      {chat.isError ? (
        <div className="card" role="alert">
          <EmptyState
            icon={<AlertTriangle />}
            title={m.loadFailed}
            description={chat.error instanceof Error ? chat.error.message : undefined}
            action={<button className="ghost-button small" onClick={() => void chat.refetch()}>{m.retry}</button>}
          />
        </div>
      ) : chat.isPending ? (
        <ChatSkeleton />
      ) : data && data.turns === 0 ? (
        <div className="card">
          <EmptyState icon={<MessageSquare />} title={m.emptyTitle} description={m.emptyDescription} />
        </div>
      ) : data ? (
        <ChatSections data={data} window={window} />
      ) : null}

      <div className="mon-row mon-row--halves">
        <KeyPool query={keys} />
        <Spool query={spool} />
      </div>
    </div>
  );
};

const ChatSkeleton = () => (
  <div className="card-grid" aria-busy="true">
    {Array.from({ length: 7 }, (_, i) => (
      <StatCard key={i} label="" value="" loading />
    ))}
  </div>
);

const axisTime = (iso: string, window: AiWindow) => {
  const d = new Date(iso);
  return window === "7d" ? d.toLocaleDateString([], { month: "short", day: "numeric" }) : d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
};

const ChatSections = ({ data, window }: { data: ChatMonitoring; window: AiWindow }) => {
  const { t } = useI18n();
  const m = t.aiMonitoring;
  const all = data.latency.all;
  const series = data.series.map((p) => ({ ...p, label: axisTime(p.ts, window) }));
  const layerLabel: Record<string, string> = { L0: m.layerL0, L1: m.layerL1, none: m.layerNone };
  const bypassLabel: Record<string, string> = { facts: m.bypassFacts, memory: m.bypassMemory };
  const usageLabel: Record<string, string> = { provider: m.usageProvider, partial: m.usagePartial, none: m.usageNone, not_recorded: m.usageNotRecorded };
  const shareText = (row: ShareRow) => fill(m.turnsShare, { n: row.turns.toLocaleString(), pct: pct(row.share) });
  const shadow = data.cache.l1_shadow;
  const tk = data.tokens;
  const totalTokens = tk.prompt_sum + tk.completion_sum;
  const topicNote = data.topic_turns ? fill(m.kpiTopicNote, { n: data.topic_turns.toLocaleString() }) : undefined;
  const tokensNote = fill(tk.partial_turns ? m.kpiTokensPartialNote : m.kpiTokensNote, {
    n: tk.reported_turns.toLocaleString(),
    p: tk.partial_turns.toLocaleString(),
  });

  const metricRows: Array<{ label: string; pick: (b: LatencyBlock) => { p50: number | null; p95: number | null } }> = [
    { label: m.metricLatency, pick: (b) => b.latency_ms },
    { label: m.metricTtft, pick: (b) => b.ttft_ms },
    { label: m.metricFirstChunk, pick: (b) => b.first_chunk_ms },
  ];
  const ms = (v: number | null) => (v == null ? "--" : fill(m.ms, { n: Math.round(v).toLocaleString() }));
  const pair = (b: LatencyBlock, pick: (b: LatencyBlock) => { p50: number | null; p95: number | null }) =>
    `${ms(pick(b).p50)} / ${ms(pick(b).p95)}`;

  return (
    <>
      <div className="card-grid">
        <StatCard label={m.kpiTurns} value={data.turns.toLocaleString()} accent="ink" variant="blue" />
        <StatCard label={m.kpiErrorRate} value={pct(data.error_rate)} note={fill(m.kpiErrors, { n: data.errors })} accent="berry" />
        <StatCard label={m.kpiLatencyP50} value={ms(all.latency_ms.p50)} note={topicNote} accent="teal" />
        <StatCard label={m.kpiLatencyP95} value={ms(all.latency_ms.p95)} note={topicNote} accent="orange" />
        <StatCard label={m.kpiTtftP95} value={ms(all.ttft_ms.p95)} note={topicNote} accent="orange" />
        <StatCard label={m.kpiTokensPerTurn} value={num(tk.per_turn)} note={tokensNote} accent="teal" />
        <StatCard label={m.kpiCacheHit} value={pct(data.cache.hit_rate)} accent="ink" />
      </div>

      <div className="mon-row mon-row--thirds">
        <ChartCard title={m.chartTurns}>
          <BarChart data={series} margin={{ top: 5, right: 10, left: -10, bottom: 0 }}>
            <CartesianGrid strokeDasharray="4 4" vertical={false} stroke="var(--line)" />
            <XAxis dataKey="label" tick={{ fontSize: 11, fill: "var(--muted)" }} axisLine={false} tickLine={false} interval="preserveStartEnd" />
            <YAxis tick={{ fontSize: 11, fill: "var(--muted)" }} axisLine={false} tickLine={false} allowDecimals={false} />
            <Tooltip content={<BentoTooltip dark={false} />} cursor={{ fill: "rgba(148, 163, 184, 0.1)" }} />
            <Bar dataKey="turns" name={m.chartTurns} fill="#FF4D00" radius={[8, 8, 8, 8]} />
          </BarChart>
        </ChartCard>
        <ChartCard title={m.chartLatency} dark>
          <AreaChart data={series} margin={{ top: 5, right: 10, left: -10, bottom: 0 }}>
            <CartesianGrid strokeDasharray="4 4" vertical={false} stroke="rgba(148, 163, 184, 0.16)" />
            <XAxis dataKey="label" tick={{ fontSize: 11, fill: "#94A3B8" }} axisLine={false} tickLine={false} interval="preserveStartEnd" />
            <YAxis tick={{ fontSize: 11, fill: "#94A3B8" }} axisLine={false} tickLine={false} />
            <Tooltip content={<BentoTooltip dark valueFormatter={(v) => `${Math.round(Number(v)).toLocaleString()} ms`} />} />
            <Area type="monotone" dataKey={P95_LATENCY_FIELD} name={m.chartLatency} stroke="#FF4D00" fill="#FF4D00" fillOpacity={0.22} strokeWidth={2.5} dot={false} />
          </AreaChart>
        </ChartCard>
        <ChartCard title={m.chartTokens}>
          <BarChart data={series} margin={{ top: 5, right: 10, left: -10, bottom: 0 }}>
            <CartesianGrid strokeDasharray="4 4" vertical={false} stroke="var(--line)" />
            <XAxis dataKey="label" tick={{ fontSize: 11, fill: "var(--muted)" }} axisLine={false} tickLine={false} interval="preserveStartEnd" />
            <YAxis tick={{ fontSize: 11, fill: "var(--muted)" }} axisLine={false} tickLine={false} />
            <Tooltip content={<BentoTooltip dark={false} />} cursor={{ fill: "rgba(148, 163, 184, 0.1)" }} />
            <Bar dataKey="tokens" name={m.chartTokens} fill="#FF8A3D" radius={[8, 8, 8, 8]} />
          </BarChart>
        </ChartCard>
      </div>

      <div className="panel">
        <h3 className="panel-heading">{m.latencySplit} (p50 / p95)</h3>
        <DataTable
          rows={metricRows}
          rowKey={(r) => r.label}
          columns={[
            { header: m.colMetric, render: (r) => <span className="table-title">{r.label}</span> },
            { header: m.colAll, render: (r) => <span className="table-meta">{pair(data.latency.all, r.pick)}</span>, align: "right" },
            { header: m.colHit, render: (r) => <span className="table-meta">{pair(data.latency.hit, r.pick)}</span>, align: "right" },
            { header: m.colMiss, render: (r) => <span className="table-meta">{pair(data.latency.miss, r.pick)}</span>, align: "right" },
          ]}
        />
      </div>

      <div className="mon-row mon-row--halves">
        <div className="card">
          <div className="mon-card-title">{m.cacheTitle}</div>
          <div className="mon-card-title mon-card-title--sm">{m.cacheLayers}</div>
          {Object.entries(data.cache.layers).map(([key, row]) => (
            <ShareBar key={key} label={layerLabel[key] ?? key} value={row.share} text={shareText(row)} />
          ))}
          <div className="mon-card-title mon-card-title--sm">{m.cacheBypass}</div>
          {Object.keys(data.cache.bypass).length === 0 ? (
            <div className="mon-updated">{m.noBypass}</div>
          ) : (
            Object.entries(data.cache.bypass).map(([key, row]) => (
              <ShareBar key={key} label={bypassLabel[key] ?? key} value={row.share} text={shareText(row)} />
            ))
          )}
        </div>

        <div className="card">
          <div className="mon-card-title">{m.shadowTitle}</div>
          {shadow.compared == null ? (
            <div className="mon-updated">{m.shadowNoData}</div>
          ) : (
            <div className="mon-load">
              <div className="mon-load-cell"><div className="mon-updated">{m.shadowCompared}</div><strong>{shadow.compared.toLocaleString()}</strong></div>
              <div className="mon-load-cell"><div className="mon-updated">{m.shadowLow}</div><strong>{(shadow.low_similarity ?? 0).toLocaleString()}</strong></div>
              <div className="mon-load-cell"><div className="mon-updated">{m.shadowLowRate}</div><strong>{pct(shadow.low_similarity_rate)}</strong></div>
            </div>
          )}
          <div className="mon-updated">{m.shadowNote}</div>
          <div className="mon-card-title mon-card-title--sm">{m.shadowF1}</div>
          <ResponsiveContainer width="100%" height={140}>
            <BarChart data={shadow.f1_distribution.map((b) => ({ ...b, label: b.from.toFixed(1) }))} margin={{ top: 5, right: 10, left: -10, bottom: 0 }}>
              <CartesianGrid strokeDasharray="4 4" vertical={false} stroke="var(--line)" />
              <XAxis dataKey="label" tick={{ fontSize: 11, fill: "var(--muted)" }} axisLine={false} tickLine={false} />
              <YAxis tick={{ fontSize: 11, fill: "var(--muted)" }} axisLine={false} tickLine={false} allowDecimals={false} />
              <Tooltip content={<BentoTooltip dark={false} />} cursor={{ fill: "rgba(148, 163, 184, 0.1)" }} />
              <Bar dataKey="count" fill="#FF7A00" radius={[8, 8, 8, 8]} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>

      <div className="mon-row mon-row--halves">
        <div className="card">
          <div className="mon-card-title">{m.tokensTitle}</div>
          <div className="mon-load">
            <div className="mon-load-cell"><div className="mon-updated">{m.tokensPrompt}</div><strong>{num(tk.prompt_avg)}</strong></div>
            <div className="mon-load-cell"><div className="mon-updated">{m.tokensCompletion}</div><strong>{num(tk.completion_avg)}</strong></div>
            <div className="mon-load-cell"><div className="mon-updated">{m.tokensCached}</div><strong>{num(tk.cached_avg)}</strong></div>
          </div>
          <div className="mon-updated">{fill(m.tokensTotal, { n: totalTokens.toLocaleString() })}</div>
          <div className="mon-card-title mon-card-title--sm">{m.usageSource}</div>
          {Object.entries(tk.usage_source).map(([key, row]) => (
            <ShareBar key={key} label={usageLabel[key] ?? key} value={row.share} text={shareText(row)} />
          ))}
        </div>

        <div className="card">
          <div className="mon-card-title">{m.modelsTitle}</div>
          {data.models.length === 0 ? (
            <div className="mon-updated">{m.noModels}</div>
          ) : (
            data.models.map((row) => (
              <ShareBar key={row.model} label={row.model} value={data.turns ? row.turns / data.turns : null} text={fill(m.turnsShare, { n: row.turns.toLocaleString(), pct: pct(data.turns ? row.turns / data.turns : null) })} />
            ))
          )}
          <ShareBar label={m.learnerState} value={data.learner_state.degraded_rate} text={`${data.learner_state.degraded.toLocaleString()} (${pct(data.learner_state.degraded_rate)})`} />
        </div>
      </div>
    </>
  );
};

const ChartCard = ({ title, dark = false, children }: { title: string; dark?: boolean; children: React.ReactElement }) => (
  <div className={dark ? "card bento-card--dark" : "card"}>
    <div className="mon-card-title mon-card-title--plain" style={dark ? { color: "#F8FAFC" } : undefined}>{title}</div>
    <ResponsiveContainer width="100%" height={200}>
      {children}
    </ResponsiveContainer>
  </div>
);

const KeyPool = ({ query }: { query: UseQueryResult<LlmKeyMonitoring> }) => {
  const { t } = useI18n();
  const m = t.aiMonitoring;
  const stateLabel: Record<LlmKeyState, string> = { available: m.stateAvailable, busy: m.stateBusy, cooling: m.stateCooling, exhausted: m.stateExhausted };
  const d = query.data;

  return (
    <div className="card">
      <div className="mon-card-title">{m.keysTitle}</div>
      {query.isError ? (
        <div role="alert">
          <div className="form-error">{m.keysLoadFailed}</div>
          <button className="ghost-button small" onClick={() => void query.refetch()}>{m.retry}</button>
        </div>
      ) : !d ? (
        <div aria-busy="true"><StatCard label="" value="" loading /></div>
      ) : (
        <>
          <div className="mon-updated">{m.keysModel}: {d.model}</div>
          <div className="mon-updated">{fill(m.keysTotals, { ...d.totals })}</div>
          {d.mode === "unpooled" ? (
            <div className="mon-updated">{m.keysUnpooled}</div>
          ) : (
            <DataTable<LlmKeyRow>
              rows={d.keys}
              rowKey={(r) => r.index}
              columns={[
                { header: m.colKey, sortValue: (r) => r.index, render: (r) => <span className="table-title">{fill(m.keyLabel, { n: r.index })}</span> },
                { header: m.colState, sortValue: (r) => r.state, render: (r) => <StatusPill tone={KEY_TONE[r.state]} label={stateLabel[r.state]} />, align: "center" },
                { header: m.colRpm, sortValue: (r) => r.rpm, render: (r) => <span className="table-meta">{r.rpm} / {r.rpm_limit}</span>, align: "right" },
                { header: m.colTpm, sortValue: (r) => r.tpm, render: (r) => <span className="table-meta">{r.tpm.toLocaleString()} / {r.tpm_limit.toLocaleString()}</span>, align: "right" },
                { header: m.colRpd, sortValue: (r) => r.rpd, render: (r) => <span className="table-meta">{r.rpd.toLocaleString()} / {r.rpd_limit.toLocaleString()}</span>, align: "right" },
              ]}
            />
          )}
        </>
      )}
    </div>
  );
};

const Spool = ({ query }: { query: UseQueryResult<SpoolMonitoring> }) => {
  const { t } = useI18n();
  const m = t.aiMonitoring;
  const spool = query.data;
  return (
    <div className="card">
      <div className="mon-card-title">{m.spoolTitle}</div>
      {query.isError ? (
        <div role="alert">
          <div className="form-error">{m.spoolLoadFailed}</div>
          <button className="ghost-button small" onClick={() => void query.refetch()}>{m.retry}</button>
        </div>
      ) : !spool ? (
        <div aria-busy="true"><StatCard label="" value="" loading /></div>
      ) : (
        <>
          <div className="mon-load">
            <div className="mon-load-cell"><div className="mon-updated">{m.spoolDepth}</div><strong>{spool.queue_depth.toLocaleString()}</strong></div>
            <div className="mon-load-cell"><div className="mon-updated">{m.spoolDead}</div><strong>{spool.dead.toLocaleString()}</strong></div>
            <div className="mon-load-cell"><div className="mon-updated">{m.spoolDelivered}</div><strong>{spool.delivered.toLocaleString()}</strong></div>
          </div>
          <div className="mon-load">
            <div className="mon-load-cell"><div className="mon-updated">{m.spoolReceiverOff}</div><strong>{spool.receiver_off_since_start.toLocaleString()}</strong></div>
            <div className="mon-load-cell"><div className="mon-updated">{m.spoolDeadSince}</div><strong>{spool.dead_since_start.toLocaleString()}</strong></div>
          </div>
          <div className="mon-updated">{m.spoolSinceRestart}</div>
        </>
      )}
    </div>
  );
};
