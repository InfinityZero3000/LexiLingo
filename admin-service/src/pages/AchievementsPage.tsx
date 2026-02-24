import React, { useEffect, useState, useRef } from "react";
import { DataTable } from "../components/DataTable";
import { SectionHeader } from "../components/SectionHeader";
import { EmptyState } from "../components/EmptyState";
import { StatusPill } from "../components/StatusPill";
import {
  listAchievements,
  createAchievement,
  updateAchievement,
  deleteAchievement,
  uploadBadgeImage,
  type AchievementItem,
} from "../lib/adminApi";
import { ENV } from "../lib/env";
import { useI18n } from "../lib/i18n";

const CATEGORIES = [
  "lessons", "streak", "vocabulary", "xp", "quiz", "course",
  "voice", "level", "special", "skill", "social", "milestone",
];
const RARITIES = ["common", "rare", "epic", "legendary"];
const CONDITION_TYPES = [
  "lesson_complete", "reach_streak", "vocab_mastered", "xp_earned",
  "perfect_score", "first_perfect", "course_complete", "voice_practice",
  "numeric_level", "study_time_night", "study_time_morning", "speed_lesson",
  "grammar_mastered", "culture_lesson", "writing_complete", "listening_complete",
  "social_interaction", "chat_complete", "help_others",
  "daily_challenge_complete", "comeback",
];

const rarityColor: Record<string, "info" | "success" | "warning" | "danger"> = {
  common: "info",
  rare: "success",
  epic: "warning",
  legendary: "danger",
};

const BACKEND_BASE = ENV.backendUrl.replace("/api/v1", "");
const CDN_BASE = "https://cdn.jsdelivr.net/gh/InfinityZero3000/LexiLingo@feature/flutter-app/assets/badges";

const badgeImgUrl = (icon?: string | null) => {
  if (!icon) return null;
  if (icon.startsWith("http")) return icon;
  if (icon.startsWith("/static")) return `${BACKEND_BASE}${icon}`;
  // If it's just a filename, use CDN
  if (icon.endsWith(".png") || icon.endsWith(".jpg") || icon.endsWith(".webp")) return `${CDN_BASE}/${icon}`;
  return null;
};

