import React, { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Clock, Gem, Globe, Info, Plug, Server, Settings } from "lucide-react";
import { SectionHeader } from "../components/SectionHeader";
import { StatCard } from "../components/StatCard";
import { StatusPill } from "../components/StatusPill";
import { useAuth } from "../components/AuthProvider";
import { getSystemInfo } from "../lib/adminApi";
import { GemLimitsConfig, getGemLimits, updateGemLimits } from "../lib/gemLimitsApi";
import { useI18n, localeNames, type Locale } from "../lib/i18n";

const messageOf = (err: unknown, fallback: string) => (err instanceof Error && err.message ? err.message : fallback);

const ConfigRow = ({ label, value }: { label: string; value: React.ReactNode }) => (
  <div
    style={{
      display: "flex",
      alignItems: "center",
      justifyContent: "space-between",
      gap: 12,
      flexWrap: "wrap",
      padding: "12px 16px",
      borderRadius: "var(--radius-inner)",
      background: "var(--panel-soft-2)",
      border: "1px solid var(--line)",
    }}
  >
    <span style={{ fontSize: 13, fontWeight: 500, color: "var(--muted)" }}>{label}</span>
    <span style={{ fontSize: 14, fontWeight: 600, color: "var(--text)" }}>{value}</span>
  </div>
);

