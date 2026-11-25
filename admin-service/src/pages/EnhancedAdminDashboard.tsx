import React from "react";
import { useQuery } from "@tanstack/react-query";
import { StatCard } from "../components/StatCard";
import { SectionHeader } from "../components/SectionHeader";
import { UserGrowthChart } from "../components/dashboard/UserGrowthChart";
import { EngagementChart } from "../components/dashboard/EngagementChart";
import { CoursePopularityChart } from "../components/dashboard/CoursePopularityChart";
import { CompletionFunnelChart } from "../components/dashboard/CompletionFunnelChart";
import { getDashboardKPIs, getUserGrowth, getEngagement, getCoursePopularity, getCompletionFunnel } from "../lib/analyticsApi";
import { getDashboardStats } from "../lib/rbacApi";
import { useI18n } from "../lib/i18n";

const ACTIVITY_BADGE_COLORS = [
  { bg: "rgba(255, 77, 0, 0.14)", color: "#FF4D00" },
  { bg: "rgba(255, 122, 0, 0.14)", color: "#EA580C" },
  { bg: "rgba(251, 146, 60, 0.16)", color: "#C2410C" },
  { bg: "rgba(245, 158, 11, 0.14)", color: "#D97706" },
];

const getActivityBadgeStyle = (action: string, index: number) => {
  const lower = action.toLowerCase();
  if (lower.includes("delete") || lower.includes("remove") || lower.includes("ban")) {
    return { bg: "rgba(244, 63, 94, 0.14)", color: "#E11D48" };
  }
  if (lower.includes("create") || lower.includes("add") || lower.includes("approve")) {
    return { bg: "rgba(255, 122, 0, 0.14)", color: "#EA580C" };
  }
  if (lower.includes("update") || lower.includes("edit") || lower.includes("publish")) {
    return { bg: "rgba(255, 77, 0, 0.14)", color: "#FF4D00" };
  }
  return ACTIVITY_BADGE_COLORS[index % ACTIVITY_BADGE_COLORS.length];
};

