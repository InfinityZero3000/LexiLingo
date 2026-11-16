import React from "react";
import { AlertTriangle, CheckCircle2 } from "lucide-react";

import { StatusPill } from "./StatusPill";
import { useI18n } from "../lib/i18n";
import {
  readingPassageRows,
  safeHttpUrl,
  type IeltsProvenance,
  type PassageProblem,
} from "../lib/ieltsProvenance";

const fill = (template: string, values: Record<string, string | number>) =>
  template.replace(/\{(\w+)\}/g, (_, key: string) => String(values[key] ?? ""));

export const IeltsProvenancePanel = ({
  content,
  provenance,
}: {
  content: unknown;
  provenance: IeltsProvenance;
}) => {
  const { t } = useI18n();
  const p = t.ieltsProvenance;
  const rows = readingPassageRows(content, provenance);
  const blocked = rows.filter((row) => row.problem).length;

  const describe = (problem: PassageProblem): string => {
    switch (problem.kind) {
      case "missing":
        return p.problemMissing;
      case "invalid_license":
        return fill(p.problemInvalid, { got: problem.got });
      case "forbidden_license":
        return fill(p.problemForbidden, { license: problem.license });
      case "missing_field":
        return fill(p.problemField, { license: problem.license, field: problem.field });
    }
  };

  return (
    <div className="panel stack" data-testid="ielts-provenance">
      <div>
        <strong>{p.title}</strong>
        <p className="table-meta">{p.description}</p>
      </div>
      {rows.length === 0 ? (
        <p className="table-meta">{p.noPassages}</p>
      ) : (
        <>
          {blocked > 0 ? (
            <div className="form-error" role="alert">
              <AlertTriangle size={14} /> {fill(p.blockedSummary, { count: blocked })}
            </div>
          ) : (
            <div>
              <CheckCircle2 size={14} /> {p.okSummary}
            </div>
          )}
          <table>
            <thead>
              <tr>
                <th>{fill(p.passage, { n: "" }).trim()}</th>
                <th>{p.license}</th>
                <th>{p.attribution}</th>
                <th>{p.source}</th>
                <th>{p.adapted}</th>
                <th>{p.retrieved}</th>
              </tr>
            </thead>
            <tbody>
              {rows.map(({ order, title, entry, problem }) => {
                const link = safeHttpUrl(entry?.source_url);
                return (
                  <React.Fragment key={order}>
                    <tr data-testid={`passage-${order}`}>
                      <td>
                        {fill(p.passage, { n: order })}
                        {title && <div className="table-meta">{title}</div>}
                      </td>
                      <td>
                        {entry?.license_id ? (
                          <StatusPill tone={problem ? "danger" : "success"} label={entry.license_id} />
                        ) : (
                          <StatusPill tone="danger" label={p.none} />
                        )}
                      </td>
                      <td>{entry?.attribution?.trim() || <span className="table-meta">{p.none}</span>}</td>
                      <td>
                        {link ? (
                          <a href={link} target="_blank" rel="noopener noreferrer">
                            {p.openSource}
                          </a>
                        ) : (
                          <span className="table-meta">{entry?.source_url || p.none}</span>
                        )}
                      </td>
                      <td>
                        <StatusPill
                          tone={entry?.adapted ? "info" : "neutral"}
                          label={entry?.adapted ? p.adapted : p.notAdapted}
                        />
                      </td>
                      <td className="table-meta">
                        {entry?.retrieved_at ? new Date(entry.retrieved_at).toLocaleDateString() : p.none}
                      </td>
                    </tr>
                    {problem && (
                      <tr>
                        <td colSpan={6} className="form-error" role="alert">
                          <AlertTriangle size={14} /> {describe(problem)}
                        </td>
                      </tr>
                    )}
                  </React.Fragment>
                );
              })}
            </tbody>
          </table>
        </>
      )}
    </div>
  );
};
