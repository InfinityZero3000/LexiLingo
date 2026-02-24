import React from "react";
import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip, Legend } from "recharts";

export type CoursePopularityData = {
  course_title: string;
  enrollments: number;
};

type Props = {
  data: CoursePopularityData[];
  loading?: boolean;
};

const COLORS = ["#3b82f6", "#10b981", "#f59e0b", "#ef4444", "#8b5cf6", "#ec4899"];

export const CoursePopularityChart: React.FC<Props> = ({ data, loading }) => {
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
        <div className="loading-text">Chưa có dữ liệu khóa học</div>
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
            label={({ name, percent }) => `${name}: ${(percent * 100).toFixed(0)}%`}
            outerRadius={80}
            fill="#8884d8"
            dataKey="value"
          >
            {chartData.map((_, index) => (
              <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
            ))}
          </Pie>
          <Tooltip formatter={(value: number) => [value.toLocaleString() + " đăng ký", ""]} />
          <Legend />
        </PieChart>
      </ResponsiveContainer>
    </div>
  );
};
