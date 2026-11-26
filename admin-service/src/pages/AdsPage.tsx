import { useConfirm } from "../components/ConfirmDialog";
import { Dialog } from "../components/Dialog";
import React, { useEffect, useRef, useState } from "react";
import { DataTable } from "../components/DataTable";
import { SectionHeader } from "../components/SectionHeader";
import { EmptyState } from "../components/EmptyState";
import { StatCard } from "../components/StatCard";
import { StatusPill } from "../components/StatusPill";
import {
  listBanners,
  createBanner,
  updateBanner,
  deleteBanner,
  uploadBannerImage,
  type BannerType,
  type BannerPosition,
} from "../lib/adminApi";
import { useI18n } from "../lib/i18n";

const IMAGE_TYPES = ["image/png", "image/jpeg", "image/webp"];
const MAX_IMAGE_BYTES = 2 * 1024 * 1024;
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
// null, not undefined: JSON drops undefined, and an update then keeps the old value.
const toIsoOrNull = (local: string) => (local ? new Date(local).toISOString() : null);

export type BannerStatus = "running" | "scheduled" | "expired" | "off";

export const bannerStatus = (
  banner: Pick<BannerType, "is_active" | "start_at" | "end_at">,
  now: Date,
): BannerStatus => {
  if (!banner.is_active) return "off";
  if (banner.end_at && new Date(banner.end_at) < now) return "expired";
  if (banner.start_at && new Date(banner.start_at) > now) return "scheduled";
  return "running";
};

const STATUS_TONE = { running: "success", scheduled: "info", expired: "warning", off: "neutral" } as const;
const STATUS_ORDER: Record<BannerStatus, number> = { running: 0, scheduled: 1, expired: 2, off: 3 };

const toLocalInput = (d: Date) => toLocalInputValue(d.toISOString());

