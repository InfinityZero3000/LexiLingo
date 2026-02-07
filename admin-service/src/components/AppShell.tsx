import React, { useState } from "react";
import { NavLink, Outlet } from "react-router-dom";
import { useAuth } from "./AuthProvider";
import { Role } from "../lib/auth";
import { useI18n } from "../lib/i18n";

export type NavItem = {
  to: string;
  label: string;
  icon?: React.ReactNode;
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
  const { t } = useI18n();
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  const toggleMobileMenu = () => setMobileMenuOpen(!mobileMenuOpen);
  const closeMobileMenu = () => setMobileMenuOpen(false);

  return (
    <div className="app-shell">
      {/* Mobile Overlay */}
      <div 
        className={`mobile-overlay ${mobileMenuOpen ? 'active' : ''}`}
        onClick={closeMobileMenu}
      />

      <aside className={`sidebar ${mobileMenuOpen ? 'mobile-open' : ''}`}>
        <div className="brand">
          <div className="brand-mark">LL</div>
          <div>
            <div className="brand-title">LexiLingo</div>
            <div className="brand-sub">{role === "super_admin" ? t.appShell.superAdmin : t.appShell.adminConsole}</div>
          </div>
        </div>

        <div className="nav-section">
          <div className="nav-title">{t.appShell.navigation}</div>
          <nav className="nav-links">
            {navItems.map((item) => (
              <NavLink
                key={item.to}
                to={item.to}
                className={({ isActive }) => (isActive ? "nav-link active" : "nav-link")}
                onClick={closeMobileMenu}
              >
                {item.icon && <span className="nav-icon">{item.icon}</span>}
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
              <div className="user-card-email">{user?.email}</div>
            </div>
          </div>
          <button className="ghost-button" onClick={signOut}>
            {t.appShell.logout}
          </button>
        </div>
      </aside>

      <main className="main">
        <div className="topbar">
          <button 
            className={`mobile-menu-btn ${mobileMenuOpen ? 'active' : ''}`}
            onClick={toggleMobileMenu}
            aria-label="Toggle menu"
          >
            <span></span>
            <span></span>
            <span></span>
          </button>
        </div>
        <div className="topbar-line" />

        <div className="page">
          <Outlet />
        </div>
      </main>
    </div>
  );
};
