import React from "react";
import { Link } from "react-router-dom";
import { useI18n } from "../lib/i18n";

export const NoAccessPage = () => {
  const { t } = useI18n();
  return (
    <div className="center-page">
      <div className="center-card">
        <h1>{t.errorPages.noAccess}</h1>
        <p>{t.errorPages.noAccessDesc}</p>
        <Link to="/login" className="primary-button">
          {t.errorPages.goToLogin}
        </Link>
      </div>
    </div>
  );
};
