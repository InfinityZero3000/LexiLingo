import React from "react";
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Cell } from "recharts";
import { Skeleton } from "../Skeleton";

export type FunnelData = {
  stage: string;
  count: number;
  percentage: number;
};

type Props = {
  data: FunnelData[];
  loading?: boolean;
  error?: boolean;
};

const COLORS = ["var(--accent)", "var(--accent-2)", "var(--accent-3)", "var(--accent-4)"];

export const CompletionFunnelChart: React.FC<Props> = ({ data, loading, error }) => {
  if (loading) {
    return (
      <div className="chart-container" aria-busy="true">
        <Skeleton height={300} />
      </div>
    );
  }

  if (error) {
    return (
      <div className="chart-state error">
        Không tải được dữ liệu.
      </div>
    );
  }

  if (!data || data.length === 0) {
    return (
      <div className="chart-state">
        Chưa có dữ liệu funnel
      </div>
    );
  }

  return (
    <div className="chart-container">
      <ResponsiveContainer width="100%" height={300}>
        <BarChart
          data={data}
          layout="vertical"
          margin={{ top: 5, right: 30, left: 100, bottom: 5 }}
        >
          <CartesianGrid strokeDasharray="3 3" stroke="var(--line)" />
          <XAxis type="number" tick={{ fontSize: 12 }} />
          <YAxis
            type="category"
            dataKey="stage"
            tick={{ fontSize: 12 }}
            width={90}
          />
          <Tooltip
            formatter={(value, _name, item) => [
              `${Number(value ?? 0).toLocaleString()} (${Number(item.payload?.percentage ?? 0).toFixed(1)}%)`,
              ""
            ]}
          />
          <Bar dataKey="count" radius={[0, 8, 8, 0]}>
            {data.map((_, index) => (
              <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
};
