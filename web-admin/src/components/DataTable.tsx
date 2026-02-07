import React from "react";

export type Column<T> = {
  header: string;
  render: (row: T) => React.ReactNode;
  align?: "left" | "center" | "right";
};

export const DataTable = <T,>({
  columns,
  rows
}: {
  columns: Column<T>[];
  rows: T[];
}) => {
  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>
            {columns.map((col, idx) => (
              <th key={idx} style={{ textAlign: col.align || "left" }}>
                {col.header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, idx) => (
            <tr key={idx}>
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
