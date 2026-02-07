import React from "react";
import { EmptyState } from "../components/EmptyState";
import { SectionHeader } from "../components/SectionHeader";

export const DatabasePage = () => (
  <div className="panel">
    <SectionHeader
      title="Database Console"
      description="Super Admin: truy cập DB và tác vụ maintenance"
    />
    <EmptyState
      title="Chưa có API DB"
      description="Bạn cần API riêng hoặc kết nối trực tiếp với DB console (khuyến nghị dùng tool chuyên dụng)."
    />
  </div>
);
