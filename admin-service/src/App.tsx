import React, { Suspense, lazy } from "react";
import { Routes, Route } from "react-router-dom";
import { I18nProvider, useI18n } from "./lib/i18n";
import { AuthProvider, useAuth } from "./components/AuthProvider";
import { RequireAuth } from "./components/RequireAuth";
import { RequireRole } from "./components/RequireRole";
import { AppShell, NavItem } from "./components/AppShell";
import {
  LayoutDashboard, Users, BookOpen, Layers, FileText,
  PenTool, BarChart3, Languages, Trophy, ShoppingBag,
  Megaphone, ScrollText, Activity, Settings,
  Shield, Database, Bot, ArrowRight, ArrowLeft, MessageSquare, Swords, Bell,
  ClipboardCheck, Gauge
} from "lucide-react";

// Lazy-loaded components
const LoginPage = lazy(() => import("./pages/LoginPage").then(m => ({ default: m.LoginPage })));
const RoleRedirectPage = lazy(() => import("./pages/RoleRedirectPage").then(m => ({ default: m.RoleRedirectPage })));
const EnhancedAdminDashboard = lazy(() => import("./pages/EnhancedAdminDashboard").then(m => ({ default: m.EnhancedAdminDashboard })));
const SuperAdminDashboard = lazy(() => import("./pages/SuperAdminDashboard").then(m => ({ default: m.SuperAdminDashboard })));
const CoursesPage = lazy(() => import("./pages/CoursesPage").then(m => ({ default: m.CoursesPage })));
const UnitsPage = lazy(() => import("./pages/UnitsPage").then(m => ({ default: m.UnitsPage })));
const LessonsPage = lazy(() => import("./pages/LessonsPage").then(m => ({ default: m.LessonsPage })));
const LessonExercisesPage = lazy(() => import("./pages/LessonExercisesPage").then(m => ({ default: m.LessonExercisesPage })));
const TopicsPage = lazy(() => import("./pages/TopicsPage").then(m => ({ default: m.TopicsPage })));
const VocabularyPage = lazy(() => import("./pages/VocabularyPage").then(m => ({ default: m.VocabularyPage })));
const AchievementsPage = lazy(() => import("./pages/AchievementsPage").then(m => ({ default: m.AchievementsPage })));
const ShopPage = lazy(() => import("./pages/ShopPage").then(m => ({ default: m.ShopPage })));
const UserManagementPage = lazy(() => import("./pages/UserManagementPage"));
const AdsPage = lazy(() => import("./pages/AdsPage").then(m => ({ default: m.AdsPage })));
const LogsPage = lazy(() => import("./pages/LogsPage").then(m => ({ default: m.LogsPage })));
const MonitoringPage = lazy(() => import("./pages/MonitoringPage").then(m => ({ default: m.MonitoringPage })));
const ContentLabPage = lazy(() => import("./pages/ContentLabPage").then(m => ({ default: m.ContentLabPage })));
const ContentQaQueuePage = lazy(() => import("./pages/ContentQaQueuePage").then(m => ({ default: m.ContentQaQueuePage })));
const DatabasePage = lazy(() => import("./pages/DatabasePage").then(m => ({ default: m.DatabasePage })));
const AiModelsPage = lazy(() => import("./pages/AiModelsPage").then(m => ({ default: m.AiModelsPage })));
const ContentAnalyticsPage = lazy(() => import("./pages/ContentAnalyticsPage").then(m => ({ default: m.ContentAnalyticsPage })));
const AiQualityDashboardPage = lazy(() => import("./pages/AiQualityDashboardPage").then(m => ({ default: m.AiQualityDashboardPage })));
const SystemSettingsPage = lazy(() => import("./pages/SystemSettingsPage").then(m => ({ default: m.SystemSettingsPage })));
const AdminManagementPage = lazy(() => import("./pages/AdminManagementPage").then(m => ({ default: m.AdminManagementPage })));
const AiChatSettingsPage = lazy(() => import("./pages/AiChatSettingsPage").then(m => ({ default: m.AiChatSettingsPage })));
const RankingAgentPage = lazy(() => import("./pages/RankingAgentPage").then(m => ({ default: m.RankingAgentPage })));
const NotificationCampaignPage = lazy(() => import("./pages/NotificationCampaignPage").then(m => ({ default: m.NotificationCampaignPage })));
const NoAccessPage = lazy(() => import("./pages/NoAccessPage").then(m => ({ default: m.NoAccessPage })));
const NotFoundPage = lazy(() => import("./pages/NotFoundPage").then(m => ({ default: m.NotFoundPage })));

