import React from "react";
import { Link } from "react-router-dom";
import { useI18n } from "../lib/i18n";

export const NotFoundPage = () => {
  const { t } = useI18n();
  return (
    <div className="center-page">
      <div className="center-card">
        <h1>{t.errorPages.notFound}</h1>
        <p>{t.errorPages.notFoundDesc}</p>
        <Link to="/" className="primary-button">
          {t.errorPages.goHome}
        </Link>
      </div>
    </div>
  );
};
