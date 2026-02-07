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

export const EnhancedAdminDashboard = () => {
  const { t } = useI18n();
  // Parallel data fetching - applying async-parallel pattern from React best practices
  const { data: kpisData, isLoading: kpisLoading, error: kpisError } = useQuery({
    queryKey: ["dashboard", "kpis"],
    queryFn: getDashboardKPIs,
    staleTime: 5 * 60 * 1000, // 5 minutes cache
  });

  const { data: statsData, isLoading: statsLoading } = useQuery({
    queryKey: ["dashboard", "stats"],
    queryFn: getDashboardStats,
    staleTime: 5 * 60 * 1000,
  });

  const { data: userGrowthData, isLoading: growthLoading } = useQuery({
    queryKey: ["dashboard", "user-growth", 30],
    queryFn: () => getUserGrowth(30),
    staleTime: 10 * 60 * 1000, // 10 minutes cache
  });

  const { data: engagementData, isLoading: engagementLoading } = useQuery({
    queryKey: ["dashboard", "engagement", 12],
    queryFn: () => getEngagement(12),
    staleTime: 10 * 60 * 1000,
  });

  const { data: popularityData, isLoading: popularityLoading } = useQuery({
    queryKey: ["dashboard", "course-popularity"],
    queryFn: getCoursePopularity,
    staleTime: 15 * 60 * 1000, // 15 minutes cache
  });

  const { data: funnelData, isLoading: funnelLoading } = useQuery({
    queryKey: ["dashboard", "completion-funnel"],
    queryFn: getCompletionFunnel,
    staleTime: 15 * 60 * 1000,
  });

  // Extract data with optional chaining
  const kpis = kpisData?.kpis;
  const stats = statsData?.dashboard;

  return (
    <div className="stack">
      {/* KPI Cards */}
      <div className="card-grid">
        <StatCard
          label={t.dashboard.totalUsers}
          value={kpisLoading ? "--" : (kpis?.total_users?.toLocaleString() ?? "--")}
          trend={kpisLoading ? undefined : `${kpis?.active_users_7d ?? 0} ${t.dashboard.activeUsers}`}
          note={kpisError ? t.common.loadFailed : undefined}
        />
        <StatCard
          label={t.dashboard.courses}
          value={kpisLoading ? "--" : String(kpis?.total_courses ?? "--")}
          trend={kpisLoading ? undefined : `${kpis?.total_lessons_completed_today ?? 0} ${t.dashboard.lessonsCompletedToday}`}
          accent="teal"
        />
        <StatCard
          label={t.dashboard.avgDau}
          value={kpisLoading ? "--" : (kpis?.avg_dau_30d?.toFixed(0) ?? "--")}
          trend={t.dashboard.dauDescription}
          accent="berry"
        />
        <StatCard
          label={t.dashboard.achievements}
          value={statsLoading ? "--" : String(stats?.total_achievements ?? "--")}
          trend={statsLoading ? undefined : `${stats?.total_unlocks ?? 0} ${t.dashboard.unlocked}`}
          accent="orange"
        />
      </div>

      {/* User Growth & Engagement Charts */}
      <div className="grid-2">
        <div className="panel">
          <SectionHeader
            title={t.dashboard.userGrowth}
            description={t.dashboard.userGrowthDesc}
          />
          <UserGrowthChart 
            data={userGrowthData?.data ?? []} 
            loading={growthLoading}
          />
        </div>

        <div className="panel">
          <SectionHeader
            title={t.dashboard.engagement}
            description={t.dashboard.engagementDesc}
          />
          <EngagementChart 
            data={engagementData?.data ?? []} 
            loading={engagementLoading}
          />
        </div>
      </div>

      {/* Course Analytics */}
      <div className="grid-2">
        <div className="panel">
          <SectionHeader
            title={t.dashboard.popularCourses}
            description={t.dashboard.popularCoursesDesc}
          />
          <CoursePopularityChart 
            data={popularityData?.data ?? []} 
            loading={popularityLoading}
          />
        </div>

        <div className="panel">
          <SectionHeader
            title={t.dashboard.courseFunnel}
            description={t.dashboard.courseFunnelDesc}
          />
          <CompletionFunnelChart 
            data={funnelData?.data ?? []} 
            loading={funnelLoading}
          />
        </div>
      </div>

      {/* Recent Activity (reuse existing from old dashboard) */}
      {stats && stats.recent_actions.length > 0 && (
        <div className="panel">
          <SectionHeader
            title={t.dashboard.recentActivity}
            description={t.dashboard.recentActivityDesc}
          />
          <div className="pill-grid">
            {stats.recent_actions.slice(0, 10).map((a, i) => {
              const date = new Date(a.created_at);
              return (
                <div className="pill-item" key={i}>
                  <div>
                    <div className="pill-title">{a.action}</div>
                    <div className="pill-desc">
                      {a.resource_type} • {date.toLocaleDateString("vi-VN")} {date.toLocaleTimeString("vi-VN", { hour: "2-digit", minute: "2-digit" })}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
};
