import React from "react";
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend } from "recharts";

export type EngagementData = {
  week: string;
  dau: number;
  wau: number;
  mau: number;
};

type Props = {
  data: EngagementData[];
  loading?: boolean;
};

export const EngagementChart: React.FC<Props> = ({ data, loading }) => {
  if (loading) {
    return (
      <div className="chart-container" style={{ height: 300, display: "flex", alignItems: "center", justifyContent: "center" }}>
        <div className="loading-text">Đang tải dữ liệu...</div>
      </div>
    );
  }

  if (!data || data.length === 0) {
    return (
      <div className="chart-container" style={{ height: 300, display: "flex", alignItems: "center", justifyContent: "center" }}>
        <div className="loading-text">Chưa có dữ liệu</div>
      </div>
    );
  }

  return (
    <div className="chart-container">
      <ResponsiveContainer width="100%" height={300}>
        <BarChart data={data} margin={{ top: 5, right: 20, left: 0, bottom: 5 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
          <XAxis dataKey="week" tick={{ fontSize: 12 }} />
          <YAxis tick={{ fontSize: 12 }} />
          <Tooltip formatter={(value: number) => [value.toLocaleString(), ""]} />
          <Legend />
          <Bar dataKey="dau" fill="#3b82f6" name="DAU (Daily)" radius={[8, 8, 0, 0]} />
          <Bar dataKey="wau" fill="#10b981" name="WAU (Weekly)" radius={[8, 8, 0, 0]} />
          <Bar dataKey="mau" fill="#8b5cf6" name="MAU (Monthly)" radius={[8, 8, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
};