const PageLoader = () => (
  <div className="flex items-center justify-center h-full p-8">
    <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
  </div>
);

const AppRoutes = () => {
  const { t } = useI18n();
  const { role } = useAuth();

  const adminNav: NavItem[] = [
    { to: "/admin", label: t.nav.dashboard, icon: <LayoutDashboard size={18} /> },
    { to: "/admin/users", label: t.nav.userManagement, icon: <Users size={18} /> },
    { to: "/admin/courses", label: t.nav.courses, icon: <BookOpen size={18} /> },
    { to: "/admin/units", label: t.nav.units, icon: <Layers size={18} /> },
    { to: "/admin/lessons", label: t.nav.lessons, icon: <FileText size={18} /> },
    { to: "/admin/topics", label: t.nav.topics, icon: <MessageSquare size={18} /> },
    { to: "/admin/content-lab", label: t.nav.grammarTest, icon: <PenTool size={18} /> },
    { to: "/admin/content-qa", label: t.nav.contentQaQueue, icon: <ClipboardCheck size={18} /> },
    { to: "/admin/content-analytics", label: t.nav.contentAnalytics, icon: <BarChart3 size={18} /> },
    { to: "/admin/ai-quality", label: t.nav.aiQuality, icon: <Gauge size={18} /> },
    { to: "/admin/vocabulary", label: t.nav.vocabulary, icon: <Languages size={18} /> },
    { to: "/admin/achievements", label: t.nav.achievements, icon: <Trophy size={18} /> },
    { to: "/admin/shop", label: t.nav.shop, icon: <ShoppingBag size={18} /> },
    { to: "/admin/ranking-agent", label: t.nav.rankingAgent, icon: <Swords size={18} /> },
    { to: "/admin/notification-campaign", label: t.nav.notificationCampaign, icon: <Bell size={18} /> },
    { to: "/admin/ads", label: t.nav.bannerAds, icon: <Megaphone size={18} /> },
    { to: "/admin/logs", label: t.nav.logs, icon: <ScrollText size={18} /> },
    { to: "/admin/monitoring", label: t.nav.monitoring, icon: <Activity size={18} /> },
    { to: "/admin/settings", label: t.nav.settings, icon: <Settings size={18} /> },
    // Conditionally add "Back to Super Admin" for super_admin users
    ...(role === "super_admin" ? [{ to: "/super", label: t.nav.superDashboard, icon: <ArrowLeft size={18} /> }] : []),
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
    <Suspense fallback={<PageLoader />}>
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
              <Route path="/admin/courses/:courseId/units/:unitId/lessons/:lessonId/exercises" element={<LessonExercisesPage />} />
              <Route path="/admin/units" element={<UnitsPage />} />
              <Route path="/admin/lessons" element={<LessonsPage />} />
              <Route path="/admin/topics" element={<TopicsPage />} />
              <Route path="/admin/content-lab" element={<ContentLabPage />} />
              <Route path="/admin/content-qa" element={<ContentQaQueuePage />} />
              <Route path="/admin/content-analytics" element={<ContentAnalyticsPage />} />
              <Route path="/admin/ai-quality" element={<AiQualityDashboardPage />} />
              <Route path="/admin/vocabulary" element={<VocabularyPage />} />
              <Route path="/admin/achievements" element={<AchievementsPage />} />
              <Route path="/admin/shop" element={<ShopPage />} />
              <Route path="/admin/ranking-agent" element={<RankingAgentPage />} />
              <Route path="/admin/notification-campaign" element={<NotificationCampaignPage />} />
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
    </Suspense>
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
