import React, { useEffect, useState } from "react";
import { DataTable } from "../components/DataTable";
import { SectionHeader } from "../components/SectionHeader";
import { EmptyState } from "../components/EmptyState";
import { StatusPill } from "../components/StatusPill";
import {
  listShopItems,
  createShopItem,
  updateShopItem,
  deleteShopItem,
  type ShopItemType,
} from "../lib/adminApi";
import { useI18n } from "../lib/i18n";

// Mirrors the item_type values actually seeded in backend-service/app/core/shop_catalog.py.
const ITEM_TYPES = [
  // Boosts
  "streak_freeze",
  "double_xp",
  "hint_pack",
  "heart_refill",
  // Cosmetics
  "avatar",
  "theme",
  // In-game power-ups
  "time_freeze",
  "extra_time",
  "skip_token",
  "reveal_hint",
  "translate_hint",
  "mistake_shield",
  "extra_heart",
  "lucky_clover",
  "score_multiplier",
  "pair_swap",
];

// Quick-create templates mirroring backend-service/app/core/shop_catalog.py, so
// picking an item_type fills in a sensible, already-working default instead of
// the admin having to know each item's expected effects payload shape by heart.
const ITEM_TYPE_TEMPLATES: Record<
  string,
  { name: string; description: string; price_gems: number; effects: Record<string, unknown> }
> = {
  streak_freeze: { name: "Streak Freeze", description: "Add one streak freeze", price_gems: 25, effects: { quantity: 1 } },
  double_xp: { name: "Double XP (1 hour)", description: "Earn double XP for 1 hour", price_gems: 25, effects: { duration_hours: 1, multiplier: 2 } },
  hint_pack: { name: "Hint Pack (5)", description: "Add 5 hints to your active lesson", price_gems: 12, effects: { quantity: 5 } },
  heart_refill: { name: "Heart Refill", description: "Restore your active lesson to 3 hearts", price_gems: 15, effects: { hearts: 3 } },
  avatar: { name: "New Avatar", description: "Exclusive profile avatar", price_gems: 50, effects: { avatar_url: "" } },
  theme: { name: "New Theme", description: "Unlockable app theme", price_gems: 50, effects: {} },
  time_freeze: { name: "Time Freeze", description: "Pause the countdown timer for 10 seconds in any timed game", price_gems: 10, effects: { seconds: 10 } },
  extra_time: { name: "Extra Time", description: "Add 20 seconds straight to the clock in any timed game", price_gems: 15, effects: { seconds: 20 } },
  skip_token: { name: "Skip Token", description: "Skip the current word or question with no penalty", price_gems: 12, effects: {} },
  reveal_hint: { name: "Magnifying Glass", description: "Free reveal: the next letter, or eliminate 2 wrong options", price_gems: 8, effects: { mode: "letter" } },
  translate_hint: { name: "Quick Translate", description: "Reveal the Vietnamese translation of the current word", price_gems: 8, effects: { mode: "translation" } },
  mistake_shield: { name: "Shield", description: "Negate the next wrong answer or life loss", price_gems: 18, effects: {} },
  extra_heart: { name: "Extra Heart", description: "Start Hangman with one extra life", price_gems: 15, effects: { lives: 1 } },
  lucky_clover: { name: "Lucky Clover", description: "30% chance to auto-correct your next wrong answer", price_gems: 20, effects: { chance: 0.3 } },
  score_multiplier: { name: "Score Multiplier", description: "Double your in-game score for the rest of this session", price_gems: 22, effects: { multiplier: 2 } },
  pair_swap: { name: "Pair Swap", description: "Undo one wrong match in Matching Game for a free retry", price_gems: 10, effects: {} },
};

type ShopItemForm = {
  name: string;
  description: string;
  item_type: string;
  price_gems: number;
  is_available: boolean;
  stock_quantity: number | undefined;
  icon_url: string;
  effectsText: string;
};

const EMPTY_FORM: ShopItemForm = {
  name: "",
  description: "",
  item_type: "streak_freeze",
  price_gems: 50,
  is_available: true,
  stock_quantity: undefined,
  icon_url: "",
  effectsText: "{}",
};

