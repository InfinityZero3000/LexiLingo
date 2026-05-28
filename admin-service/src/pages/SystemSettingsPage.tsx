import React, { useEffect, useState } from "react";
import { Edit2, Save, X, Check, HelpCircle } from "lucide-react";
import { SectionHeader } from "../components/SectionHeader";
import { StatusPill } from "../components/StatusPill";
import { getSystemInfo, updateSystemInfo, type SystemInfo } from "../lib/adminApi";
import { useI18n, localeNames, type Locale } from "../lib/i18n";

const localTexts = {
  vi: {
    edit: "Chỉnh sửa cấu hình",
    save: "Lưu thay đổi",
    cancel: "Hủy bỏ",
    saving: "Đang lưu...",
    success: "Cấu hình hệ thống đã được cập nhật thành công!",
    error: "Lỗi khi cập nhật cấu hình: ",
    corsOriginsHelp: "Danh sách domain được phép gọi API (cách nhau bởi dấu phẩy).",
    aiUrlHelp: "Đường dẫn kết nối API của AI Service.",
    tokenHelp: "Thời gian hết hạn của Access Token (phút).",
    refreshTokenHelp: "Thời gian hết hạn của Refresh Token (ngày).",
    statusProduction: "Môi trường Productive",
    statusDevelopment: "Môi trường Development",
    logLevelHelp: "Mức độ ghi log của hệ thống backend.",
    appNameHelp: "Tên hiển thị của ứng dụng."
  },
  en: {
    edit: "Edit Configuration",
    save: "Save Changes",
    cancel: "Cancel",
    saving: "Saving...",
    success: "System configuration updated successfully!",
    error: "Error updating configuration: ",
    corsOriginsHelp: "Allowed origins domains for API calls (separated by commas).",
    aiUrlHelp: "API connection endpoint for the AI Service.",
    tokenHelp: "Expiration limit of the Access Token in minutes.",
    refreshTokenHelp: "Expiration limit of the Refresh Token in days.",
    statusProduction: "Production Mode",
    statusDevelopment: "Development Mode",
    logLevelHelp: "Logging Verbosity of the Backend.",
    appNameHelp: "The title of this application."
  }
};

