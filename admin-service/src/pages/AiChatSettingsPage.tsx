import React, { useEffect, useState } from "react";
import { SectionHeader } from "../components/SectionHeader";
import { StatCard } from "../components/StatCard";
import { StatusPill } from "../components/StatusPill";
import { useI18n } from "../lib/i18n";
import { Bot, MessageSquare, Zap, Key, Database, Settings } from "lucide-react";

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

  useEffect(() => {
    fetchConfig();
  }, []);

  const fetchConfig = async () => {
    try {
      const response = await fetch(`${import.meta.env.VITE_AI_URL}/admin/config`, {
        headers: { Authorization: `Bearer ${localStorage.getItem("access_token")}` },
      });
      const data = await response.json();
      setConfig(data.data || getDefaultConfig());
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
    try {
      await fetch(`${import.meta.env.VITE_AI_URL}/admin/config`, {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${localStorage.getItem("access_token")}`,
        },
        body: JSON.stringify(config),
      });
      alert(t.common.success);
    } catch (error) {
      console.error("Failed to save config:", error);
      alert(t.common.saveFailed);
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
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
        <SectionHeader 
          title={t.aiChat.title} 
          description={t.aiChat.description} 
        />
        <button 
          className="btn-primary" 
          onClick={handleSave}
          disabled={saving}
        >
          {saving ? t.common.saving : t.common.save}
        </button>
      </div>

      {/* Quick Stats */}
      <div className="card-grid">
        <StatCard
          label={t.aiChat.model}
          value={config.gemini_model.split("-")[1] || "Flash"}
          note={`Gemini ${config.gemini_model.includes("2.0") ? "2.0" : "1.5"}`}
          accent="teal"
        />
        <StatCard
          label={t.aiChat.temperature}
          value={config.temperature.toFixed(2)}
          note={t.aiChat.creativity}
          accent="orange"
        />
        <StatCard
          label={t.aiChat.maxTokens}
          value={String(config.max_tokens)}
          note={t.aiChat.responseLength}
          accent="berry"
        />
        <StatCard
          label={t.aiChat.features}
          value={`${[config.enable_voice, config.enable_grammar, config.enable_topic].filter(Boolean).length}/3`}
          note={t.aiChat.modulesEnabled}
          accent="purple"
        />
      </div>

      <div className="grid-2">
        {/* Gemini Model Settings */}
        <div className="panel">
          <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 16 }}>
            <Bot size={20} style={{ color: "var(--accent)" }} />
            <h3 style={{ margin: 0 }}>{t.aiChat.modelSettings}</h3>
          </div>
          
          <div className="form-field">
            <label>{t.aiChat.model}</label>
            <select 
              value={config.gemini_model}
              onChange={(e) => updateConfig("gemini_model", e.target.value)}
              className="input"
            >
              <option value="gemini-2.0-flash-exp">Gemini 2.0 Flash (Experimental)</option>
              <option value="gemini-1.5-flash">Gemini 1.5 Flash</option>
              <option value="gemini-1.5-pro">Gemini 1.5 Pro</option>
            </select>
          </div>

          <div className="form-field">
            <label>{t.aiChat.temperature} ({config.temperature})</label>
            <input
              type="range"
              min="0"
              max="2"
              step="0.1"
              value={config.temperature}
              onChange={(e) => updateConfig("temperature", parseFloat(e.target.value))}
              className="slider"
            />
            <small>{t.aiChat.temperatureHint}</small>
          </div>

          <div className="form-field">
            <label>{t.aiChat.maxTokens}</label>
            <input
              type="number"
              min="512"
              max="8192"
              value={config.max_tokens}
              onChange={(e) => updateConfig("max_tokens", parseInt(e.target.value))}
              className="input"
            />
          </div>

          <div className="grid-2">
            <div className="form-field">
              <label>Top P ({config.top_p})</label>
              <input
                type="range"
                min="0"
                max="1"
                step="0.05"
                value={config.top_p}
                onChange={(e) => updateConfig("top_p", parseFloat(e.target.value))}
                className="slider"
              />
            </div>
            <div className="form-field">
              <label>Top K ({config.top_k})</label>
              <input
                type="number"
                min="1"
                max="100"
                value={config.top_k}
                onChange={(e) => updateConfig("top_k", parseInt(e.target.value))}
                className="input"
              />
            </div>
          </div>
        </div>

        {/* Features & Integrations */}
        <div className="panel">
          <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 16 }}>
            <Zap size={20} style={{ color: "var(--accent)" }} />
            <h3 style={{ margin: 0 }}>{t.aiChat.features}</h3>
          </div>

          <div className="pill-grid">
            <div className="pill-item">
              <div>
                <div className="pill-title">{t.aiChat.voiceSupport}</div>
                <div className="pill-desc">{t.aiChat.voiceDesc}</div>
              </div>
              <label className="toggle-switch">
                <input
                  type="checkbox"
                  checked={config.enable_voice}
                  onChange={(e) => updateConfig("enable_voice", e.target.checked)}
                />
                <span className="toggle-slider"></span>
              </label>
            </div>

            <div className="pill-item">
              <div>
                <div className="pill-title">{t.aiChat.grammarCheck}</div>
                <div className="pill-desc">{t.aiChat.grammarDesc}</div>
              </div>
              <label className="toggle-switch">
                <input
                  type="checkbox"
                  checked={config.enable_grammar}
                  onChange={(e) => updateConfig("enable_grammar", e.target.checked)}
                />
                <span className="toggle-slider"></span>
              </label>
            </div>

            <div className="pill-item">
              <div>
                <div className="pill-title">{t.aiChat.topicAnalysis}</div>
                <div className="pill-desc">{t.aiChat.topicDesc}</div>
              </div>
              <label className="toggle-switch">
                <input
                  type="checkbox"
                  checked={config.enable_topic}
                  onChange={(e) => updateConfig("enable_topic", e.target.checked)}
                />
                <span className="toggle-slider"></span>
              </label>
            </div>

            <div className="pill-item">
              <div>
                <div className="pill-title">{t.aiChat.mongodb}</div>
                <div className="pill-desc">{t.aiChat.mongodbDesc}</div>
              </div>
              <label className="toggle-switch">
                <input
                  type="checkbox"
                  checked={config.use_mongodb}
                  onChange={(e) => updateConfig("use_mongodb", e.target.checked)}
                />
                <span className="toggle-slider"></span>
              </label>
            </div>
          </div>

          <div className="form-field" style={{ marginTop: 16 }}>
            <label>{t.aiChat.chatMemory}</label>
            <input
              type="number"
              min="0"
              max="50"
              value={config.chat_memory_turns}
              onChange={(e) => updateConfig("chat_memory_turns", parseInt(e.target.value))}
              className="input"
            />
            <small>{t.aiChat.chatMemoryHint}</small>
          </div>
        </div>
      </div>

      {/* API Key Warning */}
      <div className="panel" style={{ padding: 16, background: "#FFF7ED", border: "1px solid #FDBA74" }}>
        <div style={{ display: "flex", gap: 12, alignItems: "flex-start" }}>
          <Key size={20} style={{ color: "#C2410C", marginTop: 2 }} />
          <div>
            <h4 style={{ margin: "0 0 4px", color: "#C2410C" }}>{t.aiChat.apiKeyWarning}</h4>
            <p style={{ margin: 0, fontSize: 14, color: "#9A3412" }}>
              {t.aiChat.apiKeyWarningDesc}
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};
