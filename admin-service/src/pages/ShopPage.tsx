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

const ITEM_TYPES = ["streak_freeze", "double_xp", "hint_pack", "cosmetic", "power_up", "time_boost"];

export const ShopPage = () => {
  const [items, setItems] = useState<ShopItemType[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Form
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [form, setForm] = useState({
    name: "",
    description: "",
    item_type: "streak_freeze",
    price_gems: 50,
    is_available: true,
    stock_quantity: undefined as number | undefined,
  });

  const resetForm = () => {
    setForm({ name: "", description: "", item_type: "streak_freeze", price_gems: 50, is_available: true, stock_quantity: undefined });
    setEditingId(null);
  };

  const loadItems = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await listShopItems(true);
      setItems(res.data || []);
    } catch (err: any) {
      setError(err?.message || "Lỗi tải shop items");
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
    });
    setShowForm(true);
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
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
        });
      } else {
        await createShopItem(form);
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
    if (!confirm("Xóa item này?")) return;
    try {
      await deleteShopItem(id);
      await loadItems();
    } catch (err: any) {
      setError(err?.message || "Xóa thất bại");
    }
  };

  const handleToggle = async (item: ShopItemType) => {
    try {
      await updateShopItem(item.id, { is_available: !item.is_available });
      await loadItems();
    } catch (err: any) {
      setError(err?.message || "Cập nhật thất bại");
    }
  };

  return (
    <div className="stack">
      <SectionHeader title="Quản lý Shop" description={`${items.length} sản phẩm`} />

      {error && <div className="form-error">{error}</div>}

      <div className="panel" style={{ padding: "12px 16px" }}>
        <div style={{ display: "flex", justifyContent: "flex-end" }}>
          <button className="primary-button" onClick={() => { resetForm(); setShowForm(true); }}>
            + Thêm Item
          </button>
        </div>
      </div>

      <div className="panel">
        {loading ? (
          <div className="loading">Đang tải...</div>
        ) : items.length === 0 ? (
          <EmptyState title="Chưa có item" description="Tạo sản phẩm mới cho shop." />
        ) : (
          <DataTable
            columns={[
              {
                header: "Sản phẩm",
                render: (row) => (
                  <div>
                    <div className="table-title">{row.name}</div>
                    <div className="table-sub">{row.description}</div>
                  </div>
                ),
              },
              {
                header: "Loại",
                render: (row) => <span className="table-meta">{row.item_type}</span>,
                align: "center",
              },
              {
                header: "Giá",
                render: (row) => <span className="table-meta">{row.price_gems} 💎</span>,
                align: "center",
              },
              {
                header: "Kho",
                render: (row) => (
                  <span className="table-meta">
                    {row.stock_quantity === null || row.stock_quantity === undefined ? "∞" : row.stock_quantity}
                  </span>
                ),
                align: "center",
              },
              {
                header: "Trạng thái",
                render: (row) => (
                  <StatusPill
                    tone={row.is_available ? "success" : "danger"}
                    label={row.is_available ? "Đang bán" : "Ẩn"}
                  />
                ),
                align: "center",
              },
              {
                header: "Hành động",
                render: (row) => (
                  <div className="table-actions">
                    <button
                      className="ghost-button small"
                      onClick={() => handleToggle(row)}
                      title={row.is_available ? "Ẩn" : "Hiện"}
                    >
                      {row.is_available ? "Ẩn" : "Hiện"}
                    </button>
                    <button className="ghost-button small" onClick={() => handleEdit(row)}>Sửa</button>
                    <button className="ghost-button small danger" onClick={() => handleDelete(row.id)}>Xóa</button>
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
          <div className="modal-content" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 520 }}>
            <h3>{editingId ? "Chỉnh sửa Item" : "Tạo Item mới"}</h3>
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
                  Loại item *
                  <select value={form.item_type} onChange={(e) => setForm({ ...form, item_type: e.target.value })}>
                    {ITEM_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
                  </select>
                </label>
                <label>
                  Giá (Gems) *
                  <input type="number" min={0} value={form.price_gems} onChange={(e) => setForm({ ...form, price_gems: Number(e.target.value) })} required />
                </label>
              </div>
              <div className="form-row">
                <label>
                  Số lượng kho
                  <input
                    type="number"
                    min={0}
                    placeholder="Để trống = vô hạn"
                    value={form.stock_quantity ?? ""}
                    onChange={(e) => setForm({ ...form, stock_quantity: e.target.value ? Number(e.target.value) : undefined })}
                  />
                </label>
                <label style={{ display: "flex", alignItems: "center", gap: 8, paddingTop: 24 }}>
                  <input
                    type="checkbox"
                    checked={form.is_available}
                    onChange={(e) => setForm({ ...form, is_available: e.target.checked })}
                  />
                  Đang bán
                </label>
              </div>
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
