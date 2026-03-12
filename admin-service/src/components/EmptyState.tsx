import React from "react";

export const EmptyState = ({
  title,
  description,
  action,
  icon
}: {
  title: string;
  description?: string;
  action?: React.ReactNode;
  icon?: React.ReactNode;
}) => (
  <div className="empty-state" style={{ padding: "48px 24px" }}>
    {icon && <div style={{ fontSize: 48, marginBottom: 16, opacity: 0.5 }}>{icon}</div>}
    <div className="empty-title" style={{ fontSize: 18, marginBottom: 4 }}>{title}</div>
    {description && <div className="empty-description" style={{ maxWidth: 400, margin: "0 auto 20px" }}>{description}</div>}
    {action && <div>{action}</div>}
  </div>
);
