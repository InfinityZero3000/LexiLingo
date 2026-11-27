import React from "react";
import { StatusPill } from "./StatusPill";
import type { LlmKeyMonitoring, MonitoringDashboard } from "../lib/aiApi";
import { useI18n } from "../lib/i18n";

// Only what the AI service reports: there is no endpoint that lists its local models.
export const LiveAiModels = ({ llm, monitor }: { llm: LlmKeyMonitoring | null; monitor: MonitoringDashboard | null }) => {
  const { t } = useI18n();
  const traceCag = monitor?.trace_cag;

  if (!llm && !traceCag) return <p className="text-small text-muted">{t.superDashboard.aiModelsUnavailable}</p>;

  return (
    <div className="mini-list">
      {llm && (
        <div className="pill-item" style={{ gap: 12 }}>
          <div style={{ minWidth: 0, overflowWrap: "anywhere" }}>
            <div className="mini-title">{llm.model}</div>
            <div className="mini-desc">{t.superDashboard.llmDesc.replace("{n}", String(llm.totals.keys))}</div>
          </div>
          <StatusPill tone="info" label="Groq" />
        </div>
      )}
      {traceCag && (
        <div className="pill-item" style={{ gap: 12 }}>
          <div style={{ minWidth: 0 }}>
            <div className="mini-title">TRACE-CAG</div>
            <div className="mini-desc">{traceCag.backend}</div>
          </div>
          <StatusPill tone={traceCag.status === "active" ? "success" : "warning"} label={traceCag.status} />
        </div>
      )}
    </div>
  );
};
