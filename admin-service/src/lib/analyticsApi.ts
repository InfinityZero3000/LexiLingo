import { apiFetch } from "./api";
import { ENV } from "./env";
import { 
  UserGrowthData 
} from "../components/dashboard/UserGrowthChart";
import { 
  EngagementData 
} from "../components/dashboard/EngagementChart";
import { 
  CoursePopularityData 
} from "../components/dashboard/CoursePopularityChart";
import { 
  FunnelData 
} from "../components/dashboard/CompletionFunnelChart";

const base = () => `${ENV.backendUrl}/admin/analytics`;

/* ─── Dashboard Analytics ─────────────────────────────── */

export type DashboardKPIs = {
  total_users: number;
  active_users_7d: number;
  total_courses: number;
  total_lessons_completed_today: number;
  avg_dau_30d: number;
};

export const getDashboardKPIs = () =>
  apiFetch<{ kpis: DashboardKPIs }>(`${base()}/dashboard/kpis`);

export const getUserGrowth = (days: number = 30) =>
  apiFetch<{ data: UserGrowthData[] }>(`${base()}/dashboard/user-growth?days=${days}`);

export const getEngagement = (weeks: number = 12) =>
  apiFetch<{ data: EngagementData[] }>(`${base()}/dashboard/engagement?weeks=${weeks}`);

export const getCoursePopularity = () =>
  apiFetch<{ data: CoursePopularityData[] }>(`${base()}/dashboard/course-popularity`);

export const getCompletionFunnel = () =>
  apiFetch<{ data: FunnelData[] }>(`${base()}/dashboard/completion-funnel`);

/* ─── User Analytics ─────────────────────────────────── */

export type UserMetrics = {
  dau: number;
  wau: number;
  mau: number;
  total_signups: number;
  avg_session_duration: number;
};

export type RetentionCohort = {
  cohort_date: string;
  users: number;
  d1_retention: number;
  d7_retention: number;
  d30_retention: number;
};

export const getUserMetrics = (startDate?: string, endDate?: string) => {
  const params = new URLSearchParams();
  if (startDate) params.append("start_date", startDate);
  if (endDate) params.append("end_date", endDate);
  return apiFetch<{ metrics: UserMetrics }>(`${base()}/user-metrics?${params.toString()}`);
};

export const getRetentionCohorts = () =>
  apiFetch<{ cohorts: RetentionCohort[] }>(`${base()}/retention-cohorts`);

/* ─── Content Performance ─────────────────────────────── */

export type CoursePerformance = {
  course_id: string;
  course_title: string;
  enrollments: number;
  completions: number;
  completion_rate: number;
  avg_score: number;
  avg_time_minutes: number;
};

export type LessonDifficulty = {
  lesson_id: string;
  lesson_title: string;
  attempts: number;
  pass_rate: number;
  avg_attempts: number;
  difficulty_score: number;
};

export const getContentPerformance = () =>
  apiFetch<{ courses: CoursePerformance[]; lessons: LessonDifficulty[] }>(`${base()}/content-performance`);

/* ─── Vocabulary Effectiveness ─────────────────────────── */

export type VocabularyEffectiveness = {
  total_words: number;
  avg_mastery_rate: number;
  avg_reviews_to_master: number;
  hardest_words: Array<{
    word: string;
    mastery_rate: number;
    avg_reviews: number;
  }>;
};

export const getVocabularyEffectiveness = () =>
  apiFetch<VocabularyEffectiveness>(`${base()}/vocabulary-effectiveness`);
