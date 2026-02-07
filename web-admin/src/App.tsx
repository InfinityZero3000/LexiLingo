import React from "react";
import { Routes, Route } from "react-router-dom";
import { AuthProvider } from "./components/AuthProvider";
import { RequireAuth } from "./components/RequireAuth";
import { RequireRole } from "./components/RequireRole";
import { AppShell, NavItem } from "./components/AppShell";
import { LoginPage } from "./pages/LoginPage";
import { RoleRedirectPage } from "./pages/RoleRedirectPage";
import { AdminDashboard } from "./pages/AdminDashboard";
import { EnhancedAdminDashboard } from "./pages/EnhancedAdminDashboard";
import { SuperAdminDashboard } from "./pages/SuperAdminDashboard";
import { CoursesPage } from "./pages/CoursesPage";
import { UnitsPage } from "./pages/UnitsPage";
import { LessonsPage } from "./pages/LessonsPage";
import { VocabularyPage } from "./pages/VocabularyPage";
import { AchievementsPage } from "./pages/AchievementsPage";
import { ShopPage } from "./pages/ShopPage";
import { UsersPage } from "./pages/UsersPage";
import { AdsPage } from "./pages/AdsPage";
import { LogsPage } from "./pages/LogsPage";
import { MonitoringPage } from "./pages/MonitoringPage";
import { ContentLabPage } from "./pages/ContentLabPage";
import { DatabasePage } from "./pages/DatabasePage";
import { AiModelsPage } from "./pages/AiModelsPage";
import { NoAccessPage } from "./pages/NoAccessPage";
import { NotFoundPage } from "./pages/NotFoundPage";

const adminNav: NavItem[] = [
  { to: "/admin", label: "Dashboard" },
  { to: "/admin/courses", label: "Khóa học" },
  { to: "/admin/units", label: "Units" },
  { to: "/admin/lessons", label: "Lessons" },
  { to: "/admin/content-lab", label: "Ngữ pháp & Test" },
  { to: "/admin/vocabulary", label: "Từ vựng" },
  { to: "/admin/achievements", label: "Achievements" },
  { to: "/admin/shop", label: "Shop" },
  { to: "/admin/users", label: "Users" },
  { to: "/admin/ads", label: "Banner & Ads" },
  { to: "/admin/logs", label: "Logs" },
  { to: "/admin/monitoring", label: "Monitoring" }
];

const superNav: NavItem[] = [
  { to: "/super", label: "Super Dashboard" },
  { to: "/super/db", label: "Database" },
  { to: "/super/ai-models", label: "AI Models" },
  { to: "/admin", label: "Admin Zone" }
];

const App = () => {
  return (
    <AuthProvider>
      <Routes>
        <Route path="/login" element={<LoginPage />} />
        <Route path="/no-access" element={<NoAccessPage />} />

        <Route element={<RequireAuth />}>
          <Route path="/" element={<RoleRedirectPage />} />

          <Route element={<RequireRole allowed={["admin", "super_admin"]} />}>
            <Route element={<AppShell title="Admin Dashboard" role="admin" navItems={adminNav} />}>
              <Route path="/admin" element={<EnhancedAdminDashboard />} />
              <Route path="/admin/courses" element={<CoursesPage />} />
              <Route path="/admin/units" element={<UnitsPage />} />
              <Route path="/admin/lessons" element={<LessonsPage />} />
              <Route path="/admin/content-lab" element={<ContentLabPage />} />
              <Route path="/admin/vocabulary" element={<VocabularyPage />} />
              <Route path="/admin/achievements" element={<AchievementsPage />} />
              <Route path="/admin/shop" element={<ShopPage />} />
              <Route path="/admin/users" element={<UsersPage />} />
              <Route path="/admin/ads" element={<AdsPage />} />
              <Route path="/admin/logs" element={<LogsPage />} />
              <Route path="/admin/monitoring" element={<MonitoringPage />} />
            </Route>
          </Route>

          <Route element={<RequireRole allowed={["super_admin"]} />}>
            <Route element={<AppShell title="Super Admin" role="super_admin" navItems={superNav} />}>
              <Route path="/super" element={<SuperAdminDashboard />} />
              <Route path="/super/db" element={<DatabasePage />} />
              <Route path="/super/ai-models" element={<AiModelsPage />} />
            </Route>
          </Route>
        </Route>

        <Route path="*" element={<NotFoundPage />} />
      </Routes>
    </AuthProvider>
  );
};

export default App;