export const EnhancedAdminDashboard = () => {
  const { t } = useI18n();
  // Parallel data fetching - applying async-parallel pattern from React best practices
  const { data: kpisData, isLoading: kpisLoading, error: kpisError } = useQuery({
    queryKey: ["dashboard", "kpis"],
    queryFn: getDashboardKPIs,
    staleTime: 5 * 60 * 1000, // 5 minutes cache
  });

  const { data: statsData, isLoading: statsLoading, error: statsError } = useQuery({
    queryKey: ["dashboard", "stats"],
    queryFn: getDashboardStats,
    staleTime: 5 * 60 * 1000,
  });

  const { data: userGrowthData, isLoading: growthLoading, error: growthError } = useQuery({
    queryKey: ["dashboard", "user-growth", 30],
    queryFn: () => getUserGrowth(30),
    staleTime: 10 * 60 * 1000, // 10 minutes cache
  });

  const { data: engagementData, isLoading: engagementLoading, error: engagementError } = useQuery({
    queryKey: ["dashboard", "engagement", 12],
    queryFn: () => getEngagement(12),
    staleTime: 10 * 60 * 1000,
  });

  const { data: popularityData, isLoading: popularityLoading, error: popularityError } = useQuery({
    queryKey: ["dashboard", "course-popularity"],
    queryFn: getCoursePopularity,
    staleTime: 15 * 60 * 1000, // 15 minutes cache
  });

  const { data: funnelData, isLoading: funnelLoading, error: funnelError } = useQuery({
    queryKey: ["dashboard", "completion-funnel"],
    queryFn: getCompletionFunnel,
    staleTime: 15 * 60 * 1000,
  });

  // Extract data with optional chaining
  const kpis = kpisData?.kpis;
  const stats = statsData?.dashboard;

  return (
    <div className="stack dashboard-view">
      {/* KPI Cards */}
      <div className="card-grid dashboard-card-grid">
        <StatCard
          label={t.dashboard.totalUsers}
          value={kpisLoading ? "--" : (kpis?.total_users?.toLocaleString() ?? "--")}
          loading={kpisLoading}
          trend={kpisLoading ? undefined : `${kpis?.active_users_7d ?? 0} ${t.dashboard.activeUsers}`}
          note={kpisError ? t.common.loadFailed : undefined}
          variant="blue"
        />
        <StatCard
          label={t.dashboard.courses}
          value={kpisLoading ? "--" : String(kpis?.total_courses ?? "--")}
          loading={kpisLoading}
          trend={kpisLoading ? undefined : `${kpis?.total_lessons_completed_today ?? 0} ${t.dashboard.lessonsCompletedToday}`}
          accent="teal"
        />
        <StatCard
          label={t.dashboard.avgDau}
          value={kpisLoading ? "--" : (kpis?.avg_dau_30d?.toFixed(0) ?? "--")}
          loading={kpisLoading}
          trend={t.dashboard.dauDescription}
          accent="berry"
        />
        <StatCard
          label={t.dashboard.achievements}
          value={statsLoading ? "--" : String(stats?.total_achievements ?? "--")}
          loading={statsLoading}
          trend={statsLoading ? undefined : `${stats?.total_unlocks ?? 0} ${t.dashboard.unlocked}`}
          note={statsError ? t.common.loadFailed : undefined}
          variant="dark"
          accent="orange"
        />
      </div>

      {/* User Growth & Engagement Charts */}
      <div className="grid-2 dashboard-grid-2">
        <div className="panel dashboard-chart-panel bento-card--dark">
          <SectionHeader
            title={t.dashboard.userGrowth}
            description={t.dashboard.userGrowthDesc}
          />
          <UserGrowthChart
            data={userGrowthData?.data ?? []}
            loading={growthLoading}
            error={!!growthError}
          />
        </div>

        <div className="panel dashboard-chart-panel">
          <SectionHeader
            title={t.dashboard.engagement}
            description={t.dashboard.engagementDesc}
          />
          <EngagementChart
            data={engagementData?.data ?? []}
            loading={engagementLoading}
            error={!!engagementError}
          />
        </div>
      </div>

      {/* Course Analytics */}
      <div className="grid-2 dashboard-grid-2">
        <div className="panel dashboard-chart-panel">
          <SectionHeader
            title={t.dashboard.popularCourses}
            description={t.dashboard.popularCoursesDesc}
          />
          <CoursePopularityChart
            data={popularityData?.data ?? []}
            loading={popularityLoading}
            error={!!popularityError}
          />
        </div>

        <div className="panel dashboard-chart-panel">
          <SectionHeader
            title={t.dashboard.courseFunnel}
            description={t.dashboard.courseFunnelDesc}
          />
          <CompletionFunnelChart
            data={funnelData?.data ?? []}
            loading={funnelLoading}
            error={!!funnelError}
          />
        </div>
      </div>

      {/* Recent Activity */}
      {stats && stats.recent_actions.length > 0 && (
        <div className="panel">
          <SectionHeader
            title={t.dashboard.recentActivity}
            description={t.dashboard.recentActivityDesc}
          />
          <div className="pill-grid">
            {stats.recent_actions.slice(0, 10).map((a, i) => {
              const date = new Date(a.created_at);
              const badge = getActivityBadgeStyle(a.action, i);
              const initial = (a.resource_type || a.action || "A").trim().slice(0, 1).toUpperCase();
              const timestamp = `${date.toLocaleDateString("vi-VN")} ${date.toLocaleTimeString("vi-VN", {
                hour: "2-digit",
                minute: "2-digit",
              })}`;

              return (
                <div className="pill-item" key={i} style={{ gap: 12 }}>
                  <div style={{ display: "flex", alignItems: "center", gap: 12, minWidth: 0 }}>
                    <span
                      aria-hidden="true"
                      style={{
                        width: 34,
                        height: 34,
                        borderRadius: "50%",
                        display: "inline-flex",
                        alignItems: "center",
                        justifyContent: "center",
                        flexShrink: 0,
                        fontWeight: 700,
                        fontSize: 13,
                        background: badge.bg,
                        color: badge.color,
                      }}
                    >
                      {initial}
                    </span>
                    <div style={{ minWidth: 0 }}>
                      <div className="pill-title" style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                        {a.action}
                      </div>
                      <div className="pill-desc">{a.resource_type}</div>
                    </div>
                  </div>
                  <span className="status-pill neutral" style={{ flexShrink: 0, fontVariantNumeric: "tabular-nums" }}>
                    {timestamp}
                  </span>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
};