export const AchievementsPage = () => {
  const { t } = useI18n();
  const [items, setItems] = useState<AchievementItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState("");

  // Form
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [form, setForm] = useState({
    name: "",
    description: "",
    badge_icon: "",
    badge_color: "#4CAF50",
    condition_type: "lesson_complete",
    condition_value: 1,
    category: "lessons",
    rarity: "common",
    xp_reward: 0,
    gems_reward: 0,
    is_hidden: false,
  });

  const resetForm = () => {
    setForm({
      name: "", description: "", badge_icon: "", badge_color: "#4CAF50",
      condition_type: "lesson_complete", condition_value: 1,
      category: "lessons", rarity: "common", xp_reward: 0, gems_reward: 0, is_hidden: false,
    });
    setEditingId(null);
  };

  const loadItems = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await listAchievements();
      setItems(res.data || []);
    } catch (err: any) {
      setError(err?.message || t.achievements.loadFailed);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { void loadItems(); }, []);

  const handleEdit = (item: AchievementItem) => {
    setEditingId(item.id);
    setForm({
      name: item.name,
      description: item.description,
      badge_icon: item.badge_icon || "",
      badge_color: item.badge_color || "#4CAF50",
      condition_type: item.condition_type,
      condition_value: item.condition_value || 1,
      category: item.category,
      rarity: item.rarity,
      xp_reward: item.xp_reward,
      gems_reward: item.gems_reward,
      is_hidden: item.is_hidden,
    });
    setShowForm(true);
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setError(null);
    try {
      if (editingId) {
        await updateAchievement(editingId, form);
      } else {
        await createAchievement(form);
      }
      resetForm();
      setShowForm(false);
      await loadItems();
    } catch (err: any) {
      setError(err?.message || t.common.saveFailed);
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async (id: string) => {
    if (!confirm(t.achievements.deleteConfirm)) return;
    try {
      await deleteAchievement(id);
      await loadItems();
    } catch (err: any) {
      setError(err?.message || t.common.deleteFailed);
    }
  };

  const handleFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploading(true);
    try {
      const res = await uploadBadgeImage(file);
      if (res.data?.url) {
        setForm((f) => ({ ...f, badge_icon: res.data!.url }));
      }
    } catch (err: any) {
      setError(err?.message || "Upload failed");
    } finally {
      setUploading(false);
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
  };

  const filtered = filter
    ? items.filter((a) => a.category === filter)
    : items;

  // Group counts
  const categoryCounts: Record<string, number> = {};
  items.forEach((a) => { categoryCounts[a.category] = (categoryCounts[a.category] || 0) + 1; });

  return (
    <div className="stack">
      <SectionHeader title={t.achievements.title} description={`${items.length} ${t.achievements.description}`} />

      {error && <div className="form-error">{error}</div>}

      <div className="panel" style={{ padding: "12px 16px" }}>
        <div style={{ display: "flex", gap: 12, alignItems: "center", flexWrap: "wrap" }}>
          <select
            className="form-input"
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            style={{ width: 200 }}
          >
            <option value="">{t.achievements.allCategories} ({items.length})</option>
            {CATEGORIES.map((c) => (
              <option key={c} value={c}>{c} ({categoryCounts[c] || 0})</option>
            ))}
          </select>
          <div style={{ flex: 1 }} />
          <button className="primary-button" onClick={() => { resetForm(); setShowForm(true); }}>
            {t.achievements.createAchievement}
          </button>
        </div>
      </div>

      <div className="panel">
        {loading ? (
          <div className="loading">{t.common.loading}</div>
        ) : filtered.length === 0 ? (
          <EmptyState title={t.achievements.noAchievements} description={t.achievements.noAchievementsDesc} />
        ) : (
          <DataTable
            columns={[
              {
                header: "Badge",
                render: (row) => {
                  const imgUrl = badgeImgUrl(row.badge_icon);
                  return imgUrl ? (
                    <img
                      src={imgUrl}
                      alt={row.name}
                      style={{
                        width: 44, height: 44, objectFit: "contain", borderRadius: 8,
                        background: "var(--panel-soft)", padding: 2,
                      }}
                    />
                  ) : (
                    <div style={{
                      width: 44, height: 44, background: row.badge_color || "var(--panel-soft)",
                      borderRadius: 8, display: "flex", alignItems: "center", justifyContent: "center",
                      fontSize: 11, color: "#fff", fontWeight: 600,
                    }}>
                      {row.name.substring(0, 2).toUpperCase()}
                    </div>
                  );
                },
                align: "center",
              },
              {
                header: "Achievement",
                render: (row) => (
                  <div>
                    <div className="table-title">{row.name}</div>
                    <div className="table-sub">{row.description}</div>
                    {row.slug && <div className="table-sub" style={{ opacity: 0.5, fontSize: 11 }}>{row.slug}</div>}
                  </div>
                ),
              },
              {
                header: t.achievements.category,
                render: (row) => <span className="table-meta">{row.category}</span>,
                align: "center",
              },
              {
                header: t.achievements.rarity,
                render: (row) => (
                  <StatusPill tone={rarityColor[row.rarity] || "info"} label={row.rarity} />
                ),
                align: "center",
              },
              {
                header: t.achievements.condition,
                render: (row) => (
                  <span className="table-meta">{row.condition_type} &ge; {row.condition_value}</span>
                ),
              },
              {
                header: t.achievements.reward,
                render: (row) => (
                  <span className="table-meta">
                    {row.xp_reward > 0 ? `${row.xp_reward} XP` : ""}
                    {row.xp_reward > 0 && row.gems_reward > 0 ? " + " : ""}
                    {row.gems_reward > 0 ? `${row.gems_reward} Gems` : ""}
                    {row.xp_reward === 0 && row.gems_reward === 0 ? "\u2014" : ""}
                  </span>
                ),
                align: "right",
              },
              {
                header: "",
                render: (row) => (
                  <div className="table-actions">
                    <button className="ghost-button small" onClick={() => handleEdit(row)}>{t.common.edit}</button>
                    <button className="ghost-button small danger" onClick={() => handleDelete(row.id)}>{t.common.delete}</button>
                  </div>
                ),
                align: "right",
              },
            ]}
            rows={filtered}
          />
        )}
      </div>

      {/* Create/Edit Modal */}
      {showForm && (
        <div className="modal-overlay" onClick={() => setShowForm(false)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 560 }}>
            <h3>{editingId ? t.achievements.editAchievement : t.achievements.createNew}</h3>
            <form className="form" onSubmit={handleSave}>
              <label>
                {t.achievements.nameRequired}
                <input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required />
              </label>
              <label>
                {t.achievements.descriptionRequired}
                <textarea rows={2} value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} required />
              </label>

              {/* Badge Image */}
              <label>
                Badge Image
                <div style={{ display: "flex", gap: 8, alignItems: "flex-start", marginTop: 4 }}>
                  <div style={{ flex: 1 }}>
                    <input
                      type="text"
                      value={form.badge_icon}
                      onChange={(e) => setForm({ ...form, badge_icon: e.target.value })}
                      placeholder="/static/badges/streak7.png or https://..."
                      style={{ width: "100%", marginBottom: 6 }}
                    />
                    <div style={{ display: "flex", gap: 6 }}>
                      <button
                        type="button"
                        className="ghost-button small"
                        onClick={() => fileInputRef.current?.click()}
                        disabled={uploading}
                      >
                        {uploading ? "Uploading..." : "Upload Image"}
                      </button>
                      <input
                        ref={fileInputRef}
                        type="file"
                        accept="image/png,image/jpeg,image/webp,image/svg+xml"
                        style={{ display: "none" }}
                        onChange={handleFileUpload}
                      />
                    </div>
                  </div>
                  {/* Preview */}
                  <div style={{
                    width: 64, height: 64, borderRadius: 8,
                    border: "1px solid var(--line)", background: "var(--panel-soft)",
                    display: "flex", alignItems: "center", justifyContent: "center",
                    overflow: "hidden", flexShrink: 0,
                  }}>
                    {badgeImgUrl(form.badge_icon) ? (
                      <img src={badgeImgUrl(form.badge_icon)!} alt="Preview" style={{ width: 56, height: 56, objectFit: "contain" }} />
                    ) : (
                      <span style={{ fontSize: 11, color: "var(--muted)" }}>No image</span>
                    )}
                  </div>
                </div>
              </label>

              <div className="form-row">
                <label>
                  Badge Color
                  <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
                    <input
                      type="color"
                      value={form.badge_color}
                      onChange={(e) => setForm({ ...form, badge_color: e.target.value })}
                      style={{ width: 40, height: 34, padding: 2, cursor: "pointer" }}
                    />
                    <input
                      type="text"
                      value={form.badge_color}
                      onChange={(e) => setForm({ ...form, badge_color: e.target.value })}
                      style={{ flex: 1 }}
                      placeholder="#4CAF50"
                    />
                  </div>
                </label>
              </div>

              <div className="form-row">
                <label>
                  {t.achievements.conditionRequired}
                  <select value={form.condition_type} onChange={(e) => setForm({ ...form, condition_type: e.target.value })}>
                    {CONDITION_TYPES.map((ct) => <option key={ct} value={ct}>{ct}</option>)}
                  </select>
                </label>
                <label>
                  {t.achievements.conditionValueLabel}
                  <input type="number" min={1} value={form.condition_value} onChange={(e) => setForm({ ...form, condition_value: Number(e.target.value) })} />
                </label>
              </div>
              <div className="form-row">
                <label>
                  {t.achievements.categoryLabel}
                  <select value={form.category} onChange={(e) => setForm({ ...form, category: e.target.value })}>
                    {CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
                  </select>
                </label>
                <label>
                  {t.achievements.rarityLabel}
                  <select value={form.rarity} onChange={(e) => setForm({ ...form, rarity: e.target.value })}>
                    {RARITIES.map((r) => <option key={r} value={r}>{r}</option>)}
                  </select>
                </label>
              </div>
              <div className="form-row">
                <label>
                  {t.achievements.xpRewardLabel}
                  <input type="number" min={0} value={form.xp_reward} onChange={(e) => setForm({ ...form, xp_reward: Number(e.target.value) })} />
                </label>
                <label>
                  {t.achievements.gemsRewardLabel}
                  <input type="number" min={0} value={form.gems_reward} onChange={(e) => setForm({ ...form, gems_reward: Number(e.target.value) })} />
                </label>
              </div>
              <label style={{ display: "flex", alignItems: "center", gap: 8 }}>
                <input
                  type="checkbox"
                  checked={form.is_hidden}
                  onChange={(e) => setForm({ ...form, is_hidden: e.target.checked })}
                />
                {t.achievements.hiddenUntilUnlocked}
              </label>
              <div style={{ display: "flex", gap: 8, justifyContent: "flex-end" }}>
                <button className="ghost-button" type="button" onClick={() => setShowForm(false)}>{t.common.cancel}</button>
                <button className="primary-button" type="submit" disabled={saving}>
                  {saving ? t.common.saving : editingId ? t.common.update : t.common.create}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