const PanelHeading = ({
  icon,
  title,
  badge,
}: {
  icon: React.ReactNode;
  title: string;
  badge?: React.ReactNode;
}) => (
  <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12 }}>
    <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
      <span
        style={{
          width: 34,
          height: 34,
          borderRadius: 10,
          display: "grid",
          placeItems: "center",
          background: "var(--accent-soft)",
          color: "var(--accent)",
          flexShrink: 0,
        }}
      >
        {icon}
      </span>
      <h3 className="panel-title panel-title--sm" style={{ margin: 0 }}>{title}</h3>
    </div>
    {badge}
  </div>
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
      <PanelHeading
        icon={<Gem size={17} />}
        title={t.settings.gemLimits}
        badge={
          <StatusPill
            tone={editable ? "info" : "neutral"}
            label={editable ? t.common.enabled : t.common.active}
          />
        }
      />
      <p className="text-muted" style={{ margin: 0, fontSize: 13 }}>{t.settings.gemLimitsHint}</p>
      {limits.error && <div className="form-error" role="alert">{messageOf(limits.error, t.settings.loadFailed)}</div>}
      {editable && limits.data?.config ? (
        <form
          className="form"
          onSubmit={(e) => { e.preventDefault(); save.mutate(); }}
        >
          <div className="form-grid">
            {LIMIT_FIELDS.map((field) => (
              <label
                key={field}
                className="ud-field"
                style={{
                  padding: "14px 16px",
                  borderRadius: "var(--radius-inner)",
                  background: "var(--panel-soft-2)",
                  border: "1px solid var(--line)",
                }}
              >
                <span style={{ fontSize: 13, fontWeight: 600, color: "var(--text)" }}>
                  {t.settings.gemFields[field]}
                </span>
                <input
                  type="number"
                  min={field.startsWith("budget") ? 0 : 1}
                  value={form[field] ?? ""}
                  onChange={(e) => { setSaved(false); setForm({ ...form, [field]: e.target.value }); }}
                  required
                  style={{ background: "var(--panel)" }}
                />
              </label>
            ))}
          </div>
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
          <div className="stack" style={{ gap: 10 }}>
            <ConfigRow
              label={t.settings.gemFields.gift_max_admin}
              value={<StatusPill tone="info" label={usage.max_per_action.toLocaleString()} />}
            />
            <ConfigRow
              label={t.settings.gemFields.budget_admin}
              value={<StatusPill tone="info" label={usage.daily_budget.toLocaleString()} />}
            />
            <ConfigRow
              label={t.settings.gemFields.item_max_qty}
              value={<StatusPill tone="success" label={usage.item_gift_max_qty.toLocaleString()} />}
            />
          </div>
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

      {data && (
        <div className="card-grid">
          <StatCard
            label={t.settings.environment}
            value={data.app_env}
            note={data.app_name}
            variant="blue"
            icon={<Server size={18} />}
          />
          <StatCard
            label={t.settings.tokenTtl}
            value={`${data.token_expire_minutes} ${t.common.minutes}`}
            note={`${t.settings.refreshTokenTtl}: ${data.refresh_token_days} ${t.common.days}`}
            accent="teal"
            icon={<Clock size={18} />}
          />
          <StatCard
            label={t.settings.integrations}
            value={`${[data.google_oauth, data.firebase].filter(Boolean).length}/2`}
            note={t.settings.logLevel + ": " + data.log_level}
            variant="dark"
            icon={<Plug size={18} />}
          />
        </div>
      )}

      <div className="panel panel--pad">
        <div
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            gap: 16,
            flexWrap: "wrap",
            padding: "14px 16px",
            borderRadius: "var(--radius-inner)",
            background: "var(--panel-soft-2)",
            border: "1px solid var(--line)",
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
            <span
              style={{
                width: 36,
                height: 36,
                borderRadius: 10,
                display: "grid",
                placeItems: "center",
                background: "var(--accent-soft)",
                color: "var(--accent)",
                flexShrink: 0,
              }}
            >
              <Globe size={18} />
            </span>
            <div>
              <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                <h3 className="panel-title panel-title--sm" style={{ margin: 0 }}>{t.settings.languageSection}</h3>
                <StatusPill tone="info" label={locale.toUpperCase()} />
              </div>
              <p className="text-muted" style={{ margin: "4px 0 0", fontSize: 13 }}>{t.settings.languageDesc}</p>
            </div>
          </div>
          <div className="seg-control">
            {(["vi", "en"] as Locale[]).map((loc) => (
              <button type="button" key={loc} onClick={() => setLocale(loc)} className={locale === loc ? "active" : ""}>
                {localeNames[loc]}
              </button>
            ))}
          </div>
        </div>
      </div>

      <GemLimitsPanel />

      {data && (
        <>
          <div
            className="panel"
            role="note"
            style={{
              flexDirection: "row",
              alignItems: "center",
              gap: 12,
              padding: "14px 18px",
              borderRadius: "var(--radius-inner)",
              background: "var(--accent-soft)",
              borderColor: "rgba(255, 77, 0, 0.22)",
              color: "var(--accent)",
            }}
          >
            <Info size={18} style={{ flexShrink: 0 }} />
            <span style={{ fontSize: 13, fontWeight: 500 }}>{t.settings.envNote}</span>
          </div>
          <div className="grid-2">
            <div className="panel panel--pad">
              <PanelHeading icon={<Settings size={17} />} title={t.settings.appConfig} />
              <div className="stack" style={{ gap: 10 }}>
                <ConfigRow label={t.settings.appName} value={data.app_name} />
                <ConfigRow
                  label={t.settings.environment}
                  value={<StatusPill tone={data.app_env === "production" ? "success" : "warning"} label={data.app_env} />}
                />
                <ConfigRow
                  label={t.settings.debug}
                  value={<StatusPill tone={data.debug ? "warning" : "success"} label={data.debug ? t.common.enabled : t.common.disabled} />}
                />
                <ConfigRow
                  label={t.settings.apiPrefix}
                  value={<span className="mono text-small">{data.api_prefix}</span>}
                />
                <ConfigRow
                  label={t.settings.logLevel}
                  value={<StatusPill tone="neutral" label={data.log_level} />}
                />
                <ConfigRow label={t.settings.aiService} value={<span className="mono text-small">{data.ai_service_url}</span>} />
                <ConfigRow label={t.settings.tokenTtl} value={`${data.token_expire_minutes} ${t.common.minutes}`} />
                <ConfigRow label={t.settings.refreshTokenTtl} value={`${data.refresh_token_days} ${t.common.days}`} />
              </div>
            </div>

            <div className="panel panel--pad">
              <PanelHeading icon={<Plug size={17} />} title={t.settings.integrations} />
              <div className="stack" style={{ gap: 10 }}>
                <ConfigRow
                  label={t.settings.googleOAuth}
                  value={<StatusPill tone={data.google_oauth ? "success" : "danger"} label={data.google_oauth ? t.common.configured : t.common.notConfigured} />}
                />
                <ConfigRow
                  label={t.settings.firebase}
                  value={<StatusPill tone={data.firebase ? "success" : "danger"} label={data.firebase ? t.common.configured : t.common.notConfigured} />}
                />
              </div>
              <div
                style={{
                  padding: "14px 16px",
                  borderRadius: "var(--radius-inner)",
                  background: "var(--panel-soft-2)",
                  border: "1px solid var(--line)",
                }}
              >
                <h4 className="panel-title panel-title--sm" style={{ margin: "0 0 10px" }}>{t.settings.corsOrigins}</h4>
                <div className="cluster">
                  {data.cors_origins.map((origin) => (
                    <span
                      key={origin}
                      className="mono text-small"
                      style={{
                        padding: "4px 10px",
                        borderRadius: 999,
                        background: "var(--panel)",
                        border: "1px solid var(--line)",
                      }}
                    >
                      {origin}
                    </span>
                  ))}
                </div>
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  );
};
