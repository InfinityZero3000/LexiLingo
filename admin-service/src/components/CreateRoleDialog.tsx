import { useState, type FormEvent } from "react";
import { useMutation } from "@tanstack/react-query";
import { createRole } from "../lib/rbacApi";
import { useI18n } from "../lib/i18n";
import { Dialog } from "./Dialog";

const SLUG_PATTERN = /^[a-z][a-z0-9_]{1,49}$/;

export const slugFromName = (name: string) =>
  name
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/đ/gi, "d")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^[^a-z]+|_+$/g, "")
    .slice(0, 50);

export const CreateRoleDialog = ({
  onClose,
  onCreated,
}: {
  onClose: () => void;
  onCreated: (name: string) => void;
}) => {
  const { t } = useI18n();
  const [name, setName] = useState("");
  const [typedSlug, setTypedSlug] = useState<string | null>(null);
  const [description, setDescription] = useState("");
  const slug = typedSlug ?? slugFromName(name);
  const valid = name.trim().length >= 2 && SLUG_PATTERN.test(slug);

  const create = useMutation({
    mutationFn: () =>
      createRole({ name: name.trim(), slug, description: description.trim() || undefined }),
    onSuccess: () => onCreated(name.trim()),
  });

  const submit = (event: FormEvent) => {
    event.preventDefault();
    if (valid && !create.isPending) create.mutate();
  };

  return (
    <Dialog onClose={onClose} maxWidth={480}>
      <form className="stack" style={{ gap: 16 }} onSubmit={submit}>
        <div>
          <h3>{t.rolesPage.createRole}</h3>
          <p className="text-small text-muted">{t.rolesPage.createDescription}</p>
        </div>
        {create.error && (
          <div className="form-error" role="alert">
            {(create.error as Error).message || t.rolesPage.createFailed}
          </div>
        )}
        <div className="form-field">
          <label htmlFor="role-name">{t.rolesPage.nameLabel}</label>
          <input id="role-name" className="input" maxLength={50} value={name} onChange={(e) => setName(e.target.value)} />
        </div>
        <div className="form-field">
          <label htmlFor="role-slug">{t.rolesPage.slugLabel}</label>
          <input
            id="role-slug"
            className="input mono"
            maxLength={50}
            value={slug}
            onChange={(e) => setTypedSlug(e.target.value)}
            aria-describedby="role-slug-hint"
          />
          <small id="role-slug-hint">{t.rolesPage.slugHint}</small>
        </div>
        <div className="form-field">
          <label htmlFor="role-description">{t.rolesPage.descriptionLabel}</label>
          <input id="role-description" className="input" maxLength={500} value={description} onChange={(e) => setDescription(e.target.value)} />
        </div>
        <div className="inline-actions confirm-actions">
          <button type="button" className="ghost-button" onClick={onClose} disabled={create.isPending}>
            {t.common.cancel}
          </button>
          <button type="submit" className="primary-button" disabled={!valid || create.isPending}>
            {create.isPending ? t.common.saving : t.rolesPage.createAction}
          </button>
        </div>
      </form>
    </Dialog>
  );
};