export const ShopPage = () => {
  const { t } = useI18n();
  const [items, setItems] = useState<ShopItemType[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Form
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [effectsError, setEffectsError] = useState<string | null>(null);
  const [form, setForm] = useState<ShopItemForm>(EMPTY_FORM);

  const resetForm = () => {
    setForm(EMPTY_FORM);
    setEffectsError(null);
    setEditingId(null);
  };

  const applyTemplate = (itemType: string) => {
    const template = ITEM_TYPE_TEMPLATES[itemType];
    if (!template) return;
    setForm((prev) => ({
      ...prev,
      item_type: itemType,
      name: template.name,
      description: template.description,
      price_gems: template.price_gems,
      effectsText: JSON.stringify(template.effects, null, 2),
    }));
    setEffectsError(null);
  };

  const loadItems = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await listShopItems(true);
      setItems(res.data || []);
    } catch (err: any) {
      setError(err?.message || t.shop.loadFailed);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { void loadItems(); }, []);

  const handleEdit = (item: ShopItemType) => {
    setEditingId(item.id);
    setForm({
      name: item.name,
      description: item.description,
      item_type: item.item_type,
      price_gems: item.price_gems,
      is_available: item.is_available,
      stock_quantity: item.stock_quantity ?? undefined,
      icon_url: item.icon_url ?? "",
      effectsText: JSON.stringify(item.effects ?? {}, null, 2),
    });
    setEffectsError(null);
    setShowForm(true);
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();

    let effects: Record<string, unknown> | undefined;
    try {
      effects = form.effectsText.trim() ? JSON.parse(form.effectsText) : {};
    } catch {
      setEffectsError(t.shop.effectsInvalidJson);
      return;
    }
    setEffectsError(null);

    setSaving(true);
    setError(null);
    try {
      if (editingId) {
        await updateShopItem(editingId, {
          name: form.name,
          description: form.description,
          price_gems: form.price_gems,
          is_available: form.is_available,
          stock_quantity: form.stock_quantity ?? undefined,
          icon_url: form.icon_url || undefined,
          effects,
        });
      } else {
        await createShopItem({
          name: form.name,
          description: form.description,
          item_type: form.item_type,
          price_gems: form.price_gems,
          is_available: form.is_available,
          stock_quantity: form.stock_quantity,
          icon_url: form.icon_url || undefined,
          effects,
        });
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
    if (!confirm(t.shop.deleteConfirm)) return;
    try {
      await deleteShopItem(id);
      await loadItems();
    } catch (err: any) {
      setError(err?.message || t.common.deleteFailed);
    }
  };

  const handleToggle = async (item: ShopItemType) => {
    try {
      await updateShopItem(item.id, { is_available: !item.is_available });
      await loadItems();
    } catch (err: any) {
      setError(err?.message || t.shop.updateFailed);
    }
  };

  return (
    <div className="stack">
      <SectionHeader title={t.shop.title} description={`${items.length} ${t.shop.description}`} />

      {error && <div className="form-error">{error}</div>}

      <div className="panel" style={{ padding: "12px 16px" }}>
        <div style={{ display: "flex", justifyContent: "flex-end" }}>
          <button className="primary-button" onClick={() => { resetForm(); setShowForm(true); }}>
            {t.shop.createItem}
          </button>
        </div>
      </div>

      <div className="panel">
        {loading ? (
          <div className="loading">{t.common.loading}</div>
        ) : items.length === 0 ? (
          <EmptyState title={t.shop.noItems} description={t.shop.noItemsDesc} />
        ) : (
          <DataTable
            columns={[
              {
                header: t.shop.item,
                render: (row) => (
                  <div>
                    <div className="table-title">{row.name}</div>
                    <div className="table-sub">{row.description}</div>
                  </div>
                ),
              },
              {
                header: t.shop.type,
                render: (row) => <span className="table-meta">{row.item_type}</span>,
                align: "center",
              },
              {
                header: t.shop.price,
                render: (row) => <span className="table-meta">{row.price_gems} Gems</span>,
                align: "center",
              },
              {
                header: t.shop.stock,
                render: (row) => (
                  <span className="table-meta">
                    {row.stock_quantity === null || row.stock_quantity === undefined ? "∞" : row.stock_quantity}
                  </span>
                ),
                align: "center",
              },
              {
                header: t.common.status,
                render: (row) => (
                  <StatusPill
                    tone={row.is_available ? "success" : "danger"}
                    label={row.is_available ? t.shop.onSale : t.shop.hidden}
                  />
                ),
                align: "center",
              },
              {
                header: t.common.actions,
                render: (row) => (
                  <div className="table-actions">
                    <button
                      className="ghost-button small"
                      onClick={() => handleToggle(row)}
                      title={row.is_available ? t.shop.hide : t.shop.show}
                    >
                      {row.is_available ? t.shop.hide : t.shop.show}
                    </button>
                    <button className="ghost-button small" onClick={() => handleEdit(row)}>{t.common.edit}</button>
                    <button className="ghost-button small danger" onClick={() => handleDelete(row.id)}>{t.common.delete}</button>
                  </div>
                ),
                align: "right",
              },
            ]}
            rows={items}
          />
        )}
      </div>

      {/* Create/Edit Modal */}
      {showForm && (
        <div className="modal-overlay" onClick={() => setShowForm(false)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 560 }}>
            <h3>{editingId ? t.shop.editItem : t.shop.createNew}</h3>
            <form className="form" onSubmit={handleSave}>
              <div className="form-row">
                <label style={{ flex: 1 }}>
                  {t.shop.itemTypeRequired}
                  <select
                    value={form.item_type}
                    disabled={!!editingId}
                    onChange={(e) => setForm({ ...form, item_type: e.target.value })}
                  >
                    {ITEM_TYPES.map((it) => <option key={it} value={it}>{it}</option>)}
                  </select>
                </label>
                {!editingId && (
                  <button
                    type="button"
                    className="ghost-button"
                    style={{ alignSelf: "flex-end" }}
                    onClick={() => applyTemplate(form.item_type)}
                  >
                    {t.shop.useTemplate}
                  </button>
                )}
              </div>
              <label>
                {t.shop.nameRequired}
                <input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required />
              </label>
              <label>
                {t.shop.descriptionRequired}
                <textarea rows={2} value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} required />
              </label>
              <div className="form-row">
                <label>
                  {t.shop.priceRequired}
                  <input type="number" min={0} value={form.price_gems} onChange={(e) => setForm({ ...form, price_gems: Number(e.target.value) })} required />
                </label>
                <label>
                  {t.shop.stockQuantity}
                  <input
                    type="number"
                    min={0}
                    placeholder={t.shop.unlimitedPlaceholder}
                    value={form.stock_quantity ?? ""}
                    onChange={(e) => setForm({ ...form, stock_quantity: e.target.value ? Number(e.target.value) : undefined })}
                  />
                </label>
              </div>
              <label>
                {t.shop.iconUrl}
                <input
                  value={form.icon_url}
                  placeholder={t.shop.iconUrlPlaceholder}
                  onChange={(e) => setForm({ ...form, icon_url: e.target.value })}
                />
              </label>
              <label>
                {t.shop.effectsLabel}
                <textarea
                  rows={3}
                  style={{ fontFamily: "monospace" }}
                  value={form.effectsText}
                  onChange={(e) => { setForm({ ...form, effectsText: e.target.value }); setEffectsError(null); }}
                />
              </label>
              {effectsError ? (
                <div className="form-error">{effectsError}</div>
              ) : (
                <div className="table-sub">{t.shop.effectsHint}</div>
              )}
              <label style={{ display: "flex", alignItems: "center", gap: 8 }}>
                <input
                  type="checkbox"
                  checked={form.is_available}
                  onChange={(e) => setForm({ ...form, is_available: e.target.checked })}
                />
                {t.shop.onSale}
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
