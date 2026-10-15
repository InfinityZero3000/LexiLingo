import React, { useEffect, useState } from "react";
import { DataTable } from "../components/DataTable";
import { SectionHeader } from "../components/SectionHeader";
import { EmptyState } from "../components/EmptyState";
import { StatusPill } from "../components/StatusPill";
import {
  listBanners,
  createBanner,
  updateBanner,
  deleteBanner,
  type BannerType,
  type BannerPosition,
} from "../lib/adminApi";
import { useI18n } from "../lib/i18n";

const POSITIONS: BannerPosition[] = ["hero", "sidebar", "interstitial"];
const CEFR_LEVELS = ["A1", "A2", "B1", "B2", "C1", "C2"];

type BannerForm = {
  title: string;
  description: string;
  image_url: string;
  link_url: string;
  position: BannerPosition;
  priority: number;
  is_active: boolean;
  start_at: string;
  end_at: string;
  target_min_level: string;
  target_max_level: string;
  target_language: string;
};

const EMPTY_FORM: BannerForm = {
  title: "",
  description: "",
  image_url: "",
  link_url: "",
  position: "hero",
  priority: 0,
  is_active: true,
  start_at: "",
  end_at: "",
  target_min_level: "",
  target_max_level: "",
  target_language: "",
};

// Backend stores UTC ISO; <input type="datetime-local"> shows and edits the
// admin's *local* wall-clock time, so the conversion must go through the
// browser's local timezone rather than slicing the UTC string directly —
// slicing left the field showing the UTC hour, and saving it back then
// re-interpreted that UTC hour as local, shifting the schedule every edit.
const toLocalInputValue = (iso?: string | null) => {
  if (!iso) return "";
  const date = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, "0");
  return (
    `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}` +
    `T${pad(date.getHours())}:${pad(date.getMinutes())}`
  );
};
const toIsoOrUndefined = (local: string) => (local ? new Date(local).toISOString() : undefined);

