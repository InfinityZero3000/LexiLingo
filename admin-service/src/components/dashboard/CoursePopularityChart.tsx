import React from "react";
import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip, Legend } from "recharts";
import { Skeleton } from "../Skeleton";

export type CoursePopularityData = {
  course_title: string;
  enrollments: number;
};

type Props = {
  data: CoursePopularityData[];
  loading?: boolean;
  error?: boolean;
};

const COLORS = ["var(--accent)", "var(--accent-2)", "var(--accent-3)", "var(--accent-4)"];

export const CoursePopularityChart: React.FC<Props> = ({ data, loading, error }) => {
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
        Chưa có dữ liệu khóa học
      </div>
    );
  }

  // Transform data for pie chart
  const chartData = data.map(item => ({
    name: item.course_title,
    value: item.enrollments,
  }));

  return (
    <div className="chart-container">
      <ResponsiveContainer width="100%" height={300}>
        <PieChart>
          <Pie
            data={chartData}
            cx="50%"
            cy="50%"
            labelLine={false}
            label={({ name, percent }) => `${name}: ${((percent ?? 0) * 100).toFixed(0)}%`}
            outerRadius={80}
            fill="#8884d8"
            dataKey="value"
          >
            {chartData.map((_, index) => (
              <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
            ))}
          </Pie>
          <Tooltip formatter={(value) => [Number(value ?? 0).toLocaleString() + " đăng ký", ""]} />
          <Legend />
        </PieChart>
      </ResponsiveContainer>
    </div>
  );
};
