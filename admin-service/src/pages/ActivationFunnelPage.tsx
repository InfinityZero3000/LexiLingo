import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { SectionHeader } from "../components/SectionHeader";
import { EmptyState } from "../components/EmptyState";
import { Skeleton } from "../components/Skeleton";
import { getActivationFunnel, type RetentionCell } from "../lib/analyticsApi";
import { useI18n } from "../lib/i18n";

const WINDOWS = [30, 90, 180, 365];
const messageOf = (err: unknown, fallback: string) => (err instanceof Error && err.message ? err.message : fallback);
const pct = (v: number | null) => (v === null ? null : `${v}%`);

export const ActivationFunnelPage = () => {
  const { t } = useI18n();
  const [days, setDays] = useState(90);
  const q = useQuery({ queryKey: ["activation-funnel", days], queryFn: () => getActivationFunnel(days) });
  const text = t.activationFunnel;
  const steps = q.data?.steps ?? [];
  const cohorts = q.data?.cohorts ?? [];
  const empty = !!q.data && (steps[0]?.count ?? 0) === 0;

  const cell = (c: RetentionCell) =>
    c.rate === null ? (
      <span className="cohort-cell-muted" title={text.notYet}>—</span>
    ) : (
      <span title={`${c.retained} / ${c.eligible}`}>{pct(c.rate)}</span>
    );

  return (
    <div className="stack">
      <SectionHeader
        title={text.title}
        description={text.description}
        action={
          <select className="filter-select" value={days} onChange={(e) => setDays(Number(e.target.value))} aria-label={text.window}>
            {WINDOWS.map((d) => (
              <option key={d} value={d}>{text.windowDays.replace("{days}", String(d))}</option>
            ))}
          </select>
        }
      />

      {q.error && (
        <div className="form-error" role="alert">
          {messageOf(q.error, text.loadFailed)}{" "}
          <button type="button" className="btn btn-ghost" onClick={() => q.refetch()}>{text.retry}</button>
        </div>
      )}

      {q.isLoading && (
        <div className="panel" aria-busy="true">
          <Skeleton height={28} />
          <Skeleton height={28} />
          <Skeleton height={28} />
        </div>
      )}

      {empty && (
        <div className="panel">
          <EmptyState title={text.emptyTitle} description={text.emptyDescription} />
        </div>
      )}

      {q.data && !empty && (
        <>
          <div className="panel">
            <h3 className="panel-heading">{text.funnelTitle}</h3>
            <p className="funnel-note">{text.funnelHint}</p>
            <ol className="funnel-list">
              {steps.map((s) => {
                const width = Math.min(100, s.pct_of_first ?? 0);
                return (
                  <li key={s.key} className="funnel-row" title={s.definition}>
                    <div className="funnel-head">
                      <strong>{text.steps[s.key]}</strong>
                      <span>
                        <strong>{s.count.toLocaleString()}</strong>
                        {s.pct_of_first !== null && <span className="text-muted"> · {pct(s.pct_of_first)} {text.ofFirst}</span>}
                        {s.pct_of_previous !== null && <span className="text-muted"> · {pct(s.pct_of_previous)} {text.ofPrevious}</span>}
                      </span>
                    </div>
                    <div className="funnel-track" role="img" aria-label={`${text.steps[s.key]}: ${s.count}`}>
                      <div className="funnel-bar" style={{ width: `${width}%` }} />
                    </div>
                    {s.breakdown && (
                      <span className="funnel-note">
                        {text.viaGoogle
                          .replace("{google}", String(s.breakdown.with_google_provider))
                          .replace("{other}", String(s.breakdown.without_google_provider))}
                      </span>
                    )}
                    <span className="funnel-note">{s.definition}</span>
                  </li>
                );
              })}
            </ol>
          </div>

          <div className="panel">
            <h3 className="panel-heading">{text.cohortsTitle}</h3>
            <p className="funnel-note">{q.data.retention_definition}</p>
            <div style={{ overflowX: "auto" }}>
              <table className="cohort-table">
                <thead>
                  <tr>
                    <th>{text.cohortWeek}</th>
                    <th>{text.cohortSize}</th>
                    <th>D1</th>
                    <th>D7</th>
                    <th>D30</th>
                  </tr>
                </thead>
                <tbody>
                  {cohorts.map((c) => (
                    <tr key={c.week_start}>
                      <td>{c.week_start}</td>
                      <td>{c.size}</td>
                      <td>{cell(c.d1)}</td>
                      <td>{cell(c.d7)}</td>
                      <td>{cell(c.d30)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </>
      )}
    </div>
  );
};
