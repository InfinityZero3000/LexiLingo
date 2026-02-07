import React, { useEffect, useState } from "react";
import { SectionHeader } from "../components/SectionHeader";
import { StatusPill } from "../components/StatusPill";
import { getSystemInfo, type SystemInfo } from "../lib/adminApi";
import { useI18n, localeNames, type Locale } from "../lib/i18n";

export const SystemSettingsPage = () => {
  const { t, locale, setLocale } = useI18n();
  const [info, setInfo] = useState<SystemInfo | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setLoading(true);
    getSystemInfo()
      .then((res) => setInfo(res.data || null))
      .catch((err) => setError(err?.message || t.settings.loadFailed))
      .finally(() => setLoading(false));
  }, []);

  if (loading) return <div className="loading">{t.common.loading}</div>;

  return (
    <div className="stack">
      <SectionHeader title={t.settings.title} description={t.settings.description} />

      {error && <div className="form-error">{error}</div>}

      {info && (
        <>
          {/* Language Preference */}
          <div className="panel" style={{ padding: 20 }}>
            <h3 style={{ margin: "0 0 8px", fontSize: 16 }}>{t.settings.languageSection}</h3>
            <p style={{ margin: "0 0 16px", fontSize: 14, color: "var(--muted, #666)" }}>{t.settings.languageDesc}</p>
            <div className="seg-control">
              {(["vi", "en"] as Locale[]).map((loc) => (
                <button
                  key={loc}
                  onClick={() => setLocale(loc)}
                  className={locale === loc ? "active" : ""}
                >
                  {localeNames[loc]}
                </button>
              ))}
            </div>
          </div>

          <div className="grid-2">
            {/* Application Configuration */}
            <div className="panel" style={{ padding: 20 }}>
              <h3 style={{ margin: "0 0 12px", fontSize: 16 }}>{t.settings.appConfig}</h3>
              <table style={{ width: "100%", borderCollapse: "collapse" }}>
                <tbody>
                  <ConfigRow label={t.settings.appName} value={info.app_name} />
                  <ConfigRow label={t.settings.environment} value={
                    <StatusPill
                      tone={info.app_env === "production" ? "success" : "warning"}
                      label={info.app_env}
                    />
                  } />
                  <ConfigRow label={t.settings.debug} value={
                    <StatusPill tone={info.debug ? "warning" : "success"} label={info.debug ? t.common.enabled : t.common.disabled} />
                  } />
                  <ConfigRow label={t.settings.apiPrefix} value={info.api_prefix} />
                  <ConfigRow label={t.settings.logLevel} value={info.log_level} />
                  <ConfigRow label={t.settings.aiService} value={
                    <span style={{ fontSize: 13, fontFamily: "monospace", color: "var(--muted)" }}>{info.ai_service_url}</span>
                  } />
                </tbody>
              </table>
            </div>

            {/* Integrations */}
            <div className="panel" style={{ padding: 20 }}>
              <h3 style={{ margin: "0 0 12px", fontSize: 16 }}>{t.settings.integrations}</h3>
              <table style={{ width: "100%", borderCollapse: "collapse" }}>
                <tbody>
                  <ConfigRow label={t.settings.googleOAuth} value={
                    <StatusPill tone={info.google_oauth ? "success" : "danger"} label={info.google_oauth ? t.common.configured : t.common.notConfigured} />
                  } />
                  <ConfigRow label={t.settings.firebase} value={
                    <StatusPill tone={info.firebase ? "success" : "danger"} label={info.firebase ? t.common.configured : t.common.notConfigured} />
                  } />
                </tbody>
              </table>
            </div>
          </div>

          {/* Security Settings */}
          <div className="panel" style={{ padding: 20 }}>
            <h3 style={{ margin: "0 0 12px", fontSize: 16 }}>{t.settings.securitySection}</h3>
            <div style={{ display: "flex", gap: 24, marginBottom: 16, flexWrap: "wrap" }}>
              <div>
                <div style={{ fontSize: 13, color: "var(--muted)", marginBottom: 4 }}>{t.settings.tokenTtl}</div>
                <div style={{ fontSize: 18, fontWeight: 600 }}>{info.token_expire_minutes} {t.common.minutes}</div>
              </div>
              <div>
                <div style={{ fontSize: 13, color: "var(--muted)", marginBottom: 4 }}>{t.settings.refreshTokenTtl}</div>
                <div style={{ fontSize: 18, fontWeight: 600 }}>{info.refresh_token_days} {t.common.days}</div>
              </div>
            </div>
            <div style={{ marginTop: 16 }}>
              <h4 style={{ margin: "0 0 8px", fontSize: 14, fontWeight: 600 }}>{t.settings.corsOrigins}</h4>
              <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
                {info.cors_origins.map((origin, i) => (
                  <span
                    key={i}
                    style={{
                      padding: "6px 12px",
                      background: "var(--bg-secondary, #f5f5f5)",
                      border: "1px solid var(--border, #e5e5e5)",
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
