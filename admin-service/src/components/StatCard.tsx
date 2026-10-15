import React from "react";
import { Skeleton } from "./Skeleton";

export const StatCard = ({
  label,
  value,
  trend,
  note,
  accent = "orange",
  loading = false,
}: {
  label: string;
  value: string;
  trend?: string;
  note?: string;
  accent?: "orange" | "teal" | "berry" | "ink";
  loading?: boolean;
}) => {
  return (
    <article className={`stat-card accent-${accent}`} aria-busy={loading}>
      <div className="stat-label">{label}</div>
      <div className="stat-value">{loading ? <Skeleton width="60%" height={32} /> : value}</div>
      {!loading && trend && <div className="stat-trend">{trend}</div>}
      {!loading && note && <div className="stat-note">{note}</div>}
    </article>
  );
};
