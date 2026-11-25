import React, { useCallback, useEffect, useState } from "react";
import { Activity, AlertTriangle, CheckCircle2, Clock, Gauge, RefreshCw } from "lucide-react";
import { DataTable } from "../components/DataTable";
import { EmptyState } from "../components/EmptyState";
import { SectionHeader } from "../components/SectionHeader";
import { StatCard } from "../components/StatCard";
import { StatusPill } from "../components/StatusPill";
import {
  getAiQualitySummary,
  type AiQualityEndpointBreakdown,
  type AiQualityFailure,
  type AiQualityResponse,
} from "../lib/aiQualityApi";

const pctTone = (value: number): "success" | "warning" | "danger" =>
  value >= 95 ? "success" : value >= 85 ? "warning" : "danger";

export const AiQualityDashboardPage = () => {
  const [data, setData] = useState<AiQualityResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      setData(await getAiQualitySummary(500));
    } catch (err: any) {
      setError(err?.message || "Failed to load AI quality metrics");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const summary = data?.summary;
  const hasEvents = Boolean(summary?.total_events);

  return (
    <div className="stack">
      <SectionHeader
        title="AI Quality"
        description="Lexi latency, correction quality, STT/TTS failures, and recent AI audit incidents."
        action={
          <button className="ghost-button small with-icon" onClick={load} disabled={loading}>
            <RefreshCw size={14} className={loading ? "is-spinning" : undefined} aria-hidden="true" />
            Refresh
          </button>
        }
      />

      {error && <div className="form-error">{error}</div>}
      {loading && <div className="loading">Loading AI quality metrics...</div>}

      {!loading && !hasEvents ? (
        <EmptyState
          icon={<AlertTriangle />}
          title="No AI audit events yet"
          description="Metrics will appear after ai-service starts ingesting audit events into backend-service."
        />
      ) : summary ? (
        <>
          <div className="card-grid">
            <StatCard
              label="Audit events"
              value={String(summary.total_events)}
              accent="ink"
              note={data?.source}
              icon={<Activity size={16} aria-hidden="true" />}
            />
            <StatCard
              label="Success rate"
              value={`${summary.success_rate.toFixed(1)}%`}
              accent="teal"
              variant="blue"
              icon={<CheckCircle2 size={16} aria-hidden="true" />}
            />
            <StatCard
              label="Avg latency"
              value={`${Math.round(summary.average_latency_ms)} ms`}
              accent="orange"
              icon={<Clock size={16} aria-hidden="true" />}
            />
            <StatCard
              label="P95 latency"
              value={`${Math.round(summary.p95_latency_ms)} ms`}
              accent="berry"
              variant="dark"
              icon={<Gauge size={16} aria-hidden="true" />}
            />
          </div>

          <div className="card-grid">
            <StatCard label="Lexi events" value={String(summary.lexi.events)} note={`${summary.lexi.failures} failures`} accent="teal" />
            <StatCard label="STT failures" value={String(summary.stt.failures)} accent="berry" />
            <StatCard label="TTS failures" value={String(summary.tts.failures)} accent="orange" />
            <StatCard label="Correction score" value={summary.correction.average_score ? summary.correction.average_score.toFixed(2) : "--"} note={`${summary.correction.events} events`} accent="ink" />
          </div>

          <div className="panel">
            <div className="cluster cluster--between" style={{ padding: "4px 4px 0" }}>
              <h3 className="panel-heading" style={{ padding: 0, margin: 0 }}>Endpoint breakdown</h3>
              <StatusPill tone="neutral" label={`${summary.endpoint_breakdown.length} endpoints`} />
            </div>
            {!summary.endpoint_breakdown.length ? (
              <EmptyState title="No endpoint data" description="No AI endpoint events were found in the selected window." />
            ) : (
              <DataTable<AiQualityEndpointBreakdown>
                rows={summary.endpoint_breakdown}
                columns={[
                  {
                    header: "Endpoint",
                    render: (row) => <span className="table-title">{row.endpoint}</span>,
                  },
                  {
                    header: "Events",
                    render: (row) => <span className="table-meta">{row.total}</span>,
                    align: "center",
                  },
                  {
                    header: "Failures",
                    render: (row) => (
                      <StatusPill
                        tone={row.failures ? "danger" : "success"}
                        label={`${row.failures} failed`}
                      />
                    ),
                    align: "center",
                  },
                  {
                    header: "Avg latency",
                    render: (row) => <span className="table-meta">{Math.round(row.average_latency_ms)} ms</span>,
                    align: "right",
                  },
                ]}
              />
            )}
          </div>

          <div className="panel">
            <div className="cluster cluster--between" style={{ padding: "4px 4px 0" }}>
              <h3 className="panel-heading" style={{ padding: 0, margin: 0 }}>Latest failures</h3>
              <StatusPill
                tone={summary.latest_failures.length ? "danger" : "success"}
                label={summary.latest_failures.length ? `${summary.latest_failures.length} incidents` : "0 incidents"}
              />
            </div>
            {!summary.latest_failures.length ? (
              <EmptyState title="No recent failures" description="The latest AI audit window has no failed events." />
            ) : (
              <DataTable<AiQualityFailure>
                rows={summary.latest_failures}
                columns={[
                  {
                    header: "Request",
                    render: (row) => (
                      <div>
                        <div className="table-title">{row.request_id || "unknown"}</div>
                        <div className="table-sub">{row.user_id || "unknown user"}</div>
                      </div>
                    ),
                  },
                  {
                    header: "Endpoint",
                    render: (row) => <span className="table-meta">{row.endpoint || "unknown"}</span>,
                  },
                  {
                    header: "Status",
                    render: (row) => <StatusPill tone="danger" label={row.status || "failed"} />,
                    align: "center",
                  },
                  {
                    header: "Latency",
                    render: (row) => <span className="table-meta">{row.latency_ms ? `${Math.round(row.latency_ms)} ms` : "--"}</span>,
                    align: "right",
                  },
                  {
                    header: "Error",
                    render: (row) => <span className="table-sub">{row.error || "No message"}</span>,
                  },
                ]}
              />
            )}
          </div>

          <div className="card cluster cluster--between" style={{ padding: "16px 22px" }}>
            <div className="cluster" style={{ gap: 10 }}>
              <StatusPill tone={pctTone(summary.success_rate)} label={`${summary.success_rate.toFixed(1)}% success`} />
              <StatusPill tone={summary.failure_count ? "danger" : "neutral"} label={`${summary.failure_count} failed`} />
            </div>
            <span className="table-sub">
              {summary.failure_count} failed of {summary.total_events} audited events.
            </span>
          </div>
        </>
      ) : null}
    </div>
  );
};
