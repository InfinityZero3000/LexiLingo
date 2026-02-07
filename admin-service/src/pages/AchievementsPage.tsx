import React, { useEffect, useState } from "react";
import { DataTable } from "../components/DataTable";
import { SectionHeader } from "../components/SectionHeader";
import { EmptyState } from "../components/EmptyState";
import { StatusPill } from "../components/StatusPill";
import {
  listAchievements,
  createAchievement,
  updateAchievement,
  deleteAchievement,
  type AchievementItem,
} from "../lib/adminApi";

const CATEGORIES = ["streak", "lessons", "social", "vocabulary", "grammar", "special"];
const RARITIES = ["common", "rare", "epic", "legendary"];
const CONDITION_TYPES = [
  "reach_streak", "complete_lessons", "pass_level", "learn_words",
  "earn_xp", "complete_course", "perfect_score", "social_share",
];

const rarityColor: Record<string, "info" | "success" | "warning" | "danger"> = {
  common: "info",
  rare: "success",
  epic: "warning",
  legendary: "danger",
};

export const AchievementsPage = () => {
  const [items, setItems] = useState<AchievementItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState("");

  // Form
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [form, setForm] = useState({
    name: "",
    description: "",
    condition_type: "reach_streak",
    condition_value: 1,
    category: "special",
    rarity: "common",
    xp_reward: 0,
    gems_reward: 0,
    is_hidden: false,
  });

  const resetForm = () => {
    setForm({
      name: "", description: "", condition_type: "reach_streak", condition_value: 1,
      category: "special", rarity: "common", xp_reward: 0, gems_reward: 0, is_hidden: false,
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
      setError(err?.message || "Lỗi tải achievements");
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
      setError(err?.message || "Lưu thất bại");
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async (id: string) => {
    if (!confirm("Xóa achievement này?")) return;
    try {
      await deleteAchievement(id);
      await loadItems();
    } catch (err: any) {
      setError(err?.message || "Xóa thất bại");
    }
  };

  const filtered = filter
    ? items.filter((a) => a.category === filter)
    : items;

  return (
    <div className="stack">
      <SectionHeader title="Quản lý Achievements" description={`${items.length} thành tựu`} />

      {error && <div className="form-error">{error}</div>}

      <div className="panel" style={{ padding: "12px 16px" }}>
        <div style={{ display: "flex", gap: 12, alignItems: "center", flexWrap: "wrap" }}>
          <select
            className="form-input"
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            style={{ width: 180 }}
          >
            <option value="">Tất cả danh mục</option>
            {CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
          </select>
          <div style={{ flex: 1 }} />
          <button className="primary-button" onClick={() => { resetForm(); setShowForm(true); }}>
            + Thêm Achievement
          </button>
        </div>
      </div>

      <div className="panel">
        {loading ? (
          <div className="loading">Đang tải...</div>
        ) : filtered.length === 0 ? (
          <EmptyState title="Chưa có achievement" description="Tạo thành tựu mới cho hệ thống." />
        ) : (
          <DataTable
            columns={[
              {
                header: "Achievement",
                render: (row) => (
                  <div>
                    <div className="table-title">{row.name}</div>
                    <div className="table-sub">{row.description}</div>
                  </div>
                ),
              },
              {
                header: "Danh mục",
                render: (row) => <span className="table-meta">{row.category}</span>,
                align: "center",
              },
              {
                header: "Độ hiếm",
                render: (row) => (
                  <StatusPill tone={rarityColor[row.rarity] || "info"} label={row.rarity} />
                ),
                align: "center",
              },
              {
                header: "Điều kiện",
                render: (row) => (
                  <span className="table-meta">{row.condition_type} ≥ {row.condition_value}</span>
                ),
              },
              {
                header: "Phần thưởng",
                render: (row) => (
                  <span className="table-meta">
                    {row.xp_reward > 0 ? `${row.xp_reward} XP` : ""}
                    {row.xp_reward > 0 && row.gems_reward > 0 ? " • " : ""}
                    {row.gems_reward > 0 ? `${row.gems_reward} 💎` : ""}
                    {row.xp_reward === 0 && row.gems_reward === 0 ? "—" : ""}
                  </span>
                ),
                align: "right",
              },
              {
                header: "",
                render: (row) => (
                  <div className="table-actions">
                    <button className="ghost-button small" onClick={() => handleEdit(row)}>Sửa</button>
                    <button className="ghost-button small danger" onClick={() => handleDelete(row.id)}>Xóa</button>
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
            <h3>{editingId ? "Chỉnh sửa Achievement" : "Tạo Achievement mới"}</h3>
            <form className="form" onSubmit={handleSave}>
              <label>
                Tên *
                <input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required />
              </label>
              <label>
                Mô tả *
                <textarea rows={2} value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} required />
              </label>
              <div className="form-row">
                <label>
                  Điều kiện *
                  <select value={form.condition_type} onChange={(e) => setForm({ ...form, condition_type: e.target.value })}>
                    {CONDITION_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
                  </select>
                </label>
                <label>
                  Giá trị
                  <input type="number" min={1} value={form.condition_value} onChange={(e) => setForm({ ...form, condition_value: Number(e.target.value) })} />
                </label>
              </div>
              <div className="form-row">
                <label>
                  Danh mục
                  <select value={form.category} onChange={(e) => setForm({ ...form, category: e.target.value })}>
                    {CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
                  </select>
                </label>
                <label>
                  Độ hiếm
                  <select value={form.rarity} onChange={(e) => setForm({ ...form, rarity: e.target.value })}>
                    {RARITIES.map((r) => <option key={r} value={r}>{r}</option>)}
                  </select>
                </label>
              </div>
              <div className="form-row">
                <label>
                  XP thưởng
                  <input type="number" min={0} value={form.xp_reward} onChange={(e) => setForm({ ...form, xp_reward: Number(e.target.value) })} />
                </label>
                <label>
                  Gems thưởng
                  <input type="number" min={0} value={form.gems_reward} onChange={(e) => setForm({ ...form, gems_reward: Number(e.target.value) })} />
                </label>
              </div>
              <label style={{ display: "flex", alignItems: "center", gap: 8 }}>
                <input
                  type="checkbox"
                  checked={form.is_hidden}
                  onChange={(e) => setForm({ ...form, is_hidden: e.target.checked })}
                />
                Ẩn cho đến khi mở khóa
              </label>
              <div style={{ display: "flex", gap: 8, justifyContent: "flex-end" }}>
                <button className="ghost-button" type="button" onClick={() => setShowForm(false)}>Hủy</button>
                <button className="primary-button" type="submit" disabled={saving}>
                  {saving ? "Đang lưu..." : editingId ? "Cập nhật" : "Tạo"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
