import React from "react";
import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip } from "recharts";
import { Skeleton } from "../Skeleton";
import { BentoTooltip } from "./BentoChartPrimitives";

export type CoursePopularityData = {
  course_title: string;
  enrollments: number;
};

type Props = {
  data: CoursePopularityData[];
  loading?: boolean;
  error?: boolean;
};

const PALETTE = ["#FF4D00", "#FF7A00", "#FB923C", "#FDBA74", "#EA580C"];

export const CoursePopularityChart: React.FC<Props> = ({ data, loading, error }) => {
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
    return <div className="chart-state">Chưa có dữ liệu khóa học</div>;
  }

  const chartData = data.map((item) => ({
    name: item.course_title,
    value: item.enrollments,
  }));

  const totalEnrollments = chartData.reduce((sum, item) => sum + item.value, 0);

  return (
    <div className="chart-container">
      <div style={{ position: "relative", width: "100%", height: 230 }}>
        <ResponsiveContainer width="100%" height={230}>
          <PieChart>
            <Pie
              data={chartData}
              cx="50%"
              cy="50%"
              innerRadius={68}
              outerRadius={96}
              paddingAngle={4}
              cornerRadius={8}
              stroke="none"
              dataKey="value"
            >
              {chartData.map((_, index) => (
                <Cell
                  key={`cell-${index}`}
                  fill={PALETTE[index % PALETTE.length]}
                />
              ))}
            </Pie>
            <Tooltip
              content={
                <BentoTooltip
                  valueFormatter={(value) =>
                    `${Number(value ?? 0).toLocaleString()} đăng ký`
                  }
                />
              }
            />
          </PieChart>
        </ResponsiveContainer>

        <div
          style={{
            position: "absolute",
            inset: 0,
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            justifyContent: "center",
            pointerEvents: "none",
            textAlign: "center",
          }}
        >
          <span
            style={{
              fontSize: 26,
              fontWeight: 700,
              lineHeight: 1.1,
              color: "var(--panel-ink)",
              fontVariantNumeric: "tabular-nums",
            }}
          >
            {totalEnrollments.toLocaleString()}
          </span>
          <span
            style={{
              fontSize: 12,
              fontWeight: 500,
              color: "var(--muted)",
              marginTop: 4,
            }}
          >
            Lượt đăng ký
          </span>
        </div>
      </div>

      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fit, minmax(170px, 1fr))",
          gap: 8,
          marginTop: 12,
        }}
      >
        {chartData.map((item, index) => {
          const color = PALETTE[index % PALETTE.length];
          const pct =
            totalEnrollments > 0
              ? ((item.value / totalEnrollments) * 100).toFixed(1)
              : "0.0";

          return (
            <div
              key={`${item.name}-${index}`}
              style={{
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                gap: 8,
                padding: "7px 10px",
                borderRadius: 999,
                background: "var(--panel-soft-2, var(--panel-soft))",
                border: "1px solid var(--line)",
                minWidth: 0,
              }}
            >
              <span
                style={{
                  display: "inline-flex",
                  alignItems: "center",
                  gap: 7,
                  minWidth: 0,
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
                <span
                  title={item.name}
                  style={{
                    fontSize: 12,
                    fontWeight: 600,
                    color: "var(--text)",
                    overflow: "hidden",
                    textOverflow: "ellipsis",
                    whiteSpace: "nowrap",
                  }}
                >
                  {item.name}
                </span>
              </span>
              <span
                style={{
                  fontSize: 11,
                  fontWeight: 700,
                  color: "var(--panel-ink)",
                  background: "var(--panel)",
                  borderRadius: 999,
                  padding: "2px 7px",
                  flexShrink: 0,
                  fontVariantNumeric: "tabular-nums",
                }}
              >
                {pct}%
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
};
