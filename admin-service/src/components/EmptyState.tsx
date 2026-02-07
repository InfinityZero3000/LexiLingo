import React from "react";

export const EmptyState = ({
  title,
  description,
  action
}: {
  title: string;
  description?: string;
  action?: React.ReactNode;
}) => (
  <div className="empty-state">
    <div className="empty-title">{title}</div>
    {description && <div className="empty-description">{description}</div>}
    {action && <div>{action}</div>}
  </div>
);