export const AdsPage = () => {
  const { t } = useI18n();
  const [banners, setBanners] = useState<BannerType[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [form, setForm] = useState<BannerForm>(EMPTY_FORM);

  const resetForm = () => {
    setForm(EMPTY_FORM);
    setEditingId(null);
  };

  const loadBanners = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await listBanners();
      setBanners(res.data || []);
    } catch (err: any) {
      setError(err?.message || t.ads.loadFailed);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { void loadBanners(); }, []);

  const handleEdit = (banner: BannerType) => {
    setEditingId(banner.id);
    setForm({
      title: banner.title,
      description: banner.description || "",
      image_url: banner.image_url,
      link_url: banner.link_url || "",
      position: banner.position,
      priority: banner.priority,
      is_active: banner.is_active,
      start_at: toLocalInputValue(banner.start_at),
      end_at: toLocalInputValue(banner.end_at),
      target_min_level: banner.target_min_level || "",
      target_max_level: banner.target_max_level || "",
      target_language: banner.target_language || "",
    });
    setShowForm(true);
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setError(null);
    try {
      const payload: Omit<BannerType, "id" | "created_at" | "updated_at"> = {
        title: form.title,
        description: form.description || undefined,
        image_url: form.image_url,
        link_url: form.link_url || undefined,
        position: form.position,
        priority: form.priority,
        is_active: form.is_active,
        start_at: toIsoOrUndefined(form.start_at),
        end_at: toIsoOrUndefined(form.end_at),
        target_min_level: form.target_min_level || undefined,
        target_max_level: form.target_max_level || undefined,
        target_language: form.target_language || undefined,
      };
      if (editingId) {
        await updateBanner(editingId, payload);
      } else {
        await createBanner(payload);
      }
      resetForm();
      setShowForm(false);
      await loadBanners();
    } catch (err: any) {
      setError(err?.message || t.common.saveFailed);
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async (id: string) => {
    if (!confirm(t.ads.deleteConfirm)) return;
    try {
      await deleteBanner(id);
      await loadBanners();
    } catch (err: any) {
      setError(err?.message || t.common.deleteFailed);
    }
  };

  const handleToggle = async (banner: BannerType) => {
    try {
      await updateBanner(banner.id, { is_active: !banner.is_active });
      await loadBanners();
    } catch (err: any) {
      setError(err?.message || t.common.saveFailed);
    }
  };

  return (
    <div className="stack">
      <SectionHeader title={t.ads.title} description={`${banners.length} ${t.ads.description}`} />

      {error && <div className="form-error">{error}</div>}

      <div className="panel" style={{ padding: "12px 16px" }}>
        <div style={{ display: "flex", justifyContent: "flex-end" }}>
          <button className="primary-button" onClick={() => { resetForm(); setShowForm(true); }}>
            {t.ads.createBanner}
          </button>
        </div>
      </div>

      <div className="panel">
        {loading ? (
          <div className="loading">{t.common.loading}</div>
        ) : banners.length === 0 ? (
          <EmptyState title={t.ads.noBanners} description={t.ads.noBannersDesc} />
        ) : (
          <DataTable
            columns={[
              {
                header: t.ads.banner,
                render: (row) => (
                  <div>
                    <div className="table-title">{row.title}</div>
                    <div className="table-sub">{row.description}</div>
                  </div>
                ),
              },
              {
                header: t.ads.position,
                render: (row) => <span className="table-meta">{row.position}</span>,
                align: "center",
              },
              {
                header: t.ads.priorityLabel,
                render: (row) => <span className="table-meta">{row.priority}</span>,
                align: "center",
              },
              {
                header: t.ads.startDate,
                render: (row) => (
                  <span className="table-meta">
                    {row.start_at ? new Date(row.start_at).toLocaleDateString() : "—"}
                  </span>
                ),
                align: "center",
              },
              {
                header: t.ads.endDate,
                render: (row) => (
                  <span className="table-meta">
                    {row.end_at ? new Date(row.end_at).toLocaleDateString() : "—"}
                  </span>
                ),
                align: "center",
              },
              {
                header: t.common.status,
                render: (row) => (
                  <StatusPill
                    tone={row.is_active ? "success" : "danger"}
                    label={row.is_active ? t.common.active : t.common.inactive}
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
                      title={row.is_active ? t.ads.hide : t.ads.show}
                    >
                      {row.is_active ? t.ads.hide : t.ads.show}
                    </button>
                    <button className="ghost-button small" onClick={() => handleEdit(row)}>{t.common.edit}</button>
                    <button className="ghost-button small danger" onClick={() => handleDelete(row.id)}>{t.common.delete}</button>
                  </div>
                ),
                align: "right",
              },
            ]}
            rows={banners}
          />
        )}
      </div>

      {showForm && (
        <div className="modal-overlay" onClick={() => setShowForm(false)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 560 }}>
            <h3>{editingId ? t.ads.editBanner : t.ads.createNew}</h3>
            <form className="form" onSubmit={handleSave}>
              <label>
                {t.ads.titleRequired}
                <input value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} required />
              </label>
              <label>
                {t.common.description}
                <textarea rows={2} value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} />
              </label>
              <label>
                {t.ads.imageUrlRequired}
                <input value={form.image_url} onChange={(e) => setForm({ ...form, image_url: e.target.value })} required />
              </label>
              <label>
                {t.ads.targetUrl}
                <input value={form.link_url} onChange={(e) => setForm({ ...form, link_url: e.target.value })} />
              </label>
              <div className="form-row">
                <label style={{ flex: 1 }}>
                  {t.ads.position}
                  <select value={form.position} onChange={(e) => setForm({ ...form, position: e.target.value as BannerPosition })}>
                    {POSITIONS.map((p) => <option key={p} value={p}>{p}</option>)}
                  </select>
                </label>
                <label>
                  {t.ads.priorityLabel}
                  <input type="number" value={form.priority} onChange={(e) => setForm({ ...form, priority: Number(e.target.value) })} />
                </label>
              </div>
              <div className="form-row">
                <label style={{ flex: 1 }}>
                  {t.ads.startDate}
                  <input type="datetime-local" value={form.start_at} onChange={(e) => setForm({ ...form, start_at: e.target.value })} />
                </label>
                <label style={{ flex: 1 }}>
                  {t.ads.endDate}
                  <input type="datetime-local" value={form.end_at} onChange={(e) => setForm({ ...form, end_at: e.target.value })} />
                </label>
              </div>
              <div className="form-row">
                <label style={{ flex: 1 }}>
                  {t.ads.targetMinLevel}
                  <select value={form.target_min_level} onChange={(e) => setForm({ ...form, target_min_level: e.target.value })}>
                    <option value="">{t.ads.anyLevelPlaceholder}</option>
                    {CEFR_LEVELS.map((lvl) => <option key={lvl} value={lvl}>{lvl}</option>)}
                  </select>
                </label>
                <label style={{ flex: 1 }}>
                  {t.ads.targetMaxLevel}
                  <select value={form.target_max_level} onChange={(e) => setForm({ ...form, target_max_level: e.target.value })}>
                    <option value="">{t.ads.anyLevelPlaceholder}</option>
                    {CEFR_LEVELS.map((lvl) => <option key={lvl} value={lvl}>{lvl}</option>)}
                  </select>
                </label>
              </div>
              <label>
                {t.ads.targetLanguage}
                <input
                  value={form.target_language}
                  placeholder={t.ads.anyLanguagePlaceholder}
                  onChange={(e) => setForm({ ...form, target_language: e.target.value })}
                />
              </label>
              <label style={{ display: "flex", alignItems: "center", gap: 8 }}>
                <input
                  type="checkbox"
                  checked={form.is_active}
                  onChange={(e) => setForm({ ...form, is_active: e.target.checked })}
                />
                {t.common.active}
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
