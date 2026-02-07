import React, { useEffect, useState, useRef } from "react";
import { DataTable } from "../components/DataTable";
import { SectionHeader } from "../components/SectionHeader";
import { EmptyState } from "../components/EmptyState";
import { StatusPill } from "../components/StatusPill";
import {
  listVocabulary,
  createVocabulary,
  updateVocabulary,
  deleteVocabulary,
  bulkImportVocabulary,
  type VocabItem,
} from "../lib/adminApi";
import { useI18n } from "../lib/i18n";

const POS_OPTIONS = ["noun", "verb", "adjective", "adverb", "pronoun", "preposition", "conjunction", "interjection"];
const LEVEL_OPTIONS = ["A1", "A2", "B1", "B2", "C1", "C2"];

const levelColor: Record<string, "info" | "success" | "warning" | "danger"> = {
  A1: "info",
  A2: "info",
  B1: "success",
  B2: "success",
  C1: "warning",
  C2: "danger",
};

export const VocabularyPage = () => {
  const { t } = useI18n();
  const [items, setItems] = useState<VocabItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState("");

  // Form
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [form, setForm] = useState({
    word: "",
    definition: "",
    translation: "",
    part_of_speech: "noun",
    pronunciation: "",
    difficulty_level: "A1",
  });

  // Bulk import
  const [importResult, setImportResult] = useState<{ created: number; skipped: number; errors: string[] } | null>(null);
  const [importing, setImporting] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);

  const resetForm = () => {
    setForm({ word: "", definition: "", translation: "", part_of_speech: "noun", pronunciation: "", difficulty_level: "A1" });
    setEditingId(null);
  };

  const loadItems = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await listVocabulary(200, 0);
      setItems(res.data || []);
    } catch (err: any) {
      setError(err?.message || t.vocabulary.loadFailed);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { void loadItems(); }, []);

  const handleEdit = (item: VocabItem) => {
    setEditingId(item.id);
    setForm({
      word: item.word,
      definition: item.definition || "",
      translation: typeof item.translation === "object" ? (item.translation?.vi || "") : String(item.translation || ""),
      part_of_speech: item.part_of_speech || "noun",
      pronunciation: item.pronunciation || "",
      difficulty_level: item.difficulty_level || "A1",
    });
    setShowForm(true);
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setError(null);
    try {
      if (editingId) {
        await updateVocabulary(editingId, form);
      } else {
        await createVocabulary(form);
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
    if (!confirm(t.vocabulary.deleteWord)) return;
    try {
      await deleteVocabulary(id);
      await loadItems();
    } catch (err: any) {
      setError(err?.message || t.common.deleteFailed);
    }
  };

  const handleBulkImport = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setImporting(true);
    setError(null);
    setImportResult(null);
    try {
      const res = await bulkImportVocabulary(file);
      setImportResult(res.data || null);
      await loadItems();
    } catch (err: any) {
      setError(err?.message || "Import thất bại");
    } finally {
      setImporting(false);
      if (fileRef.current) fileRef.current.value = "";
    }
  };

  // Client-side search filter
  const filtered = search
    ? items.filter(
        (v) =>
          v.word.toLowerCase().includes(search.toLowerCase()) ||
          (v.definition || "").toLowerCase().includes(search.toLowerCase())
      )
    : items;

  return (
    <div className="stack">
      <SectionHeader title={t.vocabulary.title} description={`${items.length} ${t.vocabulary.description}`} />

      {error && <div className="form-error">{error}</div>}

      {importResult && (
        <div className="panel" style={{ padding: "12px 16px", background: "#f0fdf4" }}>
          <strong>Import hoàn tất:</strong> {importResult.created} tạo mới, {importResult.skipped} bỏ qua
          {importResult.errors.length > 0 && (
            <ul style={{ margin: "4px 0 0", paddingLeft: 20, color: "#b91c1c" }}>
              {importResult.errors.slice(0, 5).map((e, i) => <li key={i}>{e}</li>)}
            </ul>
          )}
        </div>
      )}

      <div className="panel" style={{ padding: "12px 16px" }}>
        <div style={{ display: "flex", gap: 12, alignItems: "center", flexWrap: "wrap" }}>
          <input
            className="form-input"
            placeholder={t.vocabulary.searchPlaceholder}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            style={{ flex: 1, minWidth: 200 }}
          />
          <input type="file" accept=".csv" ref={fileRef} onChange={handleBulkImport} style={{ display: "none" }} />
          <button className="ghost-button" onClick={() => fileRef.current?.click()} disabled={importing}>
            {importing ? "Đang import..." : "Import CSV"}
          </button>
          <button className="primary-button" onClick={() => { resetForm(); setShowForm(true); }}>
            {t.vocabulary.createWord}
          </button>
        </div>
      </div>

      <div className="panel">
        {loading ? (
          <div className="loading">{t.common.loading}</div>
        ) : filtered.length === 0 ? (
          <EmptyState title={t.vocabulary.noWords} description={t.vocabulary.noWordsDesc} />
        ) : (
          <DataTable
            columns={[
              {
                header: t.vocabulary.word,
                render: (row) => (
                  <div>
                    <div className="table-title">{row.word}</div>
                    <div className="table-sub">{row.pronunciation || "—"}</div>
                  </div>
                ),
              },
              {
                header: "Định nghĩa",
                render: (row) => <span>{row.definition || "—"}</span>,
              },
              {
                header: "Dịch nghĩa",
                render: (row) => {
                  if (!row.translation) return "—";
                  if (typeof row.translation === "string") return row.translation;
                  return row.translation.vi || "—";
                },
              },
              {
                header: "Loại từ",
                render: (row) => <span className="table-meta">{row.part_of_speech || "—"}</span>,
                align: "center",
              },
              {
                header: "Level",
                render: (row) => (
                  <StatusPill
                    tone={levelColor[row.difficulty_level] || "info"}
                    label={row.difficulty_level || "A1"}
                  />
                ),
                align: "center",
              },
              {
                header: t.common.actions,
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
          <div className="modal-content" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 520 }}>
            <h3>{editingId ? t.vocabulary.editWord : t.vocabulary.createNew}</h3>
            <form className="form" onSubmit={handleSave}>
              <label>
                Từ *
                <input value={form.word} onChange={(e) => setForm({ ...form, word: e.target.value })} required />
              </label>
              <label>
                Định nghĩa *
                <textarea rows={2} value={form.definition} onChange={(e) => setForm({ ...form, definition: e.target.value })} required />
              </label>
              <label>
                Dịch nghĩa (Tiếng Việt)
                <input value={form.translation} onChange={(e) => setForm({ ...form, translation: e.target.value })} />
              </label>
              <label>
                Phát âm
                <input value={form.pronunciation} onChange={(e) => setForm({ ...form, pronunciation: e.target.value })} placeholder="/prəˌnʌnsiˈeɪʃn/" />
              </label>
              <div className="form-row">
                <label>
                  Loại từ
                  <select value={form.part_of_speech} onChange={(e) => setForm({ ...form, part_of_speech: e.target.value })}>
                    {POS_OPTIONS.map((p) => <option key={p} value={p}>{p}</option>)}
                  </select>
                </label>
                <label>
                  Cấp độ
                  <select value={form.difficulty_level} onChange={(e) => setForm({ ...form, difficulty_level: e.target.value })}>
                    {LEVEL_OPTIONS.map((l) => <option key={l} value={l}>{l}</option>)}
                  </select>
                </label>
              </div>
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
