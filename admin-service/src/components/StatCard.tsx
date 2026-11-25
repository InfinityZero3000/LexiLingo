import React from "react";
import { Skeleton } from "./Skeleton";

export const StatCard = ({
  label,
  value,
  trend,
  note,
  accent = "orange",
  variant = "default",
  icon,
  loading = false,
}: {
  label: string;
  value: string;
  trend?: string;
  note?: string;
  accent?: "orange" | "teal" | "berry" | "ink";
  variant?: "default" | "dark" | "blue";
  icon?: React.ReactNode;
  loading?: boolean;
}) => {
  const variantClass =
    variant === "dark" ? " bento-card--dark" : variant === "blue" ? " bento-card--blue" : "";

  return (
    <article className={`stat-card accent-${accent}${variantClass}`} aria-busy={loading}>
      <div className="stat-card-header">
        <div className="stat-label">{label}</div>
        {icon ? (
          <div className="stat-icon">{icon}</div>
        ) : (
          <span className="stat-accent-dot" aria-hidden="true" />
        )}
      </div>
      <div className="stat-value">{loading ? <Skeleton width="60%" height={32} /> : value}</div>
      {!loading && trend && <div className="stat-trend stat-delta-pill">{trend}</div>}
      {!loading && note && <div className="stat-note">{note}</div>}
    </article>
  );
};