const toForm = (banner: BannerType): BannerForm => ({
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

const BannerPreview = ({ url, title, description }: { url: string; title: string; description: string }) => {
  const { t } = useI18n();
  const [failed, setFailed] = useState(false);
  useEffect(() => setFailed(false), [url]);
  return (
    <div className="banner-preview" role="group" aria-label={t.ads.preview}>
      {url && !failed ? (
        <img src={url} alt={title || t.ads.preview} onError={() => setFailed(true)} />
      ) : (
        <div className="banner-preview-empty">{url ? t.ads.previewFailed : t.ads.previewEmpty}</div>
      )}
      <div className="banner-preview-text">
        <div className="table-title">{title || t.ads.titleRequired}</div>
        {description && <div className="table-sub">{description}</div>}
      </div>
    </div>
  );
};

export const AdsPage = () => {
  const { t } = useI18n();
  const confirm = useConfirm();
  const [banners, setBanners] = useState<BannerType[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [form, setForm] = useState<BannerForm>(EMPTY_FORM);
  const [uploading, setUploading] = useState(false);
  const [uploadError, setUploadError] = useState<string | null>(null);
  const [dragging, setDragging] = useState(false);
  // Only hero is shown by the app; an existing banner on another position stays selectable.
  const [legacyPosition, setLegacyPosition] = useState<BannerPosition | null>(null);

  // Bumped whenever the form is reopened or closed, so a late upload cannot land in a different banner.
  const uploadSeq = useRef(0);
  const invalidateUpload = () => {
    uploadSeq.current += 1;
    setUploading(false);
  };

  const closeForm = () => {
    invalidateUpload();
    setShowForm(false);
  };

  const resetForm = () => {
    invalidateUpload();
    setForm(EMPTY_FORM);
    setEditingId(null);
    setLegacyPosition(null);
    setUploadError(null);
  };

  const openWith = (next: BannerForm, id: string | null) => {
    invalidateUpload();
    setEditingId(id);
    setForm(next);
    setLegacyPosition(next.position === "hero" ? null : next.position);
    setUploadError(null);
    setShowForm(true);
  };

  const handleEdit = (banner: BannerType) => openWith(toForm(banner), banner.id);

  const handleDuplicate = (banner: BannerType) =>
    openWith({ ...toForm(banner), title: `${banner.title}${t.ads.copySuffix}`, is_active: false }, null);

  const applyPreset = (days: number | "month" | "now") => {
    const now = new Date();
    const start_at = toLocalInput(now);
    if (days === "now") return setForm((f) => ({ ...f, start_at }));
    const end = days === "month"
      ? new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59)
      : new Date(now.getFullYear(), now.getMonth(), now.getDate() + days, now.getHours(), now.getMinutes());
    setForm((f) => ({ ...f, start_at, end_at: toLocalInput(end) }));
  };

  const handleFile = async (file?: File) => {
    if (!file) return;
    if (!IMAGE_TYPES.includes(file.type)) return setUploadError(t.ads.uploadBadType);
    if (file.size > MAX_IMAGE_BYTES) return setUploadError(t.ads.uploadTooLarge);
    setUploadError(null);
    const seq = uploadSeq.current;
    setUploading(true);
    try {
      const res = await uploadBannerImage(file);
      const url = res.data?.url;
      if (!url) throw new Error(t.ads.uploadFailed);
      if (seq === uploadSeq.current) setForm((f) => ({ ...f, image_url: url }));
    } catch (err: any) {
      if (seq === uploadSeq.current) setUploadError(err?.message || t.ads.uploadFailed);
    } finally {
      if (seq === uploadSeq.current) setUploading(false);
    }
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

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setError(null);
    try {
      const payload: Omit<BannerType, "id" | "created_at" | "updated_at"> = {
        title: form.title,
        description: form.description || null,
        image_url: form.image_url,
        link_url: form.link_url || null,
        position: form.position,
        priority: form.priority,
        is_active: form.is_active,
        start_at: toIsoOrNull(form.start_at),
        end_at: toIsoOrNull(form.end_at),
        target_min_level: form.target_min_level || null,
        target_max_level: form.target_max_level || null,
        target_language: form.target_language || null,
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
    if (!(await confirm({ message: t.ads.deleteConfirm, confirmLabel: t.common.delete, danger: true }))) return;
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

  const now = new Date();
  const positionOptions: BannerPosition[] = legacyPosition ? ["hero", legacyPosition] : ["hero"];
  const runningCount = banners.filter((b) => bannerStatus(b, now) === "running").length;
  const scheduledCount = banners.filter((b) => bannerStatus(b, now) === "scheduled").length;
  const offCount = banners.filter((b) => {
    const s = bannerStatus(b, now);
    return s === "off" || s === "expired";
  }).length;

  return (
    <div className="stack">
      <SectionHeader title={t.ads.title} description={`${banners.length} ${t.ads.description}`} />

      {error && <div className="form-error">{error}</div>}

      <div className="card-grid">
        <StatCard label={t.ads.title} value={banners.length.toLocaleString()} variant="blue" />
        <StatCard label={t.ads.status.running} value={runningCount.toLocaleString()} accent="teal" />
        <StatCard label={t.ads.status.scheduled} value={scheduledCount.toLocaleString()} accent="ink" />
        <StatCard label={t.ads.status.off} value={offCount.toLocaleString()} accent="ink" />
      </div>

      <div className="panel" style={{ padding: "12px 16px", borderRadius: 20 }}>
        <div style={{ display: "flex", justifyContent: "flex-end" }}>
          <button
            className="primary-button"
            style={{ borderRadius: 9999 }}
            onClick={() => { resetForm(); setShowForm(true); }}
          >
            {t.ads.createBanner}
          </button>
        </div>
      </div>

      <div className="panel" style={{ borderRadius: 20 }}>
        {loading ? (
          <div className="loading">{t.common.loading}</div>
        ) : banners.length === 0 ? (
          <EmptyState title={t.ads.noBanners} description={t.ads.noBannersDesc} />
        ) : (
          <DataTable
            columns={[
              {
                header: t.ads.banner,
                sortValue: (row) => row.title,
                render: (row) => (
                  <div>
                    <div className="table-title">{row.title}</div>
                    <div className="table-sub">{row.description}</div>
                  </div>
                ),
              },
              {
                header: t.ads.position,
                sortValue: (row) => row.position,
                render: (row) => (
                  <span className="table-meta">
                    {row.position}
                    {row.position !== "hero" && (
                      <>
                        {" "}
                        <StatusPill tone="warning" label={t.ads.notShown} />
                      </>
                    )}
                  </span>
                ),
                align: "center",
              },
              {
                header: t.ads.priorityLabel,
                sortValue: (row) => row.priority,
                render: (row) => (
                  <span
                    className="table-meta"
                    style={{
                      background: "var(--panel-soft-2, #f1f5f9)",
                      borderRadius: 9999,
                      padding: "3px 10px",
                      display: "inline-block",
                    }}
                  >
                    {row.priority}
                  </span>
                ),
                align: "center",
              },
              {
                header: t.ads.startDate,
                sortValue: (row) => row.start_at,
                render: (row) => (
                  <span className="table-meta">
                    {row.start_at ? new Date(row.start_at).toLocaleDateString() : "—"}
                  </span>
                ),
                align: "center",
              },
              {
                header: t.ads.endDate,
                sortValue: (row) => row.end_at,
                render: (row) => (
                  <span className="table-meta">
                    {row.end_at ? new Date(row.end_at).toLocaleDateString() : "—"}
                  </span>
                ),
                align: "center",
              },
              {
                header: t.common.status,
                sortValue: (row) => STATUS_ORDER[bannerStatus(row, now)],
                render: (row) => {
                  const status = bannerStatus(row, now);
                  return <StatusPill tone={STATUS_TONE[status]} label={t.ads.status[status]} />;
                },
                align: "center",
              },
              {
                header: t.common.actions,
                render: (row) => (
                  <div className="table-actions">
                    <button
                      className="ghost-button small"
                      style={{ borderRadius: 9999 }}
                      onClick={() => handleToggle(row)}
                      title={row.is_active ? t.ads.hide : t.ads.show}
                    >
                      {row.is_active ? t.ads.hide : t.ads.show}
                    </button>
                    <button className="ghost-button small" style={{ borderRadius: 9999 }} onClick={() => handleEdit(row)}>
                      {t.common.edit}
                    </button>
                    <button className="ghost-button small" style={{ borderRadius: 9999 }} onClick={() => handleDuplicate(row)}>
                      {t.ads.duplicate}
                    </button>
                    <button className="ghost-button small danger" style={{ borderRadius: 9999 }} onClick={() => handleDelete(row.id)}>
                      {t.common.delete}
                    </button>
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
        <Dialog onClose={closeForm} maxWidth={560}>
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
            <div
              className={`banner-drop${dragging ? " dragging" : ""}`}
              onDragOver={(e) => { e.preventDefault(); setDragging(true); }}
              onDragLeave={() => setDragging(false)}
              onDrop={(e) => { e.preventDefault(); setDragging(false); void handleFile(e.dataTransfer.files?.[0]); }}
            >
              <label>
                {t.ads.imageUrlRequired}
                <input value={form.image_url} onChange={(e) => setForm({ ...form, image_url: e.target.value })} required />
              </label>
              <label>
                {t.ads.uploadImage}
                <input
                  type="file"
                  accept={IMAGE_TYPES.join(",")}
                  disabled={uploading}
                  onChange={(e) => { void handleFile(e.target.files?.[0]); e.target.value = ""; }}
                />
              </label>
              <p className="form-hint">{uploading ? t.ads.uploading : t.ads.uploadHint}</p>
              {uploadError && <div className="form-error" role="alert">{uploadError}</div>}
            </div>
            <BannerPreview url={form.image_url} title={form.title} description={form.description} />
            <label>
              {t.ads.targetUrl}
              <input value={form.link_url} onChange={(e) => setForm({ ...form, link_url: e.target.value })} />
            </label>
            <div className="form-row">
              <label style={{ flex: 1 }}>
                {t.ads.position}
                <select value={form.position} onChange={(e) => setForm({ ...form, position: e.target.value as BannerPosition })}>
                  {positionOptions.map((p) => <option key={p} value={p}>{p}</option>)}
                </select>
              </label>
              <label>
                {t.ads.priorityLabel}
                <input type="number" value={form.priority} onChange={(e) => setForm({ ...form, priority: Number(e.target.value) })} />
              </label>
            </div>
            {form.position !== "hero" && <div className="form-error" role="alert">{t.ads.positionNotShown}</div>}
            <div className="table-actions">
              <button className="ghost-button small" type="button" onClick={() => applyPreset("now")}>{t.ads.presetNow}</button>
              <button className="ghost-button small" type="button" onClick={() => applyPreset(7)}>{t.ads.preset7}</button>
              <button className="ghost-button small" type="button" onClick={() => applyPreset(30)}>{t.ads.preset30}</button>
              <button className="ghost-button small" type="button" onClick={() => applyPreset("month")}>{t.ads.presetMonth}</button>
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
            <div className="table-actions">
              <button className="ghost-button" type="button" style={{ borderRadius: 9999 }} onClick={closeForm}>
                {t.common.cancel}
              </button>
              <button className="primary-button" type="submit" style={{ borderRadius: 9999 }} disabled={saving || uploading}>
                {saving ? t.common.saving : editingId ? t.common.update : t.common.create}
              </button>
            </div>
          </form>
        </Dialog>
      )}
    </div>
  );
};
