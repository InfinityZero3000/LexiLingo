import React from "react";
import { EmptyState } from "../components/EmptyState";
import { SectionHeader } from "../components/SectionHeader";

export const LessonsPage = () => (
  <div className="panel">
    <SectionHeader
      title="Quản lý Lesson"
      description="CRUD Lesson qua /api/v1/admin/lessons (chưa có UI chi tiết)"
    />
    <EmptyState
      title="Chưa cấu hình UI quản lý Lesson"
      description="Cần workflow thêm bài giảng, câu hỏi, bài test và điều kiện prerequisites."
    />
  </div>
);
