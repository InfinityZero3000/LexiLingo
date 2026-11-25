import React from "react";
import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Legend,
} from "recharts";
import { Skeleton } from "../Skeleton";
import { BentoChartDefs, BentoTooltip } from "./BentoChartPrimitives";

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

const formatAxisDate = (value: unknown): string => {
  const date = new Date(String(value ?? ""));
  if (Number.isNaN(date.getTime())) return "";
  return `${date.getDate()}/${date.getMonth() + 1}`;
};

const formatTooltipDate = (value: string | number): string => {
  const date = new Date(String(value ?? ""));
  if (Number.isNaN(date.getTime())) return String(value ?? "");
  return date.toLocaleDateString("vi-VN");
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
    return <div className="chart-state error">Không tải được dữ liệu.</div>;
  }

  if (!data || data.length === 0) {
    return <div className="chart-state">Chưa có dữ liệu</div>;
  }

  return (
    <div className="chart-container" style={{ position: "relative" }}>
      <BentoChartDefs />
      <ResponsiveContainer width="100%" height={300}>
        <AreaChart data={data} margin={{ top: 10, right: 16, left: 0, bottom: 4 }}>
          <CartesianGrid
            strokeDasharray="4 4"
            vertical={false}
            stroke="rgba(148, 163, 184, 0.16)"
          />
          <XAxis
            dataKey="date"
            axisLine={false}
            tickLine={false}
            tickMargin={10}
            tick={{ fontSize: 12, fill: "currentColor", opacity: 0.65 }}
            tickFormatter={formatAxisDate}
          />
          <YAxis
            axisLine={false}
            tickLine={false}
            tickMargin={8}
            tick={{ fontSize: 12, fill: "currentColor", opacity: 0.65 }}
          />
          <Tooltip
            content={
              <BentoTooltip
                labelFormatter={formatTooltipDate}
                valueFormatter={(value) => Number(value ?? 0).toLocaleString()}
              />
            }
            cursor={{ stroke: "#FF4D00", strokeWidth: 1.5, strokeDasharray: "4 4" }}
          />
          <Legend
            iconType="circle"
            iconSize={8}
            wrapperStyle={{ fontSize: 12, paddingTop: 8 }}
          />
          <Area
            type="monotone"
            dataKey="total_users"
            stroke="#FF4D00"
            strokeWidth={3}
            fill="url(#bentoBlueArea)"
            dot={false}
            activeDot={{ r: 6, strokeWidth: 3, stroke: "#ffffff", fill: "#FF4D00" }}
            name="Tổng người dùng"
          />
          <Area
            type="monotone"
            dataKey="new_users"
            stroke="#FF9F43"
            strokeWidth={2.5}
            fill="url(#bentoLimeArea)"
            dot={false}
            activeDot={{ r: 5, strokeWidth: 2, stroke: "#ffffff", fill: "#FF9F43" }}
            name="Người dùng mới"
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
};
