import { useState } from "react";
import { useConfirm } from "./ConfirmDialog";
import type { Column } from "./DataTable";
import { describeDeletionError, fillText } from "../lib/deletion";
import { useI18n } from "../lib/i18n";
import { runSequential } from "../lib/runSequential";

const NAMES_SHOWN = 5;

/** Checkbox selection over the rows on screen. */
export const useRowSelection = <T,>(rows: T[], idOf: (row: T) => string, nameOf: (row: T) => string) => {
  const { t } = useI18n();
  const [ids, setIds] = useState<ReadonlySet<string>>(new Set());
  // Only rows still on screen count: an action must never reach a row that a
  // filter or a page change has hidden since it was ticked.
  const selected = rows.filter((row) => ids.has(idOf(row)));
  const all = rows.length > 0 && selected.length === rows.length;

  const toggle = (id: string) =>
    setIds((current) => {
      const next = new Set(current);
      if (!next.delete(id)) next.add(id);
      return next;
    });

  const column: Column<T> = {
    header: (
      <input
        type="checkbox"
        aria-label={t.deletion.selectAll}
        checked={all}
        onChange={() => setIds(all ? new Set() : new Set(rows.map(idOf)))}
      />
    ),
    render: (row) => (
      <input
        type="checkbox"
        aria-label={fillText(t.deletion.selectRow, { name: nameOf(row) })}
        checked={ids.has(idOf(row))}
        onChange={() => toggle(idOf(row))}
      />
    ),
  };

  return { selected, column, nameOf, clear: () => setIds(new Set()) };
};

export type BulkAction<T> = {
  label: string;
  /** What will happen, shown in the confirmation. */
  consequence: string;
  run: (row: T) => Promise<unknown>;
  /** A permanent action also asks the admin to type how many rows it hits. */
  danger?: boolean;
};

type Report = { done: number; failed: { name: string; message: string }[] };

export const BulkBar = <T,>({
  selection,
  actions,
  onDone,
}: {
  selection: ReturnType<typeof useRowSelection<T>>;
  actions: BulkAction<T>[];
  onDone: () => unknown;
}) => {
  const { t } = useI18n();
  const confirm = useConfirm();
  const [busy, setBusy] = useState(false);
  const [report, setReport] = useState<Report | null>(null);
  const { selected, nameOf } = selection;

  const start = async (action: BulkAction<T>) => {
    // A snapshot: what the dialog lists is exactly what runs.
    const rows = [...selected];
    const names = rows.slice(0, NAMES_SHOWN).map(nameOf).join(", ");
    const more = rows.length > NAMES_SHOWN ? fillText(t.deletion.andMore, { n: rows.length - NAMES_SHOWN }) : "";
    const ok = await confirm({
      title: fillText(t.deletion.bulkTitle, { action: action.label, n: rows.length }),
      message: `${names}${more}. ${action.consequence}`,
      confirmLabel: action.label,
      danger: action.danger,
      requireText: action.danger ? String(rows.length) : undefined,
    });
    if (!ok) return;
    setBusy(true);
    setReport(null);
    const refusals: Report["failed"] = [];
    const result = await runSequential(rows, async (row) => {
      try {
        await action.run(row);
      } catch (error) {
        refusals.push({ name: nameOf(row), message: describeDeletionError(error, t) });
        throw error;
      }
    });
    selection.clear();
    setReport({ done: result.succeeded.length, failed: refusals });
    setBusy(false);
    await onDone();
  };

  return (
    <>
      {selected.length > 0 && (
        <div className="bulk-bar" role="region" aria-live="polite">
          <span className="bulk-bar__count">{fillText(t.deletion.selected, { n: selected.length })}</span>
          {actions.map((action) => (
            <button
              key={action.label}
              type="button"
              className={action.danger ? "ghost-button small danger" : "ghost-button small"}
              disabled={busy}
              onClick={() => void start(action)}
            >
              {action.label}
            </button>
          ))}
          <button type="button" className="ghost-button small" disabled={busy} onClick={selection.clear}>
            {t.deletion.clear}
          </button>
        </div>
      )}
      {report && (
        <div className="bulk-report" role="status">
          <strong>{fillText(t.deletion.report, { done: report.done, failed: report.failed.length })}</strong>
          {report.failed.length > 0 && (
            <ul>
              {report.failed.map((item, index) => (
                <li key={index}>
                  {item.name}: {item.message}
                </li>
              ))}
            </ul>
          )}
          <button type="button" className="ghost-button small" onClick={() => setReport(null)}>
            {t.common.close}
          </button>
        </div>
      )}
    </>
  );
};
