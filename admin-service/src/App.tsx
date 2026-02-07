import React from "react";
import { Routes, Route } from "react-router-dom";
import { I18nProvider, useI18n } from "./lib/i18n";
import { AuthProvider } from "./components/AuthProvider";
import { RequireAuth } from "./components/RequireAuth";
import { RequireRole } from "./components/RequireRole";
import { AppShell, NavItem } from "./components/AppShell";
import {
  LayoutDashboard, Users, BookOpen, Layers, FileText,
  PenTool, BarChart3, Languages, Trophy, ShoppingBag,
  Megaphone, ScrollText, Activity, Settings,
  Shield, Database, Bot, ArrowRight
} from "lucide-react";
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
import UserManagementPage from "./pages/UserManagementPage";
import { AdsPage } from "./pages/AdsPage";
import { LogsPage } from "./pages/LogsPage";
import { MonitoringPage } from "./pages/MonitoringPage";
import { ContentLabPage } from "./pages/ContentLabPage";
import { DatabasePage } from "./pages/DatabasePage";
import { AiModelsPage } from "./pages/AiModelsPage";
import { ContentAnalyticsPage } from "./pages/ContentAnalyticsPage";
import { SystemSettingsPage } from "./pages/SystemSettingsPage";
import { AdminManagementPage } from "./pages/AdminManagementPage";
import { AiChatSettingsPage } from "./pages/AiChatSettingsPage";
import { NoAccessPage } from "./pages/NoAccessPage";
import { NotFoundPage } from "./pages/NotFoundPage";

const AppRoutes = () => {
  const { t } = useI18n();

  const adminNav: NavItem[] = [
    { to: "/admin", label: t.nav.dashboard, icon: <LayoutDashboard size={18} /> },
    { to: "/admin/users", label: t.nav.userManagement, icon: <Users size={18} /> },
    { to: "/admin/courses", label: t.nav.courses, icon: <BookOpen size={18} /> },
    { to: "/admin/units", label: t.nav.units, icon: <Layers size={18} /> },
    { to: "/admin/lessons", label: t.nav.lessons, icon: <FileText size={18} /> },
    { to: "/admin/content-lab", label: t.nav.grammarTest, icon: <PenTool size={18} /> },
    { to: "/admin/content-analytics", label: t.nav.contentAnalytics, icon: <BarChart3 size={18} /> },
    { to: "/admin/vocabulary", label: t.nav.vocabulary, icon: <Languages size={18} /> },
    { to: "/admin/achievements", label: t.nav.achievements, icon: <Trophy size={18} /> },
    { to: "/admin/shop", label: t.nav.shop, icon: <ShoppingBag size={18} /> },
    { to: "/admin/ads", label: t.nav.bannerAds, icon: <Megaphone size={18} /> },
    { to: "/admin/logs", label: t.nav.logs, icon: <ScrollText size={18} /> },
    { to: "/admin/monitoring", label: t.nav.monitoring, icon: <Activity size={18} /> },
    { to: "/admin/settings", label: t.nav.settings, icon: <Settings size={18} /> },
  ];

  const superNav: NavItem[] = [
    { to: "/super", label: t.nav.superDashboard, icon: <Shield size={18} /> },
    { to: "/super/admins", label: "Admin Management", icon: <Users size={18} /> },
    { to: "/super/ai-chat", label: "AI Chat Config", icon: <Bot size={18} /> },
    { to: "/super/db", label: t.nav.database, icon: <Database size={18} /> },
    { to: "/super/ai-models", label: t.nav.aiModels, icon: <Bot size={18} /> },
    { to: "/admin", label: t.nav.adminZone, icon: <ArrowRight size={18} /> },
  ];

  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route path="/no-access" element={<NoAccessPage />} />

      <Route element={<RequireAuth />}>
        <Route path="/" element={<RoleRedirectPage />} />

        <Route element={<RequireRole allowed={["admin", "super_admin"]} />}>
          <Route element={<AppShell title={t.appShell.adminDashboard} role="admin" navItems={adminNav} />}>
            <Route path="/admin" element={<EnhancedAdminDashboard />} />
            <Route path="/admin/users" element={<UserManagementPage />} />
            <Route path="/admin/courses" element={<CoursesPage />} />
            <Route path="/admin/courses/:courseId/units" element={<UnitsPage />} />
            <Route path="/admin/courses/:courseId/units/:unitId/lessons" element={<LessonsPage />} />
            <Route path="/admin/units" element={<UnitsPage />} />
            <Route path="/admin/lessons" element={<LessonsPage />} />
            <Route path="/admin/content-lab" element={<ContentLabPage />} />
            <Route path="/admin/content-analytics" element={<ContentAnalyticsPage />} />
            <Route path="/admin/vocabulary" element={<VocabularyPage />} />
            <Route path="/admin/achievements" element={<AchievementsPage />} />
            <Route path="/admin/shop" element={<ShopPage />} />
            <Route path="/admin/ads" element={<AdsPage />} />
            <Route path="/admin/logs" element={<LogsPage />} />
            <Route path="/admin/monitoring" element={<MonitoringPage />} />
            <Route path="/admin/settings" element={<SystemSettingsPage />} />
          </Route>
        </Route>

        <Route element={<RequireRole allowed={["super_admin"]} />}>
          <Route element={<AppShell title={t.appShell.superAdmin} role="super_admin" navItems={superNav} />}>
            <Route path="/super" element={<SuperAdminDashboard />} />
            <Route path="/super/admins" element={<AdminManagementPage />} />
            <Route path="/super/ai-chat" element={<AiChatSettingsPage />} />
            <Route path="/super/db" element={<DatabasePage />} />
            <Route path="/super/ai-models" element={<AiModelsPage />} />
          </Route>
        </Route>
      </Route>

      <Route path="*" element={<NotFoundPage />} />
    </Routes>
  );
};

const App = () => {
  return (
    <I18nProvider>
      <AuthProvider>
        <AppRoutes />
      </AuthProvider>
    </I18nProvider>
  );
};

export default App;
