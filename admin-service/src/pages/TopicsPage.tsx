import React, { useEffect, useState } from "react";
import {
  BadgeCheck,
  Banknote,
  BookOpen,
  BriefcaseBusiness,
  Building2,
  Car,
  GraduationCap,
  HeartPulse,
  Home,
  Landmark,
  MapPinned,
  MessageSquare,
  Mic,
  Plane,
  PlugZap,
  School,
  Settings2,
  ShoppingCart,
  Sparkles,
  Stethoscope,
  Users,
  Utensils,
  Wifi,
  Wrench,
} from "lucide-react";

import { DataTable } from "../components/DataTable";
import { EmptyState } from "../components/EmptyState";
import { SectionHeader } from "../components/SectionHeader";
import { StatusPill } from "../components/StatusPill";
import { TableSkeleton } from "../components/Skeleton";
import {
  createTopicStoryAdmin,
  listTopicStoriesAdmin,
  type TopicDifficulty,
  type TopicItem,
} from "../lib/adminApi";

const DIFFICULTIES: TopicDifficulty[] = ["A1", "A2", "B1", "B2", "C1", "C2"];

const TOPIC_ICONS = [
  { key: "travel", label: "Travel", icon: Plane },
  { key: "hotel", label: "Hotel", icon: Building2 },
  { key: "directions", label: "Directions", icon: MapPinned },
  { key: "transport", label: "Transport", icon: Car },
  { key: "work", label: "Work", icon: BriefcaseBusiness },
  { key: "finance", label: "Finance", icon: Banknote },
  { key: "shopping", label: "Shopping", icon: ShoppingCart },
  { key: "food", label: "Food", icon: Utensils },
  { key: "health", label: "Health", icon: HeartPulse },
  { key: "doctor", label: "Doctor", icon: Stethoscope },
  { key: "education", label: "Education", icon: GraduationCap },
  { key: "library", label: "Library", icon: BookOpen },
  { key: "technology", label: "Technology", icon: PlugZap },
  { key: "internet", label: "Internet", icon: Wifi },
  { key: "services", label: "Services", icon: Settings2 },
  { key: "repair", label: "Repair", icon: Wrench },
  { key: "housing", label: "Housing", icon: Home },
  { key: "culture", label: "Culture", icon: Landmark },
  { key: "social", label: "Social", icon: Users },
  { key: "media", label: "Media", icon: Mic },
  { key: "classroom", label: "Classroom", icon: School },
  { key: "achievement", label: "Achievement", icon: BadgeCheck },
  { key: "ai", label: "AI", icon: Sparkles },
  { key: "chat", label: "Chat", icon: MessageSquare },
];

const CATEGORIES = [
  "travel",
  "work",
  "services",
  "health",
  "food",
  "social",
  "finance",
  "shopping",
  "education",
  "technology",
  "housing",
  "culture",
  "leisure",
  "media",
  "emergency",
  "daily_life",
];

const iconFor = (key?: string | null) => {
  const normalized = (key || "").toLowerCase();
  return TOPIC_ICONS.find((item) => item.key === normalized)?.icon || MessageSquare;
};

const splitTags = (value: string) =>
  value
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);

