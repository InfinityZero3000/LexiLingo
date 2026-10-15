import React from "react";
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend } from "recharts";
import { Skeleton } from "../Skeleton";

export type UserGrowthData = {
  date: string;
  new_users: number;
  total_users: number;
};

type Props = {
  data: UserGrowthData[];
  loading?: boolean;
  error?: boolean;
};

export const UserGrowthChart: React.FC<Props> = ({ data, loading, error }) => {
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
        <LineChart data={data} margin={{ top: 5, right: 20, left: 0, bottom: 5 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="var(--line)" />
          <XAxis 
            dataKey="date" 
            tick={{ fontSize: 12 }}
            tickFormatter={(value) => {
              const date = new Date(String(value ?? ""));
              if (Number.isNaN(date.getTime())) return "";
              return `${date.getDate()}/${date.getMonth() + 1}`;
            }}
          />
          <YAxis tick={{ fontSize: 12 }} />
          <Tooltip 
            labelFormatter={(value) => {
              const date = new Date(String(value ?? ""));
              return date.toLocaleDateString("vi-VN");
            }}
            formatter={(value) => [Number(value ?? 0).toLocaleString(), ""]}
          />
          <Legend />
          <Line 
            type="monotone" 
            dataKey="new_users" 
            stroke="var(--accent)" 
            strokeWidth={2}
            name="Người dùng mới"
            dot={{ r: 3 }}
            activeDot={{ r: 5 }}
          />
          <Line 
            type="monotone" 
            dataKey="total_users" 
            stroke="var(--accent-2)" 
            strokeWidth={2}
            name="Tổng người dùng"
            dot={{ r: 3 }}
            activeDot={{ r: 5 }}
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
};
