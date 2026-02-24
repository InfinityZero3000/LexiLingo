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
    <div>
      <h2>{title}</h2>
      {description && <p>{description}</p>}
    </div>
    {action && <div>{action}</div>}
  </div>
);
