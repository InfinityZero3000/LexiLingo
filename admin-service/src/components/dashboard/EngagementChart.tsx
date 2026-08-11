import React from "react";
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend } from "recharts";
import { Skeleton } from "../Skeleton";

export type EngagementData = {
  week: string;
  dau: number;
  wau: number;
  mau: number;
};

type Props = {
  data: EngagementData[];
  loading?: boolean;
  error?: boolean;
};

export const EngagementChart: React.FC<Props> = ({ data, loading, error }) => {
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
        Chưa có dữ liệu
      </div>
    );
  }

  return (
    <div className="chart-container">
      <ResponsiveContainer width="100%" height={300}>
        <BarChart data={data} margin={{ top: 5, right: 20, left: 0, bottom: 5 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="var(--line)" />
          <XAxis dataKey="week" tick={{ fontSize: 12 }} />
          <YAxis tick={{ fontSize: 12 }} />
          <Tooltip formatter={(value) => [Number(value ?? 0).toLocaleString(), ""]} />
          <Legend />
          <Bar dataKey="dau" fill="var(--accent)" name="DAU (Daily)" radius={[8, 8, 0, 0]} />
          <Bar dataKey="wau" fill="var(--accent-2)" name="WAU (Weekly)" radius={[8, 8, 0, 0]} />
          <Bar dataKey="mau" fill="var(--accent-3)" name="MAU (Monthly)" radius={[8, 8, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
};
