import React from "react";
import { EmptyState } from "../components/EmptyState";
import { SectionHeader } from "../components/SectionHeader";

export const UnitsPage = () => (
  <div className="panel">
    <SectionHeader
      title="Quản lý Unit"
      description="CRUD Unit qua /api/v1/admin/units (chưa có UI chi tiết)"
    />
    <EmptyState
      title="Chưa cấu hình UI quản lý Unit"
      description="Cần thiết kế flow chọn khóa học, tạo/sửa/xóa unit và sắp xếp order."
    />
  </div>
);
