import { Dialog } from "../components/Dialog";
import React, { useEffect, useState } from "react";
import { SectionHeader } from "../components/SectionHeader";
import { StatCard } from "../components/StatCard";
import { StatusPill } from "../components/StatusPill";
import { TableSkeleton } from "../components/Skeleton";
import { useI18n } from "../lib/i18n";
import { apiFetch } from "../lib/api";
import { ENV } from "../lib/env";
import { Shield, UserPlus, Mail, Calendar, Users, CheckCircle2 } from "lucide-react";

interface AdminUser {
  id: string;
  email: string;
  display_name: string;
  role: "admin" | "super_admin";
  provider: string[];
  is_active: boolean;
  created_at: string;
  last_login_at?: string;
}

export const AdminManagementPage = () => {
  const { t } = useI18n();
  const [admins, setAdmins] = useState<AdminUser[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [showAddModal, setShowAddModal] = useState(false);
  const [newEmail, setNewEmail] = useState("");
  const [newRole, setNewRole] = useState<"admin" | "super_admin">("admin");
  const [modalError, setModalError] = useState<string | null>(null);
  const [adding, setAdding] = useState(false);

  useEffect(() => {
    fetchAdmins();
  }, []);

  const fetchAdmins = async () => {
    setLoading(true);
    setError(null);
    try {
      const [res1, res2] = await Promise.all([
        apiFetch<{ data: { users: any[] } }>(`${ENV.backendUrl}/admin/users?role=1&page_size=100`),
        apiFetch<{ data: { users: any[] } }>(`${ENV.backendUrl}/admin/users?role=2&page_size=100`),
      ]);
      const mapUser = (u: any): AdminUser => ({
        id: u.id,
        email: u.email,
        display_name: u.display_name ?? u.username,
        role: u.role_slug as "admin" | "super_admin",
        provider: Array.isArray(u.provider) ? u.provider : [u.provider ?? "—"],
        is_active: u.is_active,
        created_at: u.created_at,
        last_login_at: u.last_login ?? undefined,
      });
      const all = [
        ...(res1.data?.users ?? []).map(mapUser),
        ...(res2.data?.users ?? []).map(mapUser),
      ];
      setAdmins(all);
    } catch (err: any) {
      setError(err?.message || t.adminPages.adminsLoadFailed);
    } finally {
      setLoading(false);
    }
  };

  const handleAddAdmin = async () => {
    if (!newEmail) return;
    setAdding(true);
    setModalError(null);
    try {
      const searchRes = await apiFetch<{ data: { users: any[] } }>(
        `${ENV.backendUrl}/admin/users?search=${encodeURIComponent(newEmail)}&page_size=10`
      );
      const target = (searchRes.data?.users ?? []).find(
        (u: any) => u.email.toLowerCase() === newEmail.toLowerCase()
      );
      if (!target) {
        setModalError(t.adminPages.adminUserNotFound);
        return;
      }
      await apiFetch(`${ENV.backendUrl}/admin/users/${target.id}/role`, {
        method: "PUT",
        body: JSON.stringify({ level: newRole === "super_admin" ? 2 : 1 }),
      });
      setShowAddModal(false);
      setNewEmail("");
      setModalError(null);
      await fetchAdmins();
    } catch (err: any) {
      setModalError(err?.message || t.adminPages.adminGrantFailed);
    } finally {
      setAdding(false);
    }
  };

  const handleToggleStatus = async (userId: string, currentStatus: boolean) => {
    try {
      await apiFetch(`${ENV.backendUrl}/admin/users/${userId}/status`, {
        method: "PUT",
        body: JSON.stringify({ is_active: !currentStatus }),
      });
      await fetchAdmins();
    } catch (err: any) {
      setError(err?.message || t.adminPages.adminStatusFailed);
    }
  };

  const superAdminCount = admins.filter((a) => a.role === "super_admin").length;
  const activeCount = admins.filter((a) => a.is_active).length;

  return (
    <div className="stack">
      <SectionHeader
        title={t.adminManagement.title}
        description={t.adminManagement.description}
        action={
          <button className="primary-button" onClick={() => { setShowAddModal(true); setModalError(null); }}>
            <UserPlus size={16} />
            {t.adminManagement.addAdmin}
          </button>
        }
      />

      <div className="card-grid">
        <StatCard
          label={t.adminManagement.title}
          value={String(admins.length)}
          variant="blue"
          icon={<Users size={18} />}
          loading={loading}
        />
        <StatCard
          label={t.adminManagement.superAdmin}
          value={String(superAdminCount)}
          accent="berry"
          icon={<Shield size={18} />}
          loading={loading}
        />
        <StatCard
          label={t.common.active}
          value={String(activeCount)}
          variant="dark"
          icon={<CheckCircle2 size={18} />}
          loading={loading}
        />
      </div>

      {error && <div className="form-error" role="alert">{error}</div>}

      {/* Admin List */}
      <div className="panel">
        {loading ? (
          <TableSkeleton rows={5} cols={7} />
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>{t.adminManagement.email}</th>
                  <th>{t.adminManagement.displayName}</th>
                  <th>{t.adminManagement.role}</th>
                  <th>{t.adminManagement.provider}</th>
                  <th>{t.adminManagement.status}</th>
                  <th>{t.adminManagement.lastLogin}</th>
                  <th>{t.common.actions}</th>
                </tr>
              </thead>
              <tbody>
                {admins.length === 0 ? (
                  <tr>
                    <td colSpan={7} style={{ textAlign: "center", padding: 24, color: "var(--muted)" }}>
                      {t.adminPages.adminsEmpty}
                    </td>
                  </tr>
                ) : admins.map((admin) => (
                  <tr key={admin.id}>
                    <td>
                      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                        <Mail size={16} style={{ color: "var(--muted)" }} />
                        <span>{admin.email}</span>
                      </div>
                    </td>
                    <td className="table-title">{admin.display_name}</td>
                    <td>
                      <span
                        className="tag"
                        style={{
                          gap: 6,
                          background: admin.role === "super_admin" ? "var(--accent-soft)" : "var(--panel-soft-2)",
                          color: admin.role === "super_admin" ? "var(--accent)" : "var(--text)",
                          borderColor: admin.role === "super_admin" ? "rgba(255, 77, 0, 0.22)" : "var(--line)",
                        }}
                      >
                        <Shield size={13} />
                        {admin.role === "super_admin" ? t.adminManagement.superAdmin : t.adminManagement.admin}
                      </span>
                    </td>
                    <td>
                      <span
                        className="tag"
                        style={{
                          background: admin.provider.includes("google") ? "var(--accent-soft)" : "var(--panel-soft-2)",
                          color: admin.provider.includes("google") ? "var(--accent)" : "var(--text)",
                          borderColor: admin.provider.includes("google") ? "rgba(255, 77, 0, 0.22)" : "var(--line)",
                        }}
                      >
                        {admin.provider.join(", ")}
                      </span>
                    </td>
                    <td>
                      <StatusPill
                        tone={admin.is_active ? "success" : "neutral"}
                        label={admin.is_active ? t.common.active : t.common.inactive}
                      />
                    </td>
                    <td>
                      <div className="text-small text-muted" style={{ display: "flex", alignItems: "center", gap: 6 }}>
                        {admin.last_login_at ? (
                          <>
                            <Calendar size={14} />
                            {new Date(admin.last_login_at).toLocaleDateString("vi-VN")}
                          </>
                        ) : (
                          <span>—</span>
                        )}
                      </div>
                    </td>
                    <td>
                      <button
                        className="ghost-button small"
                        onClick={() => handleToggleStatus(admin.id, admin.is_active)}
                      >
                        {admin.is_active ? t.adminManagement.deactivate : t.adminManagement.activate}
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Add Admin Modal */}
      {showAddModal && (
        <Dialog onClose={() => setShowAddModal(false)} maxWidth={480}>
          <SectionHeader
            title={t.adminManagement.addAdmin}
            description={t.adminManagement.addAdminDesc}
          />
          <div className="stack" style={{ gap: 16 }}>
            {modalError && <div className="form-error">{modalError}</div>}
            <div className="form-field">
              <label>{t.adminManagement.email}</label>
              <input
                type="email"
                value={newEmail}
                onChange={(e) => setNewEmail(e.target.value)}
                placeholder="user@example.com"
                className="input"
                onKeyDown={(e) => e.key === "Enter" && handleAddAdmin()}
              />
              <small>{t.adminManagement.emailHint}</small>
            </div>
            <div className="form-field">
              <label>{t.adminManagement.role}</label>
              <select
                value={newRole}
                onChange={(e) => setNewRole(e.target.value as "admin" | "super_admin")}
                className="input"
              >
                <option value="admin">{t.adminManagement.admin}</option>
                <option value="super_admin">{t.adminManagement.superAdmin}</option>
              </select>
            </div>
            <div style={{ display: "flex", gap: 12, justifyContent: "flex-end" }}>
              <button className="ghost-button" onClick={() => setShowAddModal(false)} disabled={adding}>
                {t.common.cancel}
              </button>
              <button className="primary-button" onClick={handleAddAdmin} disabled={adding || !newEmail}>
                {adding ? t.common.saving : t.adminManagement.addAdmin}
              </button>
            </div>
          </div>
        </Dialog>
      )}
    </div>
  );
};
