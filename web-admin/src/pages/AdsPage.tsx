import React from "react";
import { SectionHeader } from "../components/SectionHeader";

const PLANNED_FEATURES = [
  { icon: "🖼️", title: "Banner quảng cáo", desc: "Quản lý banner hero, sidebar, interstitial với lịch hiển thị" },
  { icon: "📣", title: "Chiến dịch CTA", desc: "Tạo call-to-action cho premium, events, seasonal campaigns" },
  { icon: "📊", title: "Analytics quảng cáo", desc: "Theo dõi impressions, clicks, CTR theo vị trí hiển thị" },
  { icon: "⏰", title: "Lập lịch", desc: "Đặt thời gian bắt đầu/kết thúc, A/B testing giữa các banner" },
  { icon: "🎯", title: "Targeting", desc: "Hiển thị banner theo level, ngôn ngữ, hoạt động người dùng" },
  { icon: "📱", title: "Preview", desc: "Xem trước giao diện banner trên mobile và web" },
];

export const AdsPage = () => (
  <div className="stack">
    <SectionHeader
      title="Banner & Quảng cáo"
      description="Quản lý chiến dịch banner, CTA và quảng cáo in-app"
    />

    <div className="panel" style={{ padding: 24, textAlign: "center" }}>
      <div style={{ fontSize: 48, marginBottom: 12 }}>🚧</div>
      <h3 style={{ margin: "0 0 8px" }}>Tính năng đang phát triển</h3>
      <p style={{ color: "var(--muted, #666)", maxWidth: 480, margin: "0 auto" }}>
        Module quản lý banner & quảng cáo sẽ được triển khai trong giai đoạn tiếp theo.
        Dưới đây là các tính năng dự kiến:
      </p>
    </div>

    <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(280px, 1fr))", gap: 16 }}>
      {PLANNED_FEATURES.map((f, i) => (
        <div key={i} className="panel" style={{ padding: 20 }}>
          <div style={{ fontSize: 28, marginBottom: 8 }}>{f.icon}</div>
          <h4 style={{ margin: "0 0 6px", fontSize: 15 }}>{f.title}</h4>
          <p style={{ margin: 0, fontSize: 13, color: "var(--muted, #666)" }}>{f.desc}</p>
        </div>
      ))}
    </div>
  </div>
);
