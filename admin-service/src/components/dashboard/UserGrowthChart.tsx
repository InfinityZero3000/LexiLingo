import React from "react";
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend } from "recharts";

export type UserGrowthData = {
  date: string;
  new_users: number;
  total_users: number;
};

type Props = {
  data: UserGrowthData[];
  loading?: boolean;
};

export const UserGrowthChart: React.FC<Props> = ({ data, loading }) => {
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
        <LineChart data={data} margin={{ top: 5, right: 20, left: 0, bottom: 5 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
          <XAxis 
            dataKey="date" 
            tick={{ fontSize: 12 }}
            tickFormatter={(value) => {
              const date = new Date(value);
              return `${date.getDate()}/${date.getMonth() + 1}`;
            }}
          />
          <YAxis tick={{ fontSize: 12 }} />
          <Tooltip 
            labelFormatter={(value) => {
              const date = new Date(value);
              return date.toLocaleDateString("vi-VN");
            }}
            formatter={(value: number) => [value.toLocaleString(), ""]}
          />
          <Legend />
          <Line 
            type="monotone" 
            dataKey="new_users" 
            stroke="#3b82f6" 
            strokeWidth={2}
            name="Người dùng mới"
            dot={{ r: 3 }}
            activeDot={{ r: 5 }}
          />
          <Line 
            type="monotone" 
            dataKey="total_users" 
            stroke="#10b981" 
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
