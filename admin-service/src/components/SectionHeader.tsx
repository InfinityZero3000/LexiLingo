import React from "react";

export const SectionHeader = ({
  title,
  description,
  action
}: {
  title: string;
  description?: string;
  action?: React.ReactNode;
}) => (
  <div className="section-header">
    <div className="section-header-main">
      <h1>{title}</h1>
      {description && <p>{description}</p>}
    </div>
    {action && <div className="section-header-actions">{action}</div>}
  </div>
);

