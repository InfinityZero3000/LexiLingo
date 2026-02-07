import React, { useEffect, useState } from "react";
import { SectionHeader } from "../components/SectionHeader";
import { StatCard } from "../components/StatCard";
import { StatusPill } from "../components/StatusPill";
import { getSystemInfo, type SystemInfo } from "../lib/adminApi";

export const SystemSettingsPage = () => {
  const [info, setInfo] = useState<SystemInfo | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setLoading(true);
    getSystemInfo()
      .then((res) => setInfo(res.data || null))
      .catch((err) => setError(err?.message || "Lỗi tải system info"))
      .finally(() => setLoading(false));
  }, []);

  if (loading) return <div className="loading">Đang tải...</div>;

  return (
    <div className="stack">
      <SectionHeader title="Cài đặt hệ thống" description="Thông tin cấu hình và tổng quan hệ thống" />

      {error && <div className="form-error">{error}</div>}

      {info && (
        <>
          {/* Totals */}
          <div className="card-grid">
            <StatCard label="Người dùng" value={String(info.totals.users)} accent="orange" />
            <StatCard label="Khóa học" value={String(info.totals.courses)} accent="teal" />
            <StatCard label="Từ vựng" value={String(info.totals.vocabulary)} accent="berry" />
            <StatCard label="Thành tựu" value={String(info.totals.achievements)} accent="ink" />
          </div>

          {/* System Config */}
          <div className="panel" style={{ padding: 20 }}>
            <h3 style={{ margin: "0 0 16px" }}>Cấu hình ứng dụng</h3>
            <table style={{ width: "100%", borderCollapse: "collapse" }}>
              <tbody>
                <ConfigRow label="Tên ứng dụng" value={info.app_name} />
                <ConfigRow label="Môi trường" value={
                  <StatusPill
                    tone={info.app_env === "production" ? "success" : "warning"}
                    label={info.app_env}
                  />
                } />
                <ConfigRow label="Debug" value={
                  <StatusPill tone={info.debug ? "warning" : "success"} label={info.debug ? "Bật" : "Tắt"} />
                } />
                <ConfigRow label="API Prefix" value={info.api_prefix} />
                <ConfigRow label="Log Level" value={info.log_level} />
                <ConfigRow label="Token TTL" value={`${info.token_expire_minutes} phút`} />
                <ConfigRow label="Refresh Token TTL" value={`${info.refresh_token_days} ngày`} />
                <ConfigRow label="AI Service" value={info.ai_service_url} />
              </tbody>
            </table>
          </div>

          {/* Integrations */}
          <div className="panel" style={{ padding: 20 }}>
            <h3 style={{ margin: "0 0 16px" }}>Tích hợp bên ngoài</h3>
            <table style={{ width: "100%", borderCollapse: "collapse" }}>
              <tbody>
                <ConfigRow label="Google OAuth" value={
                  <StatusPill tone={info.google_oauth ? "success" : "danger"} label={info.google_oauth ? "Đã cấu hình" : "Chưa"} />
                } />
                <ConfigRow label="Firebase" value={
                  <StatusPill tone={info.firebase ? "success" : "danger"} label={info.firebase ? "Đã cấu hình" : "Chưa"} />
                } />
              </tbody>
            </table>
          </div>

          {/* CORS Origins */}
          <div className="panel" style={{ padding: 20 }}>
            <h3 style={{ margin: "0 0 16px" }}>CORS Origins</h3>
            <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
              {info.cors_origins.map((origin, i) => (
                <span
                  key={i}
                  style={{
                    padding: "4px 10px",
                    background: "var(--bg-secondary, #f5f5f5)",
                    borderRadius: 6,
                    fontSize: 13,
                    fontFamily: "monospace",
                  }}
                >
                  {origin}
                </span>
              ))}
            </div>
          </div>
        </>
      )}
    </div>
  );
};

const ConfigRow = ({ label, value }: { label: string; value: React.ReactNode }) => (
  <tr style={{ borderBottom: "1px solid var(--border, #eee)" }}>
    <td style={{ padding: "10px 12px", color: "var(--muted, #666)", width: "40%", fontSize: 14 }}>
      {label}
    </td>
    <td style={{ padding: "10px 12px", fontWeight: 500, fontSize: 14 }}>
      {value}
    </td>
  </tr>
);
