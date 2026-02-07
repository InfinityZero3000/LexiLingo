import React, { useEffect, useState } from "react";
import { DataTable } from "../components/DataTable";
import { SectionHeader } from "../components/SectionHeader";
import { StatusPill } from "../components/StatusPill";
import { AdminUser, listRoles, listUsers, RoleInfo, updateUser } from "../lib/adminApi";

export const UsersPage = () => {
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [roles, setRoles] = useState<RoleInfo[]>([]);
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadData = async (query?: string) => {
    setLoading(true);
    setError(null);
    try {
      const [usersRes, rolesRes] = await Promise.all([listUsers(query), listRoles()]);
      setUsers(usersRes.data || []);
      setRoles(rolesRes.data || []);
    } catch (err: any) {
      setError(err?.message || "Không tải được dữ liệu users");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void loadData();
  }, []);

  const handleRoleChange = async (userId: string, roleSlug: string) => {
    try {
      await updateUser(userId, { role_slug: roleSlug });
      await loadData(search || undefined);
    } catch (err: any) {
      setError(err?.message || "Không cập nhật role");
    }
  };

  const toggleActive = async (userId: string, isActive: boolean) => {
    try {
      await updateUser(userId, { is_active: isActive });
      await loadData(search || undefined);
    } catch (err: any) {
      setError(err?.message || "Không cập nhật trạng thái user");
    }
  };

  return (
    <div className="panel">
      <SectionHeader
        title="Quản lý Users"
        description="GET /api/v1/admin/users"
        action={
          <div className="inline-actions">
            <input
              placeholder="Tìm email hoặc username"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
            <button className="ghost-button" onClick={() => loadData(search || undefined)}>
              Tìm
            </button>
          </div>
        }
      />
      {error && <div className="form-error">{error}</div>}
      {loading ? (
        <div className="loading">Đang tải dữ liệu...</div>
      ) : (
        <DataTable
          columns={[
            {
              header: "User",
              render: (row) => (
                <div>
                  <div className="table-title">{row.display_name || row.username}</div>
                  <div className="table-sub">{row.email}</div>
                </div>
              )
            },
            {
              header: "Role",
              render: (row) => (
                <select
                  value={row.role_slug}
                  onChange={(e) => handleRoleChange(row.id, e.target.value)}
                >
                  {roles.map((role) => (
                    <option key={role.slug} value={role.slug}>
                      {role.name}
                    </option>
                  ))}
                </select>
              )
            },
            {
              header: "Status",
              render: (row) => (
                <StatusPill tone={row.is_active ? "success" : "danger"} label={row.is_active ? "Active" : "Locked"} />
              ),
              align: "center"
            },
            {
              header: "Hành động",
              render: (row) => (
                <div className="table-actions">
                  <button
                    className="ghost-button small"
                    onClick={() => toggleActive(row.id, !row.is_active)}
                  >
                    {row.is_active ? "Khóa" : "Mở"}
                  </button>
                </div>
              ),
              align: "right"
            }
          ]}
          rows={users}
        />
      )}
    </div>
  );
};
