import React from "react";
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Cell,
} from "recharts";
import { Skeleton } from "../Skeleton";
import { BentoTooltip } from "./BentoChartPrimitives";

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

const PALETTE = ["#FF4D00", "#FF7A00", "#FB923C", "#FDBA74", "#EA580C"];

export const CompletionFunnelChart: React.FC<Props> = ({ data, loading, error }) => {
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
    return <div className="chart-state">Chưa có dữ liệu funnel</div>;
  }

  const barChartHeight = Math.max(210, data.length * 46);

  return (
    <div className="chart-container">
      <ResponsiveContainer width="100%" height={barChartHeight}>
        <BarChart
          data={data}
          layout="vertical"
          margin={{ top: 4, right: 16, left: 8, bottom: 4 }}
        >
          <CartesianGrid vertical={false} horizontal={false} />
          <XAxis type="number" hide />
          <YAxis
            type="category"
            dataKey="stage"
            axisLine={false}
            tickLine={false}
            width={115}
            tick={{ fontSize: 12, fill: "var(--muted)" }}
          />
          <Tooltip
            content={
              <BentoTooltip
                valueFormatter={(value, _name, entryPayload) =>
                  `${Number(value ?? 0).toLocaleString()} (${Number(
                    entryPayload?.percentage ?? 0
                  ).toFixed(1)}%)`
                }
              />
            }
            cursor={{ fill: "rgba(255, 77, 0, 0.06)", radius: 10 }}
          />
          <Bar
            dataKey="count"
            name="Số lượng"
            radius={[10, 10, 10, 10]}
            barSize={22}
            background={{ fill: "var(--panel-soft)", radius: 10 }}
          >
            {data.map((_, index) => (
              <Cell
                key={`cell-${index}`}
                fill={PALETTE[index % PALETTE.length]}
              />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>

      <div
        style={{
          display: "flex",
          flexWrap: "wrap",
          gap: 8,
          marginTop: 12,
        }}
      >
        {data.map((item, index) => {
          const color = PALETTE[index % PALETTE.length];
          return (
            <div
              key={`${item.stage}-${index}`}
              style={{
                display: "inline-flex",
                alignItems: "center",
                gap: 7,
                padding: "6px 10px",
                borderRadius: 999,
                background: "var(--panel-soft-2, var(--panel-soft))",
                border: "1px solid var(--line)",
                fontSize: 12,
              }}
            >
              <span
                style={{
                  width: 8,
                  height: 8,
                  borderRadius: "999px",
                  backgroundColor: color,
                  flexShrink: 0,
                }}
              />
              <span style={{ fontWeight: 600, color: "var(--text)" }}>
                {item.stage}
              </span>
              <span
                style={{
                  fontWeight: 700,
                  color: "var(--panel-ink)",
                  background: "var(--panel)",
                  borderRadius: 999,
                  padding: "1px 7px",
                  fontSize: 11,
                  fontVariantNumeric: "tabular-nums",
                }}
              >
                {Number(item.percentage ?? 0).toFixed(1)}%
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
};
