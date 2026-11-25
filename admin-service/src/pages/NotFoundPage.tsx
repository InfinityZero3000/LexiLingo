import React from "react";
import { Link } from "react-router-dom";
import { Compass, Home } from "lucide-react";
import { StatusPill } from "../components/StatusPill";
import { useI18n } from "../lib/i18n";

export const NotFoundPage = () => {
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
            background: "var(--accent-soft)",
            color: "var(--accent)",
            border: "1px solid rgba(255, 77, 0, 0.22)",
          }}
        >
          <Compass size={26} />
        </div>
        <StatusPill tone="info" label="404" />
        <h1 style={{ margin: 0, fontSize: 22 }}>{t.errorPages.notFound}</h1>
        <p className="text-muted" style={{ margin: 0, fontSize: 14, lineHeight: 1.6 }}>
          {t.errorPages.notFoundDesc}
        </p>
        <Link to="/" className="primary-button" style={{ marginTop: 6 }}>
          <Home size={16} />
          {t.errorPages.goHome}
        </Link>
      </div>
    </div>
  );
};
