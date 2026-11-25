import React, { useEffect, useState } from "react";
import { SectionHeader } from "../components/SectionHeader";
import { StatCard } from "../components/StatCard";
import { StatusPill } from "../components/StatusPill";
import { useI18n } from "../lib/i18n";
import { authStore } from "../lib/auth";
import { getAiConfig, updateAiConfig } from "../lib/healthApi";
import { Bot, CheckCircle, Cpu, Key, Lightbulb, Sparkles, Zap } from "lucide-react";

interface AiChatConfig {
  gemini_api_key?: string;
  gemini_model: string;
  temperature: number;
  max_tokens: number;
  top_p: number;
  top_k: number;
  use_mongodb: boolean;
  enable_voice: boolean;
  enable_grammar: boolean;
  enable_topic: boolean;
  chat_memory_turns: number;
}

export const AiChatSettingsPage = () => {
  const { t } = useI18n();
  const [config, setConfig] = useState<AiChatConfig | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [showApiKey, setShowApiKey] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [saveSuccess, setSaveSuccess] = useState(false);

  useEffect(() => {
    fetchConfig();
  }, []);

  const fetchConfig = async () => {
    try {
      const response = await getAiConfig(authStore.accessToken ?? undefined);
      const data = await response.json();
      // Backend returns flat AiConfig object; remap model_name → gemini_model
      if (data && data.model_name) {
        setConfig({
          ...getDefaultConfig(),
          ...data,
          gemini_model: data.gemini_model ?? data.model_name,
        });
      } else {
        setConfig(getDefaultConfig());
      }
    } catch (error) {
      console.error("Failed to fetch AI config:", error);
      setConfig(getDefaultConfig());
    } finally {
      setLoading(false);
    }
  };

  const getDefaultConfig = (): AiChatConfig => ({
    gemini_model: "gemini-2.0-flash-exp",
    temperature: 0.7,
    max_tokens: 2048,
    top_p: 0.9,
    top_k: 40,
    use_mongodb: true,
    enable_voice: true,
    enable_grammar: true,
    enable_topic: true,
    chat_memory_turns: 10,
  });

  const handleSave = async () => {
    if (!config) return;
    setSaving(true);
    setSaveError(null);
    setSaveSuccess(false);
    try {
      const payload = { ...config, model_name: config.gemini_model };
      const response = await updateAiConfig(payload, authStore.accessToken ?? undefined);
      if (!response.ok) {
        const err = await response.json().catch(() => ({}));
        throw new Error(err.detail || response.statusText);
      }
      setSaveSuccess(true);
      setTimeout(() => setSaveSuccess(false), 4000);
    } catch (error: any) {
      setSaveError(error.message || t.common.saveFailed);
    } finally {
      setSaving(false);
    }
  };

  const updateConfig = <K extends keyof AiChatConfig>(key: K, value: AiChatConfig[K]) => {
    if (!config) return;
    setConfig({ ...config, [key]: value });
  };

  if (loading) return <div className="loading">{t.common.loading}</div>;
  if (!config) return <div>{t.common.loadFailed}</div>;

  return (
    <div className="stack">
      <div className="page-header-actions">
        <SectionHeader 
          title={t.aiChat.title} 
          description={t.aiChat.description} 
        />
        <button 
          className="primary-button" 
          onClick={handleSave}
          disabled={saving}
        >
          {saving ? t.common.saving : t.common.save}
        </button>
      </div>

      {saveError && <div className="form-error">{saveError}</div>}
      {saveSuccess && (
        <div className="form-success">
          <CheckCircle size={16} aria-hidden="true" /> {t.common.success}
        </div>
      )}

      {/* Quick Stats */}
      <div className="card-grid">
        <StatCard
          label={t.aiChat.model}
          value={config.gemini_model.split("-")[1] || "Flash"}
          note={`Gemini ${config.gemini_model.includes("2.0") ? "2.0" : "1.5"}`}
          variant="blue"
          icon={<Bot size={18} />}
        />
        <StatCard
          label={t.aiChat.temperature}
          value={config.temperature.toFixed(2)}
          note={t.aiChat.creativity}
          accent="teal"
          icon={<Sparkles size={18} />}
        />
        <StatCard
          label={t.aiChat.maxTokens}
          value={String(config.max_tokens)}
          note={t.aiChat.responseLength}
          accent="berry"
          icon={<Cpu size={18} />}
        />
        <StatCard
          label={t.aiChat.features}
          value={`${[config.enable_voice, config.enable_grammar, config.enable_topic].filter(Boolean).length}/3`}
          note={t.aiChat.modulesEnabled}
          variant="dark"
          icon={<Zap size={18} />}
        />
      </div>

      <div className="grid-2">
        {/* Gemini Model Settings */}
        <div className="panel">
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12 }}>
            <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
              <span
                style={{
                  width: 36,
                  height: 36,
                  borderRadius: 12,
                  display: "grid",
                  placeItems: "center",
                  background: "var(--accent-soft)",
                  color: "var(--accent)",
                  flexShrink: 0,
                }}
              >
                <Bot size={18} />
              </span>
              <h3 style={{ margin: 0 }}>{t.aiChat.modelSettings}</h3>
            </div>
            <StatusPill tone="info" label={config.gemini_model} />
          </div>

          <div
            className="form-field"
            style={{
              padding: "14px 16px",
              borderRadius: "var(--radius-inner)",
              background: "var(--panel-soft-2)",
              border: "1px solid var(--line)",
            }}
          >
            <label style={{ fontWeight: 600 }}>{t.aiChat.model}</label>
            <select
              value={config.gemini_model}
              onChange={(e) => updateConfig("gemini_model", e.target.value)}
              className="input"
              style={{ background: "var(--panel)" }}
            >
              <option value="gemini-2.0-flash-exp">Gemini 2.0 Flash (Experimental)</option>
              <option value="gemini-1.5-flash">Gemini 1.5 Flash</option>
              <option value="gemini-1.5-pro">Gemini 1.5 Pro</option>
            </select>
          </div>

          <div
            className="form-field"
            style={{
              padding: "14px 16px",
              borderRadius: "var(--radius-inner)",
              background: "var(--panel-soft-2)",
              border: "1px solid var(--line)",
            }}
          >
            <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 8, marginBottom: 8 }}>
              <label style={{ margin: 0, fontWeight: 600 }}>{t.aiChat.temperature}</label>
              <StatusPill tone="info" label={config.temperature.toFixed(1)} />
            </div>
            <input
              type="range"
              min="0"
              max="2"
              step="0.1"
              value={config.temperature}
              onChange={(e) => updateConfig("temperature", parseFloat(e.target.value))}
              className="slider"
              style={{ accentColor: "var(--accent)" }}
            />
            <small className="text-muted" style={{ display: "block", marginTop: 8 }}>{t.aiChat.temperatureHint}</small>
          </div>

          <div
            className="form-field"
            style={{
              padding: "14px 16px",
              borderRadius: "var(--radius-inner)",
              background: "var(--panel-soft-2)",
              border: "1px solid var(--line)",
            }}
          >
            <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 8, marginBottom: 8 }}>
              <label style={{ margin: 0, fontWeight: 600 }}>{t.aiChat.maxTokens}</label>
              <StatusPill tone="neutral" label={String(config.max_tokens)} />
            </div>
            <input
              type="number"
              min="512"
              max="8192"
              value={config.max_tokens}
              onChange={(e) => updateConfig("max_tokens", parseInt(e.target.value))}
              className="input"
              style={{ background: "var(--panel)" }}
            />
          </div>

          <div className="grid-2">
            <div
              className="form-field"
              style={{
                padding: "14px 16px",
                borderRadius: "var(--radius-inner)",
                background: "var(--panel-soft-2)",
                border: "1px solid var(--line)",
              }}
            >
              <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 8, marginBottom: 8 }}>
                <label style={{ margin: 0, fontWeight: 600 }}>Top P</label>
                <StatusPill tone="info" label={config.top_p.toFixed(2)} />
              </div>
              <input
                type="range"
                min="0"
                max="1"
                step="0.05"
                value={config.top_p}
                onChange={(e) => updateConfig("top_p", parseFloat(e.target.value))}
                className="slider"
                style={{ accentColor: "var(--accent)" }}
              />
            </div>
            <div
              className="form-field"
              style={{
                padding: "14px 16px",
                borderRadius: "var(--radius-inner)",
                background: "var(--panel-soft-2)",
                border: "1px solid var(--line)",
              }}
            >
              <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 8, marginBottom: 8 }}>
                <label style={{ margin: 0, fontWeight: 600 }}>Top K</label>
                <StatusPill tone="neutral" label={String(config.top_k)} />
              </div>
              <input
                type="number"
                min="1"
                max="100"
                value={config.top_k}
                onChange={(e) => updateConfig("top_k", parseInt(e.target.value))}
                className="input"
                style={{ background: "var(--panel)" }}
              />
            </div>
          </div>
        </div>

        {/* Features & Integrations */}
        <div className="panel">
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12 }}>
            <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
              <span
                style={{
                  width: 36,
                  height: 36,
                  borderRadius: 12,
                  display: "grid",
                  placeItems: "center",
                  background: "var(--accent-2-soft)",
                  color: "var(--accent-2)",
                  flexShrink: 0,
                }}
              >
                <Zap size={18} />
              </span>
              <h3 style={{ margin: 0 }}>{t.aiChat.features}</h3>
            </div>
            <StatusPill
              tone="success"
              label={`${[config.enable_voice, config.enable_grammar, config.enable_topic].filter(Boolean).length}/3`}
            />
          </div>

          <div className="pill-grid">
            <div className="pill-item">
              <div>
                <div className="pill-title">{t.aiChat.voiceSupport}</div>
                <div className="pill-desc">{t.aiChat.voiceDesc}</div>
              </div>
              <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                <StatusPill tone={config.enable_voice ? "success" : "neutral"} label={config.enable_voice ? t.common.enabled : t.common.disabled} />
                <label className="toggle-switch">
                  <input
                    type="checkbox"
                    checked={config.enable_voice}
                    onChange={(e) => updateConfig("enable_voice", e.target.checked)}
                    style={{ accentColor: "var(--accent)" }}
                  />
                  <span className="toggle-slider"></span>
                </label>
              </div>
            </div>

            <div className="pill-item">
              <div>
                <div className="pill-title">{t.aiChat.grammarCheck}</div>
                <div className="pill-desc">{t.aiChat.grammarDesc}</div>
              </div>
              <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                <StatusPill tone={config.enable_grammar ? "success" : "neutral"} label={config.enable_grammar ? t.common.enabled : t.common.disabled} />
                <label className="toggle-switch">
                  <input
                    type="checkbox"
                    checked={config.enable_grammar}
                    onChange={(e) => updateConfig("enable_grammar", e.target.checked)}
                    style={{ accentColor: "var(--accent)" }}
                  />
                  <span className="toggle-slider"></span>
                </label>
              </div>
            </div>

            <div className="pill-item">
              <div>
                <div className="pill-title">{t.aiChat.topicAnalysis}</div>
                <div className="pill-desc">{t.aiChat.topicDesc}</div>
              </div>
              <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                <StatusPill tone={config.enable_topic ? "success" : "neutral"} label={config.enable_topic ? t.common.enabled : t.common.disabled} />
                <label className="toggle-switch">
                  <input
                    type="checkbox"
                    checked={config.enable_topic}
                    onChange={(e) => updateConfig("enable_topic", e.target.checked)}
                    style={{ accentColor: "var(--accent)" }}
                  />
                  <span className="toggle-slider"></span>
                </label>
              </div>
            </div>

            <div className="pill-item">
              <div>
                <div className="pill-title">{t.aiChat.mongodb}</div>
                <div className="pill-desc">{t.aiChat.mongodbDesc}</div>
              </div>
              <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                <StatusPill tone={config.use_mongodb ? "success" : "neutral"} label={config.use_mongodb ? t.common.enabled : t.common.disabled} />
                <label className="toggle-switch">
                  <input
                    type="checkbox"
                    checked={config.use_mongodb}
                    onChange={(e) => updateConfig("use_mongodb", e.target.checked)}
                    style={{ accentColor: "var(--accent)" }}
                  />
                  <span className="toggle-slider"></span>
                </label>
              </div>
            </div>
          </div>

          <div
            className="form-field"
            style={{
              padding: "14px 16px",
              borderRadius: "var(--radius-inner)",
              background: "var(--panel-soft-2)",
              border: "1px solid var(--line)",
            }}
          >
            <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 8, marginBottom: 8 }}>
              <label style={{ margin: 0, fontWeight: 600 }}>{t.aiChat.chatMemory}</label>
              <StatusPill tone="info" label={String(config.chat_memory_turns)} />
            </div>
            <input
              type="number"
              min="0"
              max="50"
              value={config.chat_memory_turns}
              onChange={(e) => updateConfig("chat_memory_turns", parseInt(e.target.value))}
              className="input"
              style={{ background: "var(--panel)" }}
            />
            <small className="text-muted" style={{ display: "block", marginTop: 6 }}>{t.aiChat.chatMemoryHint}</small>
          </div>
        </div>
      </div>

      {/* API Key Configuration */}
      <div className="panel">
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <span
              style={{
                width: 36,
                height: 36,
                borderRadius: 12,
                display: "grid",
                placeItems: "center",
                background: "var(--accent-soft)",
                color: "var(--accent)",
                flexShrink: 0,
              }}
            >
              <Key size={18} />
            </span>
            <h3 style={{ margin: 0 }}>{t.aiChat.apiKeyConfig}</h3>
          </div>
          <StatusPill
            tone={config.gemini_api_key ? "success" : "neutral"}
            label={config.gemini_api_key ? t.common.configured : t.common.notConfigured}
          />
        </div>

        <div
          className="form-field"
          style={{
            padding: "14px 16px",
            borderRadius: "var(--radius-inner)",
            background: "var(--panel-soft-2)",
            border: "1px solid var(--line)",
          }}
        >
          <label style={{ fontWeight: 600 }}>{t.aiChat.geminiApiKey}</label>
          <div style={{ display: "flex", gap: 8 }}>
            <input
              type={showApiKey ? "text" : "password"}
              value={config.gemini_api_key || ""}
              onChange={(e) => updateConfig("gemini_api_key", e.target.value)}
              placeholder="AIza..."
              className="input"
              style={{ flex: 1, background: "var(--panel)" }}
            />
            <button
              type="button"
              onClick={() => setShowApiKey(!showApiKey)}
              className="ghost-button"
              style={{ minWidth: 100 }}
            >
              {showApiKey ? t.aiChat.hide : t.aiChat.show}
            </button>
          </div>
          <small className="text-muted" style={{ display: "block", marginTop: 6 }}>{t.aiChat.apiKeyHint}</small>
        </div>

        <div className="info-callout">
          <p>
            <Lightbulb size={16} aria-hidden="true" /> {t.aiChat.apiKeyNote}
          </p>
        </div>
      </div>
    </div>
  );
};
