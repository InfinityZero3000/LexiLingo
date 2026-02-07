import React from "react";
import { EmptyState } from "../components/EmptyState";
import { SectionHeader } from "../components/SectionHeader";

export const AdsPage = () => (
  <div className="panel">
    <SectionHeader
      title="Banner & Ads"
      description="Thiết kế chiến dịch banner, CTA, và quảng cáo in-app"
    />
    <EmptyState
      title="Chưa có API banner/ads"
      description="Nếu bạn muốn, tôi có thể tạo schema + endpoint để quản lý banner, vị trí, thời gian hiển thị."
    />
  </div>
);
