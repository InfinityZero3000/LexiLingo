import React from "react";
import { Link } from "react-router-dom";
import { LogIn, ShieldAlert } from "lucide-react";
import { StatusPill } from "../components/StatusPill";
import { useI18n } from "../lib/i18n";

export const NoAccessPage = () => {
  const { t } = useI18n();
  return (
    <div className="center-page">
      <div
        className="center-card"
        style={{
          maxWidth: 440,
          width: "100%",
          padding: "36px 32px",
          justifyItems: "center",
          gap: 14,
        }}
      >
        <div
          style={{
            width: 56,
            height: 56,
            borderRadius: 18,
            display: "grid",
            placeItems: "center",
            background: "rgba(244, 63, 94, 0.12)",
            color: "var(--ink-red)",
            border: "1px solid rgba(244, 63, 94, 0.24)",
          }}
        >
          <ShieldAlert size={26} />
        </div>
        <StatusPill tone="danger" label="403" />
        <h1 style={{ margin: 0, fontSize: 22 }}>{t.errorPages.noAccess}</h1>
        <p className="text-muted" style={{ margin: 0, fontSize: 14, lineHeight: 1.6 }}>
          {t.errorPages.noAccessDesc}
        </p>
        <Link to="/login" className="primary-button" style={{ marginTop: 6 }}>
          <LogIn size={16} />
          {t.errorPages.goToLogin}
        </Link>
      </div>
    </div>
  );
};
