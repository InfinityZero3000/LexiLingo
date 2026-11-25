import { useEffect, useState } from "react";
import { useMutation, useQueries, useQuery, useQueryClient } from "@tanstack/react-query";
import { Check, Info, KeyRound, Layers, Minus, Shield, ShieldCheck } from "lucide-react";
import { useAuth } from "../components/AuthProvider";
import { useConfirm } from "../components/ConfirmDialog";
import { SectionHeader } from "../components/SectionHeader";
import { StatCard } from "../components/StatCard";
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

      {!error && (
        <div className="card-grid">
          <StatCard
            label={t.rolesPage.permission}
            value={String(permissions.data?.length ?? 0)}
            variant="blue"
            icon={<KeyRound size={18} />}
            loading={loading}
          />
          <StatCard
            label={t.rolesPage.systemRole}
            value={String(sortedRoles.length)}
            accent="teal"
            icon={<Shield size={18} />}
            loading={loading}
          />
          <StatCard
            label={t.rolesPage.level}
            value={String(groups.length)}
            variant="dark"
            icon={<Layers size={18} />}
            loading={loading}
          />
        </div>
      )}

      <div
        className="panel"
        role="note"
        style={{
          flexDirection: "row",
          alignItems: "center",
          gap: 12,
          padding: "14px 18px",
          borderRadius: "var(--radius-inner)",
          background: canEdit ? "var(--accent-soft)" : "var(--panel-soft-2)",
          borderColor: canEdit ? "rgba(255, 77, 0, 0.22)" : "var(--line)",
        }}
      >
        <span
          style={{
            width: 34,
            height: 34,
            borderRadius: 10,
            display: "grid",
            placeItems: "center",
            flexShrink: 0,
            background: canEdit ? "var(--accent)" : "var(--panel)",
            color: canEdit ? "#ffffff" : "var(--muted)",
            border: canEdit ? "none" : "1px solid var(--line)",
          }}
        >
          {canEdit ? <ShieldCheck size={16} /> : <Info size={16} />}
        </span>
        <span style={{ fontSize: 13, fontWeight: 500, color: canEdit ? "var(--accent)" : "var(--text)" }}>
          {canEdit ? t.rolesPage.editHint : t.rolesPage.readOnlyHint}
        </span>
      </div>
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
                      <div style={{ fontSize: 13, fontWeight: 700, color: "var(--text)", textTransform: "none", letterSpacing: 0 }}>
                        {role.name}
                      </div>
                      <div style={{ display: "inline-flex", alignItems: "center", gap: 6, marginTop: 6, flexWrap: "wrap", justifyContent: "center" }}>
                        <span
                          className="text-small text-muted"
                          style={{
                            padding: "2px 8px",
                            borderRadius: 999,
                            background: "var(--panel)",
                            border: "1px solid var(--line)",
                            textTransform: "none",
                            letterSpacing: 0,
                            fontWeight: 600,
                          }}
                        >
                          {t.rolesPage.level} {role.level}
                          {role.is_system ? ` · ${t.rolesPage.systemRole}` : ""}
                        </span>
                        {!role.is_active && <StatusPill tone="neutral" label={t.rolesPage.inactive} />}
                      </div>
                    </th>
                  ))}
                </tr>
              </thead>
              {groups.map(([resource, items]) => (
                <tbody key={resource}>
                  <tr>
                    <th
                      scope="rowgroup"
                      colSpan={sortedRoles.length + 1}
                      className="text-small text-muted"
                      style={{
                        background: "var(--panel-soft-2)",
                        padding: "10px 14px",
                      }}
                    >
                      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 8 }}>
                        <span
                          style={{
                            display: "inline-flex",
                            alignItems: "center",
                            padding: "3px 10px",
                            borderRadius: 999,
                            background: "var(--accent-soft)",
                            color: "var(--accent)",
                            fontWeight: 700,
                            fontSize: 11,
                          }}
                        >
                          {resource}
                        </span>
                        <span
                          style={{
                            padding: "2px 8px",
                            borderRadius: 999,
                            background: "var(--panel)",
                            border: "1px solid var(--line)",
                            fontSize: 11,
                            fontWeight: 600,
                          }}
                        >
                          {items.length}
                        </span>
                      </div>
                    </th>
                  </tr>
                  {items.map((permission) => (
                    <tr key={permission.slug}>
                      <td>
                        <div
                          className="mono text-small"
                          style={{
                            display: "inline-block",
                            padding: "3px 10px",
                            borderRadius: 8,
                            background: "var(--panel-soft-2)",
                            border: "1px solid var(--line)",
                            fontWeight: 600,
                          }}
                        >
                          {permission.slug}
                        </div>
                        {permission.description && (
                          <div className="text-small text-muted" style={{ marginTop: 4 }}>
                            {permission.description}
                          </div>
                        )}
                      </td>
                      {sortedRoles.map((role) => {
                        const has = holds(role.slug, permission.slug);
                        const editable = canEdit && role.level === 1;
                        return (
                          <td key={role.slug} style={{ textAlign: "center" }}>
                            {editable ? (
                              <label
                                style={{
                                  display: "inline-flex",
                                  alignItems: "center",
                                  justifyContent: "center",
                                  width: 34,
                                  height: 34,
                                  borderRadius: 10,
                                  background: has ? "var(--accent-soft)" : "var(--panel-soft-2)",
                                  border: has ? "1px solid rgba(255, 77, 0, 0.25)" : "1px solid var(--line)",
                                  cursor: "pointer",
                                }}
                              >
                                <input
                                  type="checkbox"
                                  checked={has}
                                  onChange={() => toggle(role.slug, permission.slug)}
                                  aria-label={`${role.name}: ${permission.slug}`}
                                  style={{
                                    width: 17,
                                    height: 17,
                                    accentColor: "var(--accent)",
                                    cursor: "pointer",
                                    margin: 0,
                                  }}
                                />
                              </label>
                            ) : has ? (
                              <span
                                style={{
                                  display: "inline-grid",
                                  placeItems: "center",
                                  width: 28,
                                  height: 28,
                                  borderRadius: 999,
                                  background: "var(--accent-2-soft)",
                                  color: "var(--accent-2)",
                                }}
                              >
                                <Check size={15} aria-label={t.rolesPage.granted} />
                              </span>
                            ) : (
                              <span
                                style={{
                                  display: "inline-grid",
                                  placeItems: "center",
                                  width: 28,
                                  height: 28,
                                  borderRadius: 999,
                                  background: "var(--panel-soft)",
                                }}
                              >
                                <Minus size={15} className="text-muted" aria-label={t.rolesPage.notGranted} />
                              </span>
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
