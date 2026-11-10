import React, { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { SectionHeader } from "../components/SectionHeader";
import { StatusPill } from "../components/StatusPill";
import { useAuth } from "../components/AuthProvider";
import { getSystemInfo } from "../lib/adminApi";
import { GemLimitsConfig, getGemLimits, updateGemLimits } from "../lib/gemLimitsApi";
import { useI18n, localeNames, type Locale } from "../lib/i18n";

const messageOf = (err: unknown, fallback: string) => (err instanceof Error && err.message ? err.message : fallback);

const ConfigRow = ({ label, value }: { label: string; value: React.ReactNode }) => (
  <tr>
    <td className="kv-label">{label}</td>
    <td className="kv-value">{value}</td>
  </tr>
);

const LIMIT_FIELDS: (keyof GemLimitsConfig)[] = [
  "gift_max_admin", "gift_max_super_admin", "budget_admin", "budget_super_admin", "item_max_qty",
];

/** Per-action caps and the daily budget for admin gem gifts; stored in the database, edited by super admins only. */
const GemLimitsPanel = () => {
  const { t } = useI18n();
  const { role } = useAuth();
  const queryClient = useQueryClient();
  const editable = role === "super_admin";
  const limits = useQuery({ queryKey: ["gem-limits"], queryFn: getGemLimits });
  const [form, setForm] = useState<Record<string, string>>({});
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const config = limits.data?.config;
    if (config) setForm(Object.fromEntries(LIMIT_FIELDS.map((f) => [f, String(config[f])])));
  }, [limits.data]);

  const save = useMutation({
    mutationFn: () => updateGemLimits(Object.fromEntries(LIMIT_FIELDS.map((f) => [f, Number(form[f])])) as Partial<GemLimitsConfig>),
    onMutate: () => { setError(null); setSaved(false); },
    onSuccess: () => { setSaved(true); queryClient.invalidateQueries({ queryKey: ["gem-limits"] }); },
    onError: (err) => setError(messageOf(err, t.settings.gemSaveFailed)),
  });

  const usage = limits.data?.usage;
  return (
    <div className="panel panel--pad">
      <h3 className="panel-title panel-title--sm">{t.settings.gemLimits}</h3>
      <p className="text-muted">{t.settings.gemLimitsHint}</p>
      {limits.error && <div className="form-error" role="alert">{messageOf(limits.error, t.settings.loadFailed)}</div>}
      {editable && limits.data?.config ? (
        <form
          className="form"
          onSubmit={(e) => { e.preventDefault(); save.mutate(); }}
        >
          {LIMIT_FIELDS.map((field) => (
            <label key={field} className="ud-field">
              {t.settings.gemFields[field]}
              <input
                type="number"
                min={field.startsWith("budget") ? 0 : 1}
                value={form[field] ?? ""}
                onChange={(e) => { setSaved(false); setForm({ ...form, [field]: e.target.value }); }}
                required
              />
            </label>
          ))}
          {error && <div className="form-error" role="alert">{error}</div>}
          {saved && <div className="form-success" role="status">{t.settings.gemSaved}</div>}
          <div className="ud-submit-row">
            <button type="submit" className="primary-button" disabled={save.isPending}>
              {save.isPending ? t.common.saving : t.common.save}
            </button>
          </div>
        </form>
      ) : (
        usage && (
          <table className="kv-table">
            <tbody>
              <ConfigRow label={t.settings.gemFields.gift_max_admin} value={usage.max_per_action.toLocaleString()} />
              <ConfigRow label={t.settings.gemFields.budget_admin} value={usage.daily_budget.toLocaleString()} />
              <ConfigRow label={t.settings.gemFields.item_max_qty} value={usage.item_gift_max_qty.toLocaleString()} />
            </tbody>
          </table>
        )
      )}
    </div>
  );
};

export const SystemSettingsPage = () => {
  const { t, locale, setLocale } = useI18n();
  const info = useQuery({ queryKey: ["system-info"], queryFn: getSystemInfo });
  const data = info.data?.data;

  return (
    <div className="stack">
      <SectionHeader title={t.settings.title} description={t.settings.description} />

      {info.error && <div className="form-error" role="alert">{messageOf(info.error, t.settings.loadFailed)}</div>}

      <div className="panel panel--pad">
        <h3 className="panel-title panel-title--sm">{t.settings.languageSection}</h3>
        <p className="text-muted">{t.settings.languageDesc}</p>
        <div className="seg-control">
          {(["vi", "en"] as Locale[]).map((loc) => (
            <button type="button" key={loc} onClick={() => setLocale(loc)} className={locale === loc ? "active" : ""}>
              {localeNames[loc]}
            </button>
          ))}
        </div>
      </div>

      <GemLimitsPanel />

      {data && (
        <>
          <div className="panel" role="note">{t.settings.envNote}</div>
          <div className="grid-2">
            <div className="panel panel--pad">
              <h3 className="panel-title panel-title--sm">{t.settings.appConfig}</h3>
              <table className="kv-table">
                <tbody>
                  <ConfigRow label={t.settings.appName} value={data.app_name} />
                  <ConfigRow
                    label={t.settings.environment}
                    value={<StatusPill tone={data.app_env === "production" ? "success" : "warning"} label={data.app_env} />}
                  />
                  <ConfigRow
                    label={t.settings.debug}
                    value={<StatusPill tone={data.debug ? "warning" : "success"} label={data.debug ? t.common.enabled : t.common.disabled} />}
                  />
                  <ConfigRow label={t.settings.apiPrefix} value={data.api_prefix} />
                  <ConfigRow label={t.settings.logLevel} value={data.log_level} />
                  <ConfigRow label={t.settings.aiService} value={<span className="mono">{data.ai_service_url}</span>} />
                  <ConfigRow label={t.settings.tokenTtl} value={`${data.token_expire_minutes} ${t.common.minutes}`} />
                  <ConfigRow label={t.settings.refreshTokenTtl} value={`${data.refresh_token_days} ${t.common.days}`} />
                </tbody>
              </table>
            </div>

            <div className="panel panel--pad">
              <h3 className="panel-title panel-title--sm">{t.settings.integrations}</h3>
              <table className="kv-table">
                <tbody>
                  <ConfigRow
                    label={t.settings.googleOAuth}
                    value={<StatusPill tone={data.google_oauth ? "success" : "danger"} label={data.google_oauth ? t.common.configured : t.common.notConfigured} />}
                  />
                  <ConfigRow
                    label={t.settings.firebase}
                    value={<StatusPill tone={data.firebase ? "success" : "danger"} label={data.firebase ? t.common.configured : t.common.notConfigured} />}
                  />
                </tbody>
              </table>
              <h4 className="panel-title panel-title--sm">{t.settings.corsOrigins}</h4>
              <div className="cluster">
                {data.cors_origins.map((origin) => (
                  <span key={origin} className="mono">{origin}</span>
                ))}
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  );
};
