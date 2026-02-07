import React from "react";
import { EmptyState } from "../components/EmptyState";
import { SectionHeader } from "../components/SectionHeader";

export const AiModelsPage = () => (
  <div className="panel">
    <SectionHeader
      title="AI Models Config"
      description="Super Admin: cấu hình model, memory, routing"
    />
    <EmptyState
      title="Chưa có endpoint cấu hình model"
      description="AI service hiện có monitoring, nhưng chưa có API cấu hình runtime."
    />
  </div>
);
