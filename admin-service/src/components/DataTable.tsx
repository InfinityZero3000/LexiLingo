import React, { useState } from "react";

type SortValue = string | number | null | undefined;

export type Column<T> = {
  header: React.ReactNode;
  render: (row: T) => React.ReactNode;
  align?: "left" | "center" | "right";
  /** Sorts the rows already on screen. */
  sortValue?: (row: T) => SortValue;
  /** Server-side sort: clicking reports this key through `onSort`. */
  sortKey?: string;
};

export type Sort = { key: string; dir: "asc" | "desc" };

export const sortRows = <T,>(rows: T[], get: (row: T) => SortValue, dir: "asc" | "desc"): T[] => {
  const sign = dir === "asc" ? 1 : -1;
  return rows
    .map((row, i) => ({ row, i, v: get(row) }))
    .sort((a, b) => {
      const aNil = a.v == null || a.v === "";
      const bNil = b.v == null || b.v === "";
      if (aNil || bNil) return aNil === bNil ? a.i - b.i : aNil ? 1 : -1;
      const cmp =
        typeof a.v === "number" && typeof b.v === "number"
          ? a.v - b.v
          : String(a.v).localeCompare(String(b.v), undefined, { numeric: true, sensitivity: "base" });
      return cmp * sign || a.i - b.i;
    })
    .map((x) => x.row);
};

export const DataTable = <T,>({
  columns,
  rows,
  sort,
  onSort,
  rowKey,
}: {
  columns: Column<T>[];
  rows: T[];
  sort?: Sort;
  onSort?: (key: string) => void;
  rowKey?: (row: T) => string | number;
}) => {
  const [local, setLocal] = useState<Sort | null>(null);
  const active = sort ?? local;

  const keyOf = (col: Column<T>, idx: number) => col.sortKey ?? String(idx);
  const isSortable = (col: Column<T>) => !!col.sortValue || (!!col.sortKey && !!onSort);

  const toggle = (col: Column<T>, idx: number) => {
    const key = keyOf(col, idx);
    if (onSort && col.sortKey) return onSort(col.sortKey);
    setLocal((prev) => (prev?.key !== key ? { key, dir: "asc" } : prev.dir === "asc" ? { key, dir: "desc" } : null));
  };

  const activeIdx = active ? columns.findIndex((c, i) => keyOf(c, i) === active.key) : -1;
  const activeCol = activeIdx >= 0 ? columns[activeIdx] : undefined;
  const shown = active && activeCol?.sortValue && !onSort ? sortRows(rows, activeCol.sortValue, active.dir) : rows;

  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>
            {columns.map((col, idx) => {
              const dir = active && keyOf(col, idx) === active.key ? active.dir : null;
              return (
                <th
                  key={idx}
                  style={{ textAlign: col.align || "left" }}
                  aria-sort={isSortable(col) ? (dir === "asc" ? "ascending" : dir === "desc" ? "descending" : "none") : undefined}
                >
                  {isSortable(col) ? (
                    <button type="button" className="th-sort" data-dir={dir ?? undefined} onClick={() => toggle(col, idx)}>
                      {col.header}
                    </button>
                  ) : (
                    col.header
                  )}
                </th>
              );
            })}
          </tr>
        </thead>
        <tbody>
          {shown.map((row, idx) => (
            <tr key={rowKey ? rowKey(row) : idx}>
              {columns.map((col, cIdx) => (
                <td key={cIdx} style={{ textAlign: col.align || "left" }}>
                  {col.render(row)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
};
