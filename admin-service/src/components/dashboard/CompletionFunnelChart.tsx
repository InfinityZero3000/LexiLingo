import React from "react";
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Cell } from "recharts";

export type FunnelData = {
  stage: string;
  count: number;
  percentage: number;
};

type Props = {
  data: FunnelData[];
  loading?: boolean;
};

const COLORS = ["#3b82f6", "#10b981", "#f59e0b", "#ef4444"];

export const CompletionFunnelChart: React.FC<Props> = ({ data, loading }) => {
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
        <div className="loading-text">Chưa có dữ liệu funnel</div>
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
          <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
          <XAxis type="number" tick={{ fontSize: 12 }} />
          <YAxis 
            type="category" 
            dataKey="stage" 
            tick={{ fontSize: 12 }}
            width={90}
          />
          <Tooltip 
            formatter={(value: number, name, props: any) => [
              `${value.toLocaleString()} (${props.payload.percentage.toFixed(1)}%)`,
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
