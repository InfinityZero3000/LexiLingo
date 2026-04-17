import React, { useEffect, useState } from "react";
import { SectionHeader } from "../components/SectionHeader";
import { StatusPill } from "../components/StatusPill";
import { useI18n } from "../lib/i18n";
import { apiFetch } from "../lib/api";
import { ENV } from "../lib/env";
import { Shield, UserPlus, Mail, Calendar, Activity } from "lucide-react";

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
  const [showAddModal, setShowAddModal] = useState(false);
  const [newEmail, setNewEmail] = useState("");
  const [newRole, setNewRole] = useState<"admin" | "super_admin">("admin");

  useEffect(() => {
    fetchAdmins();
  }, []);

  const fetchAdmins = async () => {
    try {
      // Backend accepts role as integer: 1=admin, 2=super_admin
      const [res1, res2] = await Promise.all([
        apiFetch<{ data: { users: any[] } }>(`${ENV.backendUrl}/admin/users?role=1&page_size=100`),
        apiFetch<{ data: { users: any[] } }>(`${ENV.backendUrl}/admin/users?role=2&page_size=100`),
      ]);
      const mapUser = (u: any): AdminUser => ({
        id: u.id,
        email: u.email,
        display_name: u.display_name ?? u.username,
        role: u.role_slug as "admin" | "super_admin",
        provider: u.provider ?? "—",
        is_active: u.is_active,
        created_at: u.created_at,
        last_login_at: u.last_login ?? undefined,
      });
      const all = [
        ...(res1.data?.users ?? []).map(mapUser),
        ...(res2.data?.users ?? []).map(mapUser),
      ];
      setAdmins(all);
    } catch (error) {
      console.error("Failed to fetch admins:", error);
    } finally {
      setLoading(false);
    }
  };

  const handleAddAdmin = async () => {
    if (!newEmail) return;
    try {
      // Step 1: find user by email
      const searchRes = await apiFetch<{ data: { users: any[] } }>(
        `${ENV.backendUrl}/admin/users?search=${encodeURIComponent(newEmail)}&page_size=10`
      );
      const target = (searchRes.data?.users ?? []).find(
        (u: any) => u.email.toLowerCase() === newEmail.toLowerCase()
      );
      if (!target) {
        alert("User not found. Make sure they have registered first.");
        return;
      }
      // Step 2: promote to role (1=admin, 2=super_admin)
      await apiFetch(`${ENV.backendUrl}/admin/users/${target.id}/role`, {
        method: "PUT",
        body: JSON.stringify({ level: newRole === "super_admin" ? 2 : 1 }),
      });
      setShowAddModal(false);
      setNewEmail("");
      fetchAdmins();
    } catch (error: any) {
      console.error("Failed to add admin:", error);
      alert(error?.message || "Failed to promote user");
    }
  };

  const handleToggleStatus = async (userId: string, currentStatus: boolean) => {
    try {
      await apiFetch(`${ENV.backendUrl}/admin/users/${userId}/status`, {
        method: "PUT",
        body: JSON.stringify({ is_active: !currentStatus }),
      });
      fetchAdmins();
    } catch (error) {
      console.error("Failed to toggle status:", error);
    }
  };

  if (loading) return <div className="loading">{t.common.loading}</div>;

  return (
    <div className="stack">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
        <SectionHeader 
          title={t.adminManagement.title} 
          description={t.adminManagement.description} 
        />
        <button className="btn-primary" onClick={() => setShowAddModal(true)}>
          <UserPlus size={16} />
          {t.adminManagement.addAdmin}
        </button>
      </div>

      {/* Admin List */}
      <div className="panel">
        <div className="table-container">
          <table className="data-table">
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
              {admins.map((admin) => (
                <tr key={admin.id}>
                  <td>
                    <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                      <Mail size={16} style={{ color: "var(--muted)" }} />
                      {admin.email}
                    </div>
                  </td>
                  <td>{admin.display_name}</td>
                  <td>
                    <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                      <Shield 
                        size={14} 
                        style={{ color: admin.role === "super_admin" ? "var(--accent)" : "var(--muted)" }} 
                      />
                      <span style={{ 
                        fontWeight: admin.role === "super_admin" ? 600 : 400,
                        color: admin.role === "super_admin" ? "var(--accent)" : "inherit"
                      }}>
                        {admin.role === "super_admin" ? t.adminManagement.superAdmin : t.adminManagement.admin}
                      </span>
                    </div>
                  </td>
                  <td>
                    <span className="tag" style={{
                      background: admin.provider === "google" ? "#EBF5FF" : "#F5F5F5",
                      color: admin.provider === "google" ? "#1E40AF" : "#666"
                    }}>
                      {admin.provider}
                    </span>
                  </td>
                  <td>
                    <StatusPill 
                      tone={admin.is_active ? "success" : "muted"} 
                      label={admin.is_active ? t.common.active : t.common.inactive} 
                    />
                  </td>
                  <td>
                    <div style={{ display: "flex", alignItems: "center", gap: 6, fontSize: 13, color: "var(--muted)" }}>
                      {admin.last_login_at ? (
                        <>
                          <Calendar size={14} />
                          {new Date(admin.last_login_at).toLocaleDateString()}
                        </>
                      ) : (
                        <span>—</span>
                      )}
                    </div>
                  </td>
                  <td>
                    <button 
                      className="btn-ghost btn-sm"
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
      </div>

      {/* Add Admin Modal */}
      {showAddModal && (
        <div className="modal-overlay" onClick={() => setShowAddModal(false)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()}>
            <SectionHeader 
              title={t.adminManagement.addAdmin} 
              description={t.adminManagement.addAdminDesc} 
            />
            <div className="stack" style={{ gap: 16 }}>
              <div className="form-field">
                <label>{t.adminManagement.email}</label>
                <input
                  type="email"
                  value={newEmail}
                  onChange={(e) => setNewEmail(e.target.value)}
                  placeholder="user@example.com"
                  className="input"
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
                <button className="btn-secondary" onClick={() => setShowAddModal(false)}>
                  {t.common.cancel}
                </button>
                <button className="btn-primary" onClick={handleAddAdmin}>
                  {t.adminManagement.addAdmin}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