export const SystemSettingsPage = () => {
  const { t, locale, setLocale } = useI18n();
  const [info, setInfo] = useState<SystemInfo | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);

  // Edit states
  const [isEditing, setIsEditing] = useState(false);
  const [editForm, setEditForm] = useState({
    app_name: "",
    debug: false,
    log_level: "INFO",
    token_expire_minutes: 30,
    refresh_token_days: 7,
    ai_service_url: "",
    cors_origins: ""
  });
  const [saving, setSaving] = useState(false);

  const texts = localTexts[locale as Locale] || localTexts.en;

  const fetchInfo = () => {
    setLoading(true);
    getSystemInfo()
      .then((res) => {
        setInfo(res.data || null);
        setError(null);
      })
      .catch((err) => setError(err?.message || t.settings.loadFailed))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    fetchInfo();
  }, []);

  const handleStartEdit = () => {
    if (!info) return;
    setEditForm({
      app_name: info.app_name,
      debug: info.debug,
      log_level: info.log_level,
      token_expire_minutes: info.token_expire_minutes,
      refresh_token_days: info.refresh_token_days,
      ai_service_url: info.ai_service_url,
      cors_origins: info.cors_origins.join(", ")
    });
    setIsEditing(true);
    setError(null);
    setSuccessMsg(null);
  };

  const handleCancel = () => {
    setIsEditing(false);
    setError(null);
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setError(null);
    setSuccessMsg(null);

    try {
      const res = await updateSystemInfo({
        app_name: editForm.app_name,
        debug: editForm.debug,
        log_level: editForm.log_level,
        token_expire_minutes: Number(editForm.token_expire_minutes),
        refresh_token_days: Number(editForm.refresh_token_days),
        ai_service_url: editForm.ai_service_url,
        cors_origins: editForm.cors_origins,
      });

      if (res.success && res.data) {
        setInfo(prev => {
          if (!prev) return null;
          return {
            ...prev,
            app_name: res.data!.app_name,
            debug: res.data!.debug,
            log_level: res.data!.log_level,
            token_expire_minutes: res.data!.token_expire_minutes,
            refresh_token_days: res.data!.refresh_token_days,
            ai_service_url: res.data!.ai_service_url,
            cors_origins: res.data!.cors_origins,
          };
        });
        setSuccessMsg(texts.success);
        setIsEditing(false);
        // Clear success message after 5 seconds
        setTimeout(() => setSuccessMsg(null), 5000);
      } else {
        setError(res.error || "Failed to update configuration");
      }
    } catch (err: any) {
      setError(err?.message || "Failed to update configuration");
    } finally {
      setSaving(false);
    }
  };

  if (loading && !info) return <div className="loading">{t.common.loading}</div>;

  return (
    <div className="stack">
      <style>{`
        .settings-header-action {
          display: flex;
          gap: 12px;
          align-items: center;
        }
        
        .settings-btn {
          display: inline-flex;
          align-items: center;
          gap: 8px;
          padding: 8px 16px;
          border-radius: 8px;
          font-size: 14px;
          font-weight: 500;
          cursor: pointer;
          transition: all 0.2s ease;
          border: 1px solid transparent;
        }

        .settings-btn-primary {
          background: var(--accent, #3b82f6);
          color: white;
        }

        .settings-btn-primary:hover {
          opacity: 0.9;
          transform: translateY(-1px);
        }

        .settings-btn-secondary {
          background: transparent;
          border-color: var(--border, #e5e7eb);
          color: var(--text, #1f2937);
        }

        .settings-btn-secondary:hover {
          background: var(--bg-secondary, #f3f4f6);
        }

        .settings-form-group {
          margin-bottom: 20px;
        }

        .settings-label {
          display: block;
          font-size: 14px;
          font-weight: 500;
          margin-bottom: 6px;
          color: var(--text, #374151);
        }

        .settings-input {
          width: 100%;
          padding: 10px 12px;
          border-radius: 8px;
          border: 1px solid var(--border, #d1d5db);
          background: var(--bg-primary, #ffffff);
          color: var(--text, #1f2937);
          font-size: 14px;
          transition: all 0.15s ease;
        }

        .settings-input:focus {
          outline: none;
          border-color: var(--accent, #3b82f6);
          box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.15);
        }

        .settings-select {
          width: 100%;
          padding: 10px 12px;
          border-radius: 8px;
          border: 1px solid var(--border, #d1d5db);
          background: var(--bg-primary, #ffffff);
          color: var(--text, #1f2937);
          font-size: 14px;
          outline: none;
        }

        .settings-select:focus {
          border-color: var(--accent, #3b82f6);
        }

        .settings-help {
          display: flex;
          align-items: center;
          gap: 4px;
          font-size: 12px;
          color: var(--muted, #6b7280);
          margin-top: 4px;
        }

        .toggle-switch {
          position: relative;
          display: inline-block;
          width: 48px;
          height: 24px;
        }

        .toggle-switch input {
          opacity: 0;
          width: 0;
          height: 0;
        }

        .toggle-slider {
          position: absolute;
          cursor: pointer;
          top: 0;
          left: 0;
          right: 0;
          bottom: 0;
          background-color: var(--border, #ccc);
          transition: .3s;
          border-radius: 24px;
        }

        .toggle-slider:before {
          position: absolute;
          content: "";
          height: 18px;
          width: 18px;
          left: 3px;
          bottom: 3px;
          background-color: white;
          transition: .3s;
          border-radius: 50%;
        }

        input:checked + .toggle-slider {
          background-color: var(--accent, #10b981);
        }

        input:checked + .toggle-slider:before {
          transform: translateX(24px);
        }

        .form-success-banner {
          display: flex;
          align-items: center;
          gap: 8px;
          background: #d1fae5;
          border: 1px solid #10b981;
          color: #065f46;
          padding: 12px 16px;
          border-radius: 8px;
          font-size: 14px;
          margin-bottom: 20px;
          animation: slideDown 0.3s ease;
        }

        @keyframes slideDown {
          from { transform: translateY(-10px); opacity: 0; }
          to { transform: translateY(0); opacity: 1; }
        }
      `}</style>

      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: 16 }}>
        <SectionHeader title={t.settings.title} description={t.settings.description} />
        
        {info && (
          <div className="settings-header-action">
            {!isEditing ? (
              <button className="settings-btn settings-btn-primary" onClick={handleStartEdit}>
                <Edit2 size={16} /> {texts.edit}
              </button>
            ) : (
              <>
                <button className="settings-btn settings-btn-secondary" onClick={handleCancel} disabled={saving}>
                  <X size={16} /> {texts.cancel}
                </button>
                <button className="settings-btn settings-btn-primary" onClick={handleSave} disabled={saving}>
                  <Save size={16} /> {saving ? texts.saving : texts.save}
                </button>
              </>
            )}
          </div>
        )}
      </div>

      {error && <div className="form-error" style={{ marginBottom: 20 }}>{error}</div>}
      {successMsg && (
        <div className="form-success-banner">
          <Check size={16} /> {successMsg}
        </div>
      )}

      {info && (
        <form onSubmit={handleSave}>
          {/* Language Preference */}
          <div className="panel" style={{ padding: 20, marginBottom: 20 }}>
            <h3 style={{ margin: "0 0 8px", fontSize: 16 }}>{t.settings.languageSection}</h3>
            <p style={{ margin: "0 0 16px", fontSize: 14, color: "var(--muted, #666)" }}>{t.settings.languageDesc}</p>
            <div className="seg-control">
              {(["vi", "en"] as Locale[]).map((loc) => (
                <button
                  type="button"
                  key={loc}
                  onClick={() => setLocale(loc)}
                  className={locale === loc ? "active" : ""}
                  disabled={isEditing}
                >
                  {localeNames[loc]}
                </button>
              ))}
            </div>
          </div>

          <div className="grid-2">
            {/* Application Configuration */}
            <div className="panel" style={{ padding: 20 }}>
              <h3 style={{ margin: "0 0 16px", fontSize: 16 }}>{t.settings.appConfig}</h3>
              
              {isEditing ? (
                <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
                  <div className="settings-form-group">
                    <label className="settings-label">{t.settings.appName}</label>
                    <input
                      type="text"
                      className="settings-input"
                      value={editForm.app_name}
                      onChange={(e) => setEditForm({ ...editForm, app_name: e.target.value })}
                      required
                    />
                    <div className="settings-help">
                      <HelpCircle size={12} /> {texts.appNameHelp}
                    </div>
                  </div>

                  <div className="settings-form-group">
                    <label className="settings-label" style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
                      <span>{t.settings.debug}</span>
                      <span className="toggle-switch">
                        <input
                          type="checkbox"
                          checked={editForm.debug}
                          onChange={(e) => setEditForm({ ...editForm, debug: e.target.checked })}
                        />
                        <span className="toggle-slider"></span>
                      </span>
                    </label>
                    <div className="settings-help">
                      <HelpCircle size={12} /> Enable/disable verbose debugging features.
                    </div>
                  </div>

                  <div className="settings-form-group">
                    <label className="settings-label">{t.settings.logLevel}</label>
                    <select
                      className="settings-select"
                      value={editForm.log_level}
                      onChange={(e) => setEditForm({ ...editForm, log_level: e.target.value })}
                    >
                      <option value="DEBUG">DEBUG</option>
                      <option value="INFO">INFO</option>
                      <option value="WARNING">WARNING</option>
                      <option value="ERROR">ERROR</option>
                      <option value="CRITICAL">CRITICAL</option>
                    </select>
                    <div className="settings-help">
                      <HelpCircle size={12} /> {texts.logLevelHelp}
                    </div>
                  </div>

                  <div className="settings-form-group">
                    <label className="settings-label">{t.settings.aiService}</label>
                    <input
                      type="text"
                      className="settings-input"
                      value={editForm.ai_service_url}
                      onChange={(e) => setEditForm({ ...editForm, ai_service_url: e.target.value })}
                      required
                    />
                    <div className="settings-help">
                      <HelpCircle size={12} /> {texts.aiUrlHelp}
                    </div>
                  </div>
                </div>
              ) : (
                <table style={{ width: "100%", borderCollapse: "collapse" }}>
                  <tbody>
                    <ConfigRow label={t.settings.appName} value={info.app_name} />
                    <ConfigRow label={t.settings.environment} value={
                      <StatusPill
                        tone={info.app_env === "production" ? "success" : "warning"}
                        label={info.app_env === "production" ? texts.statusProduction : texts.statusDevelopment}
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
              )}
            </div>

            {/* Integrations */}
            <div className="panel" style={{ padding: 20 }}>
              <h3 style={{ margin: "0 0 16px", fontSize: 16 }}>{t.settings.integrations}</h3>
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

          {/* Security & Access Settings */}
          <div className="panel" style={{ padding: 20, marginTop: 20 }}>
            <h3 style={{ margin: "0 0 16px", fontSize: 16 }}>{t.settings.securitySection}</h3>
            
            {isEditing ? (
              <div style={{ display: "flex", flexDirection: "column", gap: 16, maxWidth: 600 }}>
                <div className="settings-form-group">
                  <label className="settings-label">{t.settings.tokenTtl}</label>
                  <input
                    type="number"
                    className="settings-input"
                    value={editForm.token_expire_minutes}
                    onChange={(e) => setEditForm({ ...editForm, token_expire_minutes: Number(e.target.value) })}
                    min={1}
                    required
                  />
                  <div className="settings-help">
                    <HelpCircle size={12} /> {texts.tokenHelp}
                  </div>
                </div>

                <div className="settings-form-group">
                  <label className="settings-label">{t.settings.refreshTokenTtl}</label>
                  <input
                    type="number"
                    className="settings-input"
                    value={editForm.refresh_token_days}
                    onChange={(e) => setEditForm({ ...editForm, refresh_token_days: Number(e.target.value) })}
                    min={1}
                    required
                  />
                  <div className="settings-help">
                    <HelpCircle size={12} /> {texts.refreshTokenHelp}
                  </div>
                </div>

                <div className="settings-form-group">
                  <label className="settings-label">{t.settings.corsOrigins}</label>
                  <input
                    type="text"
                    className="settings-input"
                    value={editForm.cors_origins}
                    onChange={(e) => setEditForm({ ...editForm, cors_origins: e.target.value })}
                    required
                  />
                  <div className="settings-help">
                    <HelpCircle size={12} /> {texts.corsOriginsHelp}
                  </div>
                </div>
              </div>
            ) : (
              <>
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
              </>
            )}
          </div>
        </form>
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