export const TopicsPage = () => {
  const [topics, setTopics] = useState<TopicItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [isEditing, setIsEditing] = useState(false);
  const [form, setForm] = useState({
    story_id: "",
    title_en: "",
    title_vi: "",
    difficulty_level: "A2" as TopicDifficulty,
    category: "travel",
    estimated_minutes: 15,
    icon_key: "travel",
    opening_prompt: "",
    suggested_prompts: "",
    tags: "",
  });

  const loadTopics = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await listTopicStoriesAdmin();
      setTopics(res.data?.topics || []);
    } catch (err: any) {
      setError(err?.message || "Không tải được topic.");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void loadTopics();
  }, []);

  const resetForm = () => {
    setForm({
      story_id: "",
      title_en: "",
      title_vi: "",
      difficulty_level: "A2",
      category: "travel",
      estimated_minutes: 15,
      icon_key: "travel",
      opening_prompt: "",
      suggested_prompts: "",
      tags: "",
    });
    setIsEditing(false);
  };

  const handleEdit = (topic: TopicItem) => {
    setForm({
      story_id: topic.story_id,
      title_en: topic.title.en,
      title_vi: topic.title.vi,
      difficulty_level: topic.difficulty_level,
      category: topic.category,
      estimated_minutes: topic.estimated_minutes,
      icon_key: topic.icon_key || topic.category,
      opening_prompt: "",
      suggested_prompts: (topic.suggested_prompts || []).join(", "),
      tags: (topic.tags || []).join(", "),
    });
    setIsEditing(true);
    setShowForm(true);
  };

  const handleSave = async (event: React.FormEvent) => {
    event.preventDefault();
    setSaving(true);
    setError(null);
    try {
      await createTopicStoryAdmin({
        story_id: form.story_id || undefined,
        title: {
          en: form.title_en,
          vi: form.title_vi || form.title_en,
        },
        difficulty_level: form.difficulty_level,
        category: form.category,
        estimated_minutes: Number(form.estimated_minutes) || 15,
        icon_key: form.icon_key,
        opening_prompt: form.opening_prompt || undefined,
        suggested_prompts: splitTags(form.suggested_prompts),
        tags: splitTags(form.tags),
        is_published: true,
      });
      resetForm();
      setShowForm(false);
      setIsEditing(false);
      await loadTopics();
    } catch (err: any) {
      setError(err?.message || "Không tạo được topic");
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="stack">
      <SectionHeader
        title="Conversation Topics"
        description={`${topics.length} topic chat scenarios from AI service`}
      />

      {error && <div className="form-error">{error}</div>}

      <div className="panel" style={{ padding: "12px 16px" }}>
        <div style={{ display: "flex", justifyContent: "space-between", gap: 12, flexWrap: "wrap" }}>
          <div>
            <div className="table-title">Topic catalog</div>
            <div className="table-sub">Create topics with icon keys shown in the mobile Topic tab.</div>
          </div>
          <button
            className="primary-button"
            onClick={() => {
              resetForm();
              setShowForm((value) => !value);
            }}
          >
            {showForm && !isEditing ? "Ẩn form" : "Create Topic"}
          </button>
        </div>
      </div>

      {showForm && (
        <form className="panel" onSubmit={handleSave} style={{ padding: 16 }}>
          <h4 style={{ margin: "0 0 12px", fontSize: 15, fontWeight: 600 }}>
            {isEditing ? `Sửa topic: ${form.title_en}` : "Tạo topic mới"}
          </h4>
          <div className="form-grid">
            <label>
              English title
              <input
                required
                value={form.title_en}
                onChange={(e) => setForm({ ...form, title_en: e.target.value })}
              />
            </label>
            <label>
              Vietnamese title
              <input
                value={form.title_vi}
                onChange={(e) => setForm({ ...form, title_vi: e.target.value })}
              />
            </label>
            <label>
              Story ID
              <input
                placeholder="Auto generated if empty"
                value={form.story_id}
                onChange={(e) => setForm({ ...form, story_id: e.target.value })}
              />
            </label>
            <label>
              Category
              <select
                value={form.category}
                onChange={(e) => setForm({ ...form, category: e.target.value })}
              >
                {CATEGORIES.map((category) => (
                  <option key={category} value={category}>{category}</option>
                ))}
              </select>
            </label>
            <label>
              Difficulty
              <select
                value={form.difficulty_level}
                onChange={(e) => setForm({ ...form, difficulty_level: e.target.value as TopicDifficulty })}
              >
                {DIFFICULTIES.map((level) => (
                  <option key={level} value={level}>{level}</option>
                ))}
              </select>
            </label>
            <label>
              Minutes
              <input
                type="number"
                min={5}
                max={60}
                value={form.estimated_minutes}
                onChange={(e) => setForm({ ...form, estimated_minutes: Number(e.target.value) })}
              />
            </label>
          </div>

          <label>
            Opening prompt
            <textarea
              rows={3}
              value={form.opening_prompt}
              onChange={(e) => setForm({ ...form, opening_prompt: e.target.value })}
            />
          </label>

          <div>
            <div className="table-title" style={{ marginBottom: 8 }}>Icon</div>
            <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
              {TOPIC_ICONS.map((item) => {
                const Icon = item.icon;
                const selected = form.icon_key === item.key;
                return (
                  <button
                    key={item.key}
                    type="button"
                    className={selected ? "primary-button" : "ghost-button"}
                    onClick={() => setForm({ ...form, icon_key: item.key })}
                    style={{ display: "inline-flex", alignItems: "center", gap: 6 }}
                  >
                    <Icon size={16} />
                    {item.label}
                  </button>
                );
              })}
            </div>
          </div>

          <div className="form-grid">
            <label>
              Suggested prompts
              <input
                placeholder="comma separated"
                value={form.suggested_prompts}
                onChange={(e) => setForm({ ...form, suggested_prompts: e.target.value })}
              />
            </label>
            <label>
              Tags
              <input
                placeholder="comma separated"
                value={form.tags}
                onChange={(e) => setForm({ ...form, tags: e.target.value })}
              />
            </label>
          </div>

          <div style={{ display: "flex", justifyContent: "flex-end", gap: 8 }}>
            <button className="ghost-button" type="button" onClick={() => { resetForm(); setShowForm(false); }}>
              Cancel
            </button>
            <button className="primary-button" type="submit" disabled={saving}>
              {saving ? "Saving..." : isEditing ? "Cập nhật Topic" : "Save Topic"}
            </button>
          </div>
        </form>
      )}

      <div className="panel">
        {loading ? (
          <TableSkeleton rows={5} cols={5} />
        ) : topics.length === 0 ? (
          <EmptyState
            title="No topics"
            description="Create the first topic from this admin panel."
            icon={<MessageSquare size={40} aria-hidden="true" />}
            action={<button className="primary-button" onClick={() => setShowForm(true)}>Create Topic</button>}
          />
        ) : (
          <DataTable
            columns={[
              {
                header: "Topic",
                render: (row) => {
                  const Icon = iconFor(row.icon_key || row.category);
                  return (
                    <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                      <span className="stat-icon" style={{ width: 36, height: 36 }}>
                        <Icon size={18} />
                      </span>
                      <div>
                        <div className="table-title">{row.title.en}</div>
                        <div className="table-sub">{row.title.vi}</div>
                      </div>
                    </div>
                  );
                },
              },
              { header: "Category", render: (row) => <StatusPill tone="info" label={row.category} /> },
              { header: "Level", render: (row) => <StatusPill tone="warning" label={row.difficulty_level} />, align: "center" },
              { header: "Icon", render: (row) => <span className="table-meta">{row.icon_key || row.category}</span> },
              { header: "Minutes", render: (row) => <span className="table-meta">{row.estimated_minutes}</span>, align: "center" },
              {
                header: "",
                render: (row) => (
                  <button
                    className="ghost-button small"
                    onClick={() => handleEdit(row)}
                    type="button"
                  >
                    Sửa
                  </button>
                ),
                align: "right",
              },
            ]}
            rows={topics}
          />
        )}
      </div>
    </div>
  );
};
