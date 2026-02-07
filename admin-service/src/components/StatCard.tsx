import React from "react";

export const StatCard = ({
  label,
  value,
  trend,
  note,
  accent = "orange"
}: {
  label: string;
  value: string;
  trend?: string;
  note?: string;
  accent?: "orange" | "teal" | "berry" | "ink";
}) => {
  return (
    <div className={`card stat-card accent-${accent}`}>
      <div className="stat-label">{label}</div>
      <div className="stat-value">{value}</div>
      {trend && <div className="stat-trend">{trend}</div>}
      {note && <div className="stat-note">{note}</div>}
    </div>
  );
};
