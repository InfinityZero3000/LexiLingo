import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { SectionHeader } from "../components/SectionHeader";
import { DataTable, Column } from "../components/DataTable";
import { Dialog } from "../components/Dialog";
import { EmptyState } from "../components/EmptyState";
import { StatusPill } from "../components/StatusPill";
import { TableSkeleton } from "../components/Skeleton";
import { useConfirm } from "../components/ConfirmDialog";
import {
  CategoryInput, CourseCategory, createCategory, hideCategory, listCategories, updateCategory,
} from "../lib/categoriesApi";
import { useI18n } from "../lib/i18n";

const slugify = (text: string) =>
  text
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/đ/gi, "d")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");

const EMPTY: CategoryInput = {
  name: "", slug: "", description: "", icon: "", color: "#6366f1", order_index: 0, is_active: true,
};

const messageOf = (err: unknown, fallback: string) => (err instanceof Error && err.message ? err.message : fallback);

export const CategoriesPage = () => {
  const { t } = useI18n();
  const confirm = useConfirm();
  const queryClient = useQueryClient();
  const [editing, setEditing] = useState<CourseCategory | "new" | null>(null);
  const [form, setForm] = useState<CategoryInput>(EMPTY);
  const [slugTouched, setSlugTouched] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const categories = useQuery({ queryKey: ["admin-categories"], queryFn: listCategories });
  const refresh = () => queryClient.invalidateQueries({ queryKey: ["admin-categories"] });

  const save = useMutation({
    mutationFn: (input: CategoryInput) =>
      editing && editing !== "new" ? updateCategory(editing.id, input) : createCategory(input),
    onSuccess: () => {
      setEditing(null);
      setFormError(null);
      refresh();
    },
    onError: (err) => setFormError(messageOf(err, t.common.saveFailed)),
  });
  const hide = useMutation({
    mutationFn: (id: string) => hideCategory(id),
    onMutate: () => setError(null),
    onSuccess: refresh,
    onError: (err) => setError(messageOf(err, t.common.deleteFailed)),
  });
  const show = useMutation({
    mutationFn: (id: string) => updateCategory(id, { is_active: true }),
    onMutate: () => setError(null),
    onSuccess: refresh,
    onError: (err) => setError(messageOf(err, t.common.saveFailed)),
  });

  const open = (category: CourseCategory | "new") => {
    setFormError(null);
    setSlugTouched(category !== "new");
    setForm(
      category === "new"
        ? { ...EMPTY, order_index: (categories.data?.length ?? 0) + 1 }
        : {
            name: category.name, slug: category.slug, description: category.description ?? "",
            icon: category.icon ?? "", color: category.color ?? "#6366f1",
            order_index: category.order_index, is_active: category.is_active,
          },
    );
    setEditing(category);
  };

  const askHide = async (category: CourseCategory) => {
    const ok = await confirm({
      title: t.categoriesPage.hideTitle,
      message: t.categoriesPage.hideMessage.replace("{name}", category.name),
      confirmLabel: t.categoriesPage.hide,
      danger: true,
    });
    if (ok) hide.mutate(category.id);
  };

  const rows = [...(categories.data ?? [])].sort((a, b) => a.order_index - b.order_index);

  const columns: Column<CourseCategory>[] = [
    { header: t.categoriesPage.order, align: "center", sortValue: (c) => c.order_index, render: (c) => c.order_index },
    {
      header: t.categoriesPage.category,
      sortValue: (c) => c.name,
      render: (c) => (
        <div className="cluster">
          {c.color && <span aria-hidden="true" className="color-dot" style={{ background: c.color }} />}
          <div>
            <div className="table-title">{c.icon ? `${c.icon} ` : ""}{c.name}</div>
            <div className="table-sub mono">{c.slug}</div>
          </div>
        </div>
      ),
    },
    { header: t.categoriesPage.courses, align: "center", sortValue: (c) => c.course_count, render: (c) => c.course_count },
    {
      header: t.common.status,
      align: "center",
      render: (c) => <StatusPill tone={c.is_active ? "success" : "neutral"} label={c.is_active ? t.categoriesPage.visible : t.categoriesPage.hidden} />,
    },
    {
      header: t.common.actions,
      align: "right",
      render: (c) => (
        <div className="table-actions">
          <button className="ghost-button small" onClick={() => open(c)}>{t.common.edit}</button>
          {c.is_active ? (
            <button className="ghost-button small danger" onClick={() => askHide(c)} disabled={hide.isPending}>{t.categoriesPage.hide}</button>
          ) : (
            <button className="ghost-button small" onClick={() => show.mutate(c.id)} disabled={show.isPending}>{t.categoriesPage.show}</button>
          )}
        </div>
      ),
    },
  ];

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    save.mutate({
      ...form,
      name: form.name.trim(),
      slug: form.slug.trim(),
      description: form.description?.trim() || null,
      icon: form.icon?.trim() || null,
    });
  };

  return (
    <div className="stack">
      <SectionHeader
        title={t.categoriesPage.title}
        description={t.categoriesPage.description}
        action={<button className="primary-button" onClick={() => open("new")}>{t.categoriesPage.create}</button>}
      />

      {(error || categories.error) && (
        <div className="form-error" role="alert">{error ?? messageOf(categories.error, t.categoriesPage.loadFailed)}</div>
      )}

      <div className="panel">
        {categories.isLoading ? (
          <TableSkeleton rows={5} cols={5} />
        ) : rows.length === 0 ? (
          <EmptyState
            title={t.categoriesPage.emptyTitle}
            description={t.categoriesPage.emptyDescription}
            action={<button className="primary-button" onClick={() => open("new")}>{t.categoriesPage.create}</button>}
          />
        ) : (
          <DataTable columns={columns} rows={rows} rowKey={(c) => c.id} />
        )}
      </div>

      {editing && (
        <Dialog onClose={() => setEditing(null)} maxWidth={520}>
          <h3>{editing === "new" ? t.categoriesPage.create : t.categoriesPage.edit}</h3>
          <form className="form" onSubmit={submit}>
            <label>
              {t.categoriesPage.name}
              <input
                value={form.name}
                maxLength={100}
                required
                onChange={(e) => {
                  const name = e.target.value;
                  setForm((f) => ({ ...f, name, slug: slugTouched ? f.slug : slugify(name) }));
                }}
              />
            </label>
            <label>
              {t.categoriesPage.slug}
              <input
                value={form.slug}
                maxLength={100}
                required
                pattern="[a-z0-9]+(-[a-z0-9]+)*"
                onChange={(e) => { setSlugTouched(true); setForm({ ...form, slug: e.target.value }); }}
              />
              <span className="form-hint">{t.categoriesPage.slugHint}</span>
            </label>
            <label>
              {t.common.description}
              <textarea rows={2} value={form.description ?? ""} onChange={(e) => setForm({ ...form, description: e.target.value })} />
            </label>
            <div className="form-row">
              <label>
                {t.categoriesPage.icon}
                <input value={form.icon ?? ""} maxLength={50} onChange={(e) => setForm({ ...form, icon: e.target.value })} />
              </label>
              <label>
                {t.categoriesPage.color}
                <input type="color" value={form.color ?? "#6366f1"} onChange={(e) => setForm({ ...form, color: e.target.value })} />
              </label>
              <label>
                {t.categoriesPage.order}
                <input type="number" value={form.order_index} onChange={(e) => setForm({ ...form, order_index: Number(e.target.value) })} />
              </label>
            </div>
            <label className="checkbox">
              <input type="checkbox" checked={form.is_active} onChange={(e) => setForm({ ...form, is_active: e.target.checked })} />
              {t.categoriesPage.visibleToLearners}
            </label>
            {formError && <div className="form-error" role="alert">{formError}</div>}
            <div className="table-actions">
              <button type="button" className="ghost-button" onClick={() => setEditing(null)}>{t.common.cancel}</button>
              <button type="submit" className="primary-button" disabled={save.isPending}>
                {save.isPending ? t.common.saving : editing === "new" ? t.common.create : t.common.update}
              </button>
            </div>
          </form>
        </Dialog>
      )}
    </div>
  );
};
