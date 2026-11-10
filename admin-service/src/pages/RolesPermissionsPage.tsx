import { useEffect, useState } from "react";
import { useMutation, useQueries, useQuery, useQueryClient } from "@tanstack/react-query";
import { Check, Minus } from "lucide-react";
import { useAuth } from "../components/AuthProvider";
import { useConfirm } from "../components/ConfirmDialog";
import { SectionHeader } from "../components/SectionHeader";
import { EmptyState } from "../components/EmptyState";
import { TableSkeleton } from "../components/Skeleton";
import { StatusPill } from "../components/StatusPill";
import { getRoles, getRoleWithPermissions, getPermissions, setRolePermissions, Permission } from "../lib/rbacApi";
import { useI18n } from "../lib/i18n";

const groupByResource = (permissions: Permission[]) => {
  const groups = new Map<string, Permission[]>();
  for (const permission of permissions) {
    const list = groups.get(permission.resource) ?? [];
    list.push(permission);
    groups.set(permission.resource, list);
  }
  return [...groups.entries()].sort(([a], [b]) => a.localeCompare(b));
};

export const RolesPermissionsPage = () => {
  const { t } = useI18n();
  const { role: myRole } = useAuth();
  const confirm = useConfirm();
  const queryClient = useQueryClient();
  const canEdit = myRole === "super_admin";
  const [draft, setDraft] = useState<Record<string, Set<string>>>({});
  const [saveError, setSaveError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const roles = useQuery({ queryKey: ["rbac-roles"], queryFn: getRoles });
  const permissions = useQuery({ queryKey: ["rbac-permissions"], queryFn: getPermissions });

  const roleDetails = useQueries({
    queries: (roles.data ?? []).map((role) => ({
      queryKey: ["rbac-role", role.slug],
      queryFn: () => getRoleWithPermissions(role.slug),
    })),
  });

  const loading = roles.isLoading || permissions.isLoading || roleDetails.some((q) => q.isLoading);
  const error = roles.error || permissions.error || roleDetails.find((q) => q.error)?.error;

  const sortedRoles = [...(roles.data ?? [])].sort((a, b) => a.level - b.level);
  const granted = new Map<string, Set<string>>(
    roleDetails.flatMap((q) => (q.data ? [[q.data.slug, new Set(q.data.permissions.map((p) => p.slug))] as const] : [])),
  );
  const groups = groupByResource(permissions.data ?? []);

  const roleKey = roleDetails.map((q) => q.dataUpdatedAt).join(",");
  useEffect(() => setDraft({}), [roleKey]);

  const holds = (role: string, slug: string) => (draft[role] ?? granted.get(role))?.has(slug) ?? false;
  const dirtyRoles = Object.keys(draft).filter((slug) => {
    const original = granted.get(slug) ?? new Set<string>();
    return draft[slug].size !== original.size || [...draft[slug]].some((p) => !original.has(p));
  });
  const toggle = (role: string, slug: string) => {
    setSaved(false);
    setDraft((current) => {
      const next = new Set(current[role] ?? granted.get(role) ?? []);
      next.has(slug) ? next.delete(slug) : next.add(slug);
      return { ...current, [role]: next };
    });
  };

  const save = useMutation({
    mutationFn: async () => {
      for (const slug of dirtyRoles) await setRolePermissions(slug, [...draft[slug]]);
    },
    onMutate: () => setSaveError(null),
    onSuccess: () => {
      setSaved(true);
      queryClient.invalidateQueries({ queryKey: ["rbac-role"] });
      queryClient.invalidateQueries({ queryKey: ["my-permissions"] });
    },
    onError: (err) => setSaveError(err instanceof Error && err.message ? err.message : t.rolesPage.saveFailed),
  });

  const askSave = async () => {
    const ok = await confirm({
      title: t.rolesPage.confirmTitle,
      message: t.rolesPage.confirmMessage.replace("{roles}", dirtyRoles.join(", ")),
      confirmLabel: t.common.save,
    });
    if (ok) save.mutate();
  };

  return (
    <div className="stack">
      <SectionHeader
        title={t.rolesPage.title}
        description={t.rolesPage.description}
        action={
          canEdit && dirtyRoles.length > 0 ? (
            <div className="cluster">
              <button className="ghost-button" onClick={() => setDraft({})} disabled={save.isPending}>{t.rolesPage.discard}</button>
              <button className="primary-button" onClick={askSave} disabled={save.isPending}>
                {save.isPending ? t.common.saving : t.rolesPage.saveChanges}
              </button>
            </div>
          ) : undefined
        }
      />

      <div className="panel" role="note">{canEdit ? t.rolesPage.editHint : t.rolesPage.readOnlyHint}</div>
      {saved && <div className="form-success" role="status">{t.rolesPage.saved}</div>}
      {saveError && <div className="form-error" role="alert">{saveError}</div>}

      {error && (
        <div className="form-error" role="alert">
          {(error as Error).message || t.rolesPage.loadFailed}
        </div>
      )}

      <div className="panel">
        {loading ? (
          <TableSkeleton rows={6} cols={4} />
        ) : groups.length === 0 ? (
          <EmptyState title={t.rolesPage.emptyTitle} description={t.rolesPage.emptyDescription} />
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th scope="col">{t.rolesPage.permission}</th>
                  {sortedRoles.map((role) => (
                    <th scope="col" key={role.slug} style={{ textAlign: "center" }}>
                      <div>{role.name}</div>
                      <div className="text-small text-muted">
                        {t.rolesPage.level} {role.level}
                        {role.is_system ? ` · ${t.rolesPage.systemRole}` : ""}
                      </div>
                      {!role.is_active && <StatusPill tone="neutral" label={t.rolesPage.inactive} />}
                    </th>
                  ))}
                </tr>
              </thead>
              {groups.map(([resource, items]) => (
                <tbody key={resource}>
                  <tr>
                    <th scope="rowgroup" colSpan={sortedRoles.length + 1} className="text-small text-muted">
                      {resource}
                    </th>
                  </tr>
                  {items.map((permission) => (
                    <tr key={permission.slug}>
                      <td>
                        <div className="mono text-small">{permission.slug}</div>
                        {permission.description && <div className="text-small text-muted">{permission.description}</div>}
                      </td>
                      {sortedRoles.map((role) => {
                        const has = holds(role.slug, permission.slug);
                        const editable = canEdit && role.level === 1;
                        return (
                          <td key={role.slug} style={{ textAlign: "center" }}>
                            {editable ? (
                              <input
                                type="checkbox"
                                checked={has}
                                onChange={() => toggle(role.slug, permission.slug)}
                                aria-label={`${role.name}: ${permission.slug}`}
                              />
                            ) : has ? (
                              <Check size={16} aria-label={t.rolesPage.granted} />
                            ) : (
                              <Minus size={16} className="text-muted" aria-label={t.rolesPage.notGranted} />
                            )}
                          </td>
                        );
                      })}
                    </tr>
                  ))}
                </tbody>
              ))}
            </table>
          </div>
        )}
      </div>
    </div>
  );
};
