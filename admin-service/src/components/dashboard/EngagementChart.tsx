import React from "react";
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Legend,
} from "recharts";
import { Skeleton } from "../Skeleton";
import { BentoTooltip } from "./BentoChartPrimitives";

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
    return <div className="chart-state error">Không tải được dữ liệu.</div>;
  }

  if (!data || data.length === 0) {
    return <div className="chart-state">Chưa có dữ liệu</div>;
  }

  return (
    <div className="chart-container">
      <ResponsiveContainer width="100%" height={300}>
        <BarChart
          data={data}
          margin={{ top: 10, right: 16, left: 0, bottom: 4 }}
          barGap={6}
        >
          <CartesianGrid strokeDasharray="4 4" vertical={false} stroke="var(--line)" />
          <XAxis
            dataKey="week"
            axisLine={false}
            tickLine={false}
            tickMargin={10}
            tick={{ fontSize: 12, fill: "var(--muted)" }}
          />
          <YAxis
            axisLine={false}
            tickLine={false}
            tick={{ fontSize: 12, fill: "var(--muted)" }}
          />
          <Tooltip
            content={
              <BentoTooltip
                valueFormatter={(value) => Number(value ?? 0).toLocaleString()}
              />
            }
            cursor={{ fill: "rgba(255, 77, 0, 0.06)", radius: 12 }}
          />
          <Legend
            iconType="circle"
            iconSize={8}
            wrapperStyle={{ fontSize: 12, paddingTop: 8 }}
          />
          <Bar
            dataKey="dau"
            fill="#FF4D00"
            name="DAU (Daily)"
            radius={[10, 10, 10, 10]}
            maxBarSize={24}
          />
          <Bar
            dataKey="wau"
            fill="#FF8A3D"
            name="WAU (Weekly)"
            radius={[10, 10, 10, 10]}
            maxBarSize={24}
          />
          <Bar
            dataKey="mau"
            fill="#FDBA74"
            name="MAU (Monthly)"
            radius={[10, 10, 10, 10]}
            maxBarSize={24}
          />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
};
