import React from "react";
import { NavLink, Outlet } from "react-router-dom";
import { useAuth } from "./AuthProvider";
import { Role } from "../lib/auth";

export type NavItem = {
  to: string;
  label: string;
  description?: string;
  badge?: string;
};

export const AppShell = ({
  title,
  role,
  navItems,
  children
}: {
  title: string;
  role: Role;
  navItems: NavItem[];
  children?: React.ReactNode;
}) => {
  const { user, signOut } = useAuth();

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-mark">LL</div>
          <div>
            <div className="brand-title">LexiLingo</div>
            <div className="brand-sub">{role === "super_admin" ? "Super Admin" : "Admin Console"}</div>
          </div>
        </div>

        <div className="nav-section">
          <div className="nav-title">Điều hướng</div>
          <nav className="nav-links">
            {navItems.map((item) => (
              <NavLink
                key={item.to}
                to={item.to}
                className={({ isActive }) => (isActive ? "nav-link active" : "nav-link")}
              >
                <span className="nav-label">{item.label}</span>
                {item.badge && <span className="nav-badge">{item.badge}</span>}
              </NavLink>
            ))}
          </nav>
        </div>

        <div className="sidebar-footer">
          <div className="user-card">
            <div className="user-avatar">{user?.username?.slice(0, 2).toUpperCase()}</div>
            <div>
              <div className="user-name">{user?.display_name || user?.username}</div>
              <div className="user-email">{user?.email}</div>
            </div>
          </div>
          <button className="ghost-button" onClick={signOut}>
            Đăng xuất
          </button>
        </div>
      </aside>

      <main className="main">
        <header className="topbar">
          <div>
            <div className="page-title">{title}</div>
            <div className="page-subtitle">Điều khiển nội dung, hệ thống và vận hành</div>
          </div>
          <div className="topbar-actions">{children}</div>
        </header>

        <div className="page">
          <Outlet />
        </div>
      </main>
    </div>
  );
};
