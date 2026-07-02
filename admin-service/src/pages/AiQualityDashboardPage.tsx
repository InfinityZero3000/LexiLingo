import React, { useCallback, useEffect, useState } from "react";
import { AlertTriangle, RefreshCw } from "lucide-react";
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
          <button className="btn-secondary btn-sm" onClick={load} disabled={loading}>
            <RefreshCw size={14} /> Refresh
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
            <StatCard label="Audit events" value={String(summary.total_events)} accent="ink" note={data?.source} />
            <StatCard label="Success rate" value={`${summary.success_rate.toFixed(1)}%`} accent="teal" />
            <StatCard label="Avg latency" value={`${Math.round(summary.average_latency_ms)} ms`} accent="orange" />
            <StatCard label="P95 latency" value={`${Math.round(summary.p95_latency_ms)} ms`} accent="berry" />
          </div>

          <div className="card-grid">
            <StatCard label="Lexi events" value={String(summary.lexi.events)} note={`${summary.lexi.failures} failures`} accent="teal" />
            <StatCard label="STT failures" value={String(summary.stt.failures)} accent="berry" />
            <StatCard label="TTS failures" value={String(summary.tts.failures)} accent="orange" />
            <StatCard label="Correction score" value={summary.correction.average_score ? summary.correction.average_score.toFixed(2) : "--"} note={`${summary.correction.events} events`} accent="ink" />
          </div>

          <div className="panel">
            <h3 style={{ padding: "16px 16px 0" }}>Endpoint breakdown</h3>
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
                        label={String(row.failures)}
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
            <h3 style={{ padding: "16px 16px 0" }}>Latest failures</h3>
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

          <div className="panel-inner">
            <StatusPill tone={pctTone(summary.success_rate)} label={`${summary.success_rate.toFixed(1)}% success`} />
            <span className="table-sub" style={{ marginLeft: 10 }}>
              {summary.failure_count} failed of {summary.total_events} audited events.
            </span>
          </div>
        </>
      ) : null}
    </div>
  );
};
