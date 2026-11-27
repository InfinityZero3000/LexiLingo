import React, { useState } from "react";
import { Link, NavLink, Outlet, useLocation } from "react-router-dom";
import { useAuth } from "./AuthProvider";
import { Role } from "../lib/auth";
import { useI18n } from "../lib/i18n";
import { ThemeToggle } from "./ThemeToggle";

export type NavItem = {
  to: string;
  label: string;
  icon?: React.ReactNode;
  description?: string;
  badge?: string;
  group?: string;
  /** Hidden when the signed-in admin lacks it; the server enforces it either way. */
  permission?: string;
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
  const { t, locale, setLocale } = useI18n();
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [navFilter, setNavFilter] = useState("");
  const [collapsedGroups, setCollapsedGroups] = useState<Record<string, boolean>>({});
  const { pathname } = useLocation();

  const normalizedFilter = navFilter.trim().toLowerCase();
  const visibleNavItems = normalizedFilter
    ? navItems.filter(
        (item) =>
          item.label.toLowerCase().includes(normalizedFilter) ||
          (item.group && item.group.toLowerCase().includes(normalizedFilter))
      )
    : navItems;

  const sections = visibleNavItems.reduce<{ label?: string; items: NavItem[] }[]>((acc, item) => {
    const last = acc[acc.length - 1];
    if (last && last.label === item.group) last.items.push(item);
    else acc.push({ label: item.group, items: [item] });
    return acc;
  }, []);

  const current = navItems
    .filter((i) => pathname === i.to || pathname.startsWith(`${i.to}/`))
    .sort((a, b) => b.to.length - a.to.length)[0];
  const segmentLabels: Record<string, string> = {
    units: t.nav.units,
    lessons: t.nav.lessons,
    exercises: t.nav.exercises,
  };
  const crumbs: { label: string; to?: string }[] = [];
  if (current) {
    if (current.group) crumbs.push({ label: current.group });
    crumbs.push({ label: current.label, to: current.to });
    const segs = pathname.split("/").filter(Boolean);
    const base = current.to.split("/").filter(Boolean).length;
    segs.forEach((seg, i) => {
      if (i >= base && segmentLabels[seg]) crumbs.push({ label: segmentLabels[seg], to: `/${segs.slice(0, i + 1).join("/")}` });
    });
  }

  const toggleMobileMenu = () => setMobileMenuOpen(!mobileMenuOpen);
  const closeMobileMenu = () => setMobileMenuOpen(false);
  const toggleGroup = (groupLabel: string) => {
    setCollapsedGroups((prev) => ({ ...prev, [groupLabel]: !prev[groupLabel] }));
  };

  const formatRole = (role: Role) => {
    return role === "super_admin" ? "Super Admin" : "Admin";
  };

  return (
    <div className="app-shell">
      {/* Mobile Overlay */}
      <div 
        className={`mobile-overlay ${mobileMenuOpen ? 'active' : ''}`}
        onClick={closeMobileMenu}
      />

      <aside className={`sidebar ${mobileMenuOpen ? 'mobile-open' : ''}`}>
        <div className="brand">
          <div className="brand-mark" style={{ background: "transparent", padding: 0, borderRadius: 0, overflow: "visible", boxShadow: "none" }}>
            <img src="/favicon-admin.png" alt="LexiLingo" style={{ width: "100%", height: "100%", objectFit: "contain", display: "block" }} />
          </div>
          <div>
            <div className="brand-title">LexiLingo</div>
            <div className="brand-sub">{formatRole(role)}</div>
          </div>
        </div>

        <div className="nav-section">
          <div className="nav-title">{t.appShell.navigation}</div>
          {navItems.length > 8 && (
            <div className="nav-filter-wrap">
              <input
                type="search"
                className="nav-filter-input"
                placeholder={t.appShell.filterNav}
                aria-label={t.appShell.filterNav}
                value={navFilter}
                onChange={(e) => setNavFilter(e.target.value)}
              />
            </div>
          )}
          <nav className="nav-links">
            {sections.map((section, i) => {
              const hasActiveItem = section.items.some(
                (item) => pathname === item.to || pathname.startsWith(`${item.to}/`)
              );
              const isCollapsed =
                !!section.label &&
                !normalizedFilter &&
                !hasActiveItem &&
                !!collapsedGroups[section.label];
              return (
                <div className="nav-group" key={section.label ?? i} role="group" aria-label={section.label}>
                  {section.label && (
                    <button
                      type="button"
                      className="nav-group-toggle"
                      aria-expanded={!isCollapsed}
                      onClick={() => toggleGroup(section.label!)}
                    >
                      <span>{section.label}</span>
                      <span aria-hidden="true">{isCollapsed ? "+" : "−"}</span>
                    </button>
                  )}
                  {!isCollapsed &&
                    section.items.map((item) => (
                      <NavLink
                        key={item.to}
                        to={item.to}
                        end={item.to === "/admin" || item.to === "/super"}
                        className={({ isActive }) => (isActive ? "nav-link active" : "nav-link")}
                        onClick={closeMobileMenu}
                      >
                        {item.icon && <span className="nav-icon">{item.icon}</span>}
                        <span className="nav-label">{item.label}</span>
                        {item.badge && <span className="nav-badge">{item.badge}</span>}
                      </NavLink>
                    ))}
                </div>
              );
            })}
          </nav>
        </div>

        <div className="sidebar-footer">
          <div className="user-card">
            <div className="user-avatar" aria-hidden="true">
              {user?.username?.slice(0, 2).toUpperCase() || "AD"}
            </div>
            <div className="user-info">
              <div className="user-name">{user?.display_name || user?.username}</div>
              <div className="user-email">{user?.email}</div>
            </div>
          </div>
          <button className="ghost-button logout-button" onClick={signOut}>
            {t.appShell.logout}
          </button>
        </div>
      </aside>

      <main className="main">
        <header className="topbar">
          <button
            className={`mobile-menu-btn ${mobileMenuOpen ? 'active' : ''}`}
            onClick={toggleMobileMenu}
            aria-label={t.appShell.toggleMenu}
            aria-expanded={mobileMenuOpen}
          >
            <span></span>
            <span></span>
            <span></span>
          </button>
          <span className="topbar-brand">LexiLingo</span>
          {crumbs.length > 1 && (
            <nav className="breadcrumb" aria-label={t.appShell.breadcrumb}>
              <ol>
                {crumbs.map((crumb, i) => (
                  <li key={`${crumb.label}-${i}`}>
                    {i === crumbs.length - 1 ? (
                      <span aria-current="page">{crumb.label}</span>
                    ) : crumb.to ? (
                      <Link to={crumb.to}>{crumb.label}</Link>
                    ) : (
                      <span>{crumb.label}</span>
                    )}
                  </li>
                ))}
              </ol>
            </nav>
          )}
          <div className="topbar-actions">
            <div className="locale-toggle" role="group" aria-label={t.appShell.switchLanguage}>
              <button
                type="button"
                className={`locale-toggle__btn ${locale === "en" ? "active" : ""}`}
                aria-pressed={locale === "en"}
                onClick={() => setLocale("en")}
              >
                EN
              </button>
              <button
                type="button"
                className={`locale-toggle__btn ${locale === "vi" ? "active" : ""}`}
                aria-pressed={locale === "vi"}
                onClick={() => setLocale("vi")}
              >
                VI
              </button>
            </div>
            <ThemeToggle />
          </div>
        </header>

        <div className="page">
          <Outlet />
        </div>
      </main>
    </div>
  );
};
