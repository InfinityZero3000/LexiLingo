import { apiFetch } from "./api";
import { ENV } from "./env";
import exerciseTypesContract from "../../../contracts/content-agent/exercise-types-v1.json";

export type AdminResponse<T> = {
  success: boolean;
  message?: string;
  data?: T;
  error?: string;
};

const asAdminResponse = <T>(payload: T | AdminResponse<T>): AdminResponse<T> => {
  if (
    payload &&
    typeof payload === "object" &&
    ("success" in payload || "data" in payload || "error" in payload)
  ) {
    return payload as AdminResponse<T>;
  }

  return {
    success: true,
    data: payload as T,
  };
};

export type AdminUser = {
  id: string;
  email: string;
  username: string;
  display_name?: string | null;
  is_active: boolean;
  is_verified: boolean;
  role_slug: string;
  role_level: number;
  created_at: string;
  last_login?: string | null;
};

export type RoleInfo = {
  id: string;
  name: string;
  slug: string;
  level: number;
};

export const listUsers = async (search?: string) => {
  const url = new URL(`${ENV.backendUrl}/admin/users`);
  url.searchParams.set("limit", "100");
  url.searchParams.set("offset", "0");
  if (search) url.searchParams.set("search", search);
  return apiFetch<AdminResponse<AdminUser[]>>(url.toString());
};

export const updateUser = async (userId: string, payload: { role_slug?: string; is_active?: boolean; display_name?: string }) => {
  return apiFetch<AdminResponse<AdminUser>>(`${ENV.backendUrl}/admin/users/${userId}`, {
    method: "PATCH",
    body: JSON.stringify(payload)
  });
};

export const listRoles = async () => {
  return apiFetch<AdminResponse<RoleInfo[]>>(`${ENV.backendUrl}/admin/roles`);
};

// ============================================================================
// Topic Chat Management (AI Service Admin)
// ============================================================================

export type TopicDifficulty = "A1" | "A2" | "B1" | "B2" | "C1" | "C2";

export type TopicItem = {
  story_id: string;
  title: { en: string; vi: string };
  difficulty_level: TopicDifficulty;
  category: string;
  estimated_minutes: number;
  icon_key?: string | null;
  suggested_prompts?: string[];
  tags?: string[];
};

export type TopicsAdminPayload = {
  topics: TopicItem[];
  total: number;
};

const aiAdminHeaders = () => ({
  ...(ENV.aiAdminApiKey ? { "X-Admin-Key": ENV.aiAdminApiKey } : {}),
});

export const listTopicStoriesAdmin = async () =>
  apiFetch<AdminResponse<TopicsAdminPayload>>(`${ENV.aiAdminUrl}/topics?limit=200`, {
    headers: aiAdminHeaders(),
  });

export const createTopicStoryAdmin = async (payload: {
  story_id?: string;
  title: { en: string; vi: string };
  difficulty_level: TopicDifficulty;
  category: string;
  estimated_minutes: number;
  icon_key?: string;
  opening_prompt?: string;
  suggested_prompts?: string[];
  tags?: string[];
  is_published?: boolean;
}) =>
  apiFetch<AdminResponse<TopicItem>>(`${ENV.aiAdminUrl}/topics`, {
    method: "POST",
    headers: aiAdminHeaders(),
    body: JSON.stringify(payload),
  });

// Grammar
export type GrammarItem = {
  id: string;
  title: string;
  level: string;
  topic?: string | null;
  summary?: string | null;
  content: string;
  examples?: any[] | null;
  tags?: string[] | null;
  is_active: boolean;
};

export const listGrammar = async () =>
  apiFetch<AdminResponse<GrammarItem[]>>(`${ENV.backendUrl}/admin/grammar?limit=100&offset=0`);

export const createGrammar = async (payload: Partial<GrammarItem>) =>
  apiFetch<AdminResponse<GrammarItem>>(`${ENV.backendUrl}/admin/grammar`, {
    method: "POST",
    body: JSON.stringify(payload)
  });

export const updateGrammar = async (id: string, payload: Partial<GrammarItem>) =>
  apiFetch<AdminResponse<GrammarItem>>(`${ENV.backendUrl}/admin/grammar/${id}`, {
    method: "PUT",
    body: JSON.stringify(payload)
  });

export const deleteGrammar = async (id: string) =>
  apiFetch<AdminResponse<{ deleted: boolean }>>(`${ENV.backendUrl}/admin/grammar/${id}`, {
    method: "DELETE"
  });

export const bulkImportGrammar = async (file: File) => {
  const formData = new FormData();
  formData.append("file", file);
  return apiFetch<AdminResponse<{ created: number; skipped: number; errors: string[] }>>(
    `${ENV.backendUrl}/admin/grammar/bulk-import`,
    { method: "POST", body: formData }
  );
};

// Questions
export type QuestionItem = {
  id: string;
  prompt: string;
  question_type: string;
  options?: any[] | null;
  answer?: any | null;
  explanation?: string | null;
  difficulty_level: string;
  tags?: string[] | null;
  grammar_id?: string | null;
  is_active: boolean;
};

export const listQuestions = async () =>
  apiFetch<AdminResponse<QuestionItem[]>>(`${ENV.backendUrl}/admin/questions?limit=100&offset=0`);

export const createQuestion = async (payload: Partial<QuestionItem>) =>
  apiFetch<AdminResponse<QuestionItem>>(`${ENV.backendUrl}/admin/questions`, {
    method: "POST",
    body: JSON.stringify(payload)
  });

export const updateQuestion = async (id: string, payload: Partial<QuestionItem>) =>
  apiFetch<AdminResponse<QuestionItem>>(`${ENV.backendUrl}/admin/questions/${id}`, {
    method: "PUT",
    body: JSON.stringify(payload)
  });

export const deleteQuestion = async (id: string) =>
  apiFetch<AdminResponse<{ deleted: boolean }>>(`${ENV.backendUrl}/admin/questions/${id}`, {
    method: "DELETE"
  });

export const bulkImportQuestions = async (file: File) => {
  const formData = new FormData();
  formData.append("file", file);
  return apiFetch<AdminResponse<{ created: number; skipped: number; errors: string[] }>>(
    `${ENV.backendUrl}/admin/questions/bulk-import`,
    { method: "POST", body: formData }
  );
};

// Test exams
export type TestExam = {
  id: string;
  title: string;
  description?: string | null;
  level: string;
  duration_minutes: number;
  passing_score: number;
  question_ids?: string[] | null;
  is_published: boolean;
};

export const listTestExams = async () =>
  apiFetch<AdminResponse<TestExam[]>>(`${ENV.backendUrl}/admin/test-exams?limit=100&offset=0`);

export const createTestExam = async (payload: Partial<TestExam>) =>
  apiFetch<AdminResponse<TestExam>>(`${ENV.backendUrl}/admin/test-exams`, {
    method: "POST",
    body: JSON.stringify(payload)
  });

export const updateTestExam = async (id: string, payload: Partial<TestExam>) =>
  apiFetch<AdminResponse<TestExam>>(`${ENV.backendUrl}/admin/test-exams/${id}`, {
    method: "PUT",
    body: JSON.stringify(payload)
  });

export const deleteTestExam = async (id: string) =>
  apiFetch<AdminResponse<{ deleted: boolean }>>(`${ENV.backendUrl}/admin/test-exams/${id}`, {
    method: "DELETE"
  });

export const bulkImportTestExams = async (file: File) => {
  const formData = new FormData();
  formData.append("file", file);
  return apiFetch<AdminResponse<{ created: number; skipped: number; errors: string[] }>>(
    `${ENV.backendUrl}/admin/test-exams/bulk-import`,
    { method: "POST", body: formData }
  );
};

// ============================================================================
// Achievement Management
// ============================================================================

export type AchievementItem = {
  id: string;
  slug?: string | null;
  name: string;
  description: string;
  condition_type: string;
  condition_value?: number;
  category: string;
  rarity: string;
  xp_reward: number;
  gems_reward: number;
  is_hidden: boolean;
  badge_icon?: string | null;
  badge_color?: string | null;
};

export const listAchievements = async () =>
  apiFetch<AdminResponse<AchievementItem[]>>(`${ENV.backendUrl}/admin/achievements`);

export const createAchievement = async (params: {
  name: string;
  description: string;
  condition_type: string;
  condition_value?: number;
  category?: string;
  rarity?: string;
  xp_reward?: number;
  gems_reward?: number;
  is_hidden?: boolean;
  badge_icon?: string;
  badge_color?: string;
  slug?: string;
}) => {
  const url = new URL(`${ENV.backendUrl}/admin/achievements`);
  Object.entries(params).forEach(([k, v]) => { if (v !== undefined) url.searchParams.set(k, String(v)); });
  return apiFetch<AdminResponse<AchievementItem>>(url.toString(), { method: "POST" });
};

export const updateAchievement = async (id: string, params: Partial<AchievementItem>) => {
  const url = new URL(`${ENV.backendUrl}/admin/achievements/${id}`);
  Object.entries(params).forEach(([k, v]) => { if (v !== undefined && v !== null) url.searchParams.set(k, String(v)); });
  return apiFetch<AdminResponse<AchievementItem>>(url.toString(), { method: "PUT" });
};

export const deleteAchievement = async (id: string) =>
  apiFetch<AdminResponse<{ deleted: boolean }>>(`${ENV.backendUrl}/admin/achievements/${id}`, {
    method: "DELETE",
  });

export const uploadBadgeImage = async (file: File): Promise<AdminResponse<{ url: string; filename: string }>> => {
  const formData = new FormData();
  formData.append("file", file);
  return apiFetch<AdminResponse<{ url: string; filename: string }>>(
    `${ENV.backendUrl}/admin/upload/badge`,
    {
      method: "POST",
      body: formData,
    }
  );
};

// ============================================================================
// Shop Management
// ============================================================================

export type ShopItemEffects = Record<string, unknown>;

export type ShopItemType = {
  id: string;
  name: string;
  description: string;
  item_type: string;
  price_gems: number;
  is_available: boolean;
  stock_quantity?: number | null;
  icon_url?: string | null;
  effects?: ShopItemEffects | null;
};

export const listShopItems = async (includeUnavailable = true) =>
  apiFetch<AdminResponse<ShopItemType[]>>(
    `${ENV.backendUrl}/admin/shop?include_unavailable=${includeUnavailable}`
  );

export const createShopItem = async (params: {
  name: string;
  description: string;
  item_type: string;
  price_gems: number;
  is_available?: boolean;
  stock_quantity?: number;
  icon_url?: string;
  effects?: ShopItemEffects;
}) =>
  apiFetch<AdminResponse<ShopItemType>>(`${ENV.backendUrl}/admin/shop`, {
    method: "POST",
    body: JSON.stringify(params),
  });

export const updateShopItem = async (id: string, params: Partial<ShopItemType>) =>
  apiFetch<AdminResponse<ShopItemType>>(`${ENV.backendUrl}/admin/shop/${id}`, {
    method: "PUT",
    body: JSON.stringify(params),
  });

export const deleteShopItem = async (id: string) =>
  apiFetch<AdminResponse<{ deleted: boolean }>>(`${ENV.backendUrl}/admin/shop/${id}`, {
    method: "DELETE",
  });

// ============================================================================
// Course Management
// ============================================================================

export type CourseItem = {
  id: string;
  title: string;
  description?: string | null;
  language: string;
  level: string;
  tags?: string[];
  thumbnail_url?: string | null;
  total_lessons: number;
  total_xp: number;
  estimated_duration: number;
  is_published: boolean;
  created_at: string;
  updated_at: string;
};

export type CoursesPaginated = {
  courses: CourseItem[];
  total: number;
  page: number;
  page_size: number;
  total_pages: number;
};

export const listCoursesAdmin = async (params?: {
  page?: number;
  page_size?: number;
  search?: string;
  level?: string;
  is_published?: boolean;
}) => {
  const url = new URL(`${ENV.backendUrl}/admin/courses`);
  if (params?.page) url.searchParams.set("page", String(params.page));
  if (params?.page_size) url.searchParams.set("page_size", String(params.page_size));
  if (params?.search) url.searchParams.set("search", params.search);
  if (params?.level) url.searchParams.set("level", params.level);
  if (params?.is_published !== undefined) url.searchParams.set("is_published", String(params.is_published));
  return apiFetch<AdminResponse<CoursesPaginated>>(url.toString());
};

export const createCourse = async (payload: {
  title: string;
  description?: string;
  language: string;
  level: string;
  tags?: string[];
  thumbnail_url?: string;
  is_published?: boolean;
}) =>
  apiFetch<AdminResponse<CourseItem>>(`${ENV.backendUrl}/admin/courses`, {
    method: "POST",
    body: JSON.stringify(payload),
  });

export const updateCourse = async (id: string, payload: Partial<CourseItem>) =>
  apiFetch<AdminResponse<CourseItem>>(`${ENV.backendUrl}/admin/courses/${id}`, {
    method: "PUT",
    body: JSON.stringify(payload),
  });

export const deleteCourse = async (id: string) =>
  apiFetch<AdminResponse<{ deleted: boolean }>>(`${ENV.backendUrl}/admin/courses/${id}`, {
    method: "DELETE",
  });

export const bulkImportCourses = async (courses: unknown[]) =>
  apiFetch<AdminResponse<{ courses: number; units: number; lessons: number; errors: string[] }>>(
    `${ENV.backendUrl}/admin/courses/bulk-import`,
    { method: "POST", body: JSON.stringify({ courses }) }
  );

// ============================================================================
// Unit Management
// ============================================================================

export type UnitItem = {
  id: string;
  course_id: string;
  title: string;
  description?: string | null;
  order_index: number;
  background_color?: string | null;
  icon_url?: string | null;
  total_lessons: number;
  created_at: string;
  updated_at: string;
};

export const listUnitsAdmin = async (courseId?: string, search?: string) => {
  const url = new URL(`${ENV.backendUrl}/admin/units`);
  if (courseId) url.searchParams.set("course_id", courseId);
  if (search) url.searchParams.set("search", search);
  return apiFetch<AdminResponse<UnitItem[]>>(url.toString());
};

export const createUnit = async (payload: {
  course_id: string;
  title: string;
  description?: string;
  order_index: number;
  background_color?: string;
  icon_url?: string;
}) =>
  apiFetch<AdminResponse<UnitItem>>(`${ENV.backendUrl}/admin/units`, {
    method: "POST",
    body: JSON.stringify(payload),
  });

export const updateUnit = async (id: string, payload: Partial<UnitItem>) =>
  apiFetch<AdminResponse<UnitItem>>(`${ENV.backendUrl}/admin/units/${id}`, {
    method: "PUT",
    body: JSON.stringify(payload),
  });

export const deleteUnit = async (id: string) =>
  apiFetch<AdminResponse<{ deleted: boolean }>>(`${ENV.backendUrl}/admin/units/${id}`, {
    method: "DELETE",
  });

// ============================================================================
// Exercise Types
// ============================================================================

export type UiType = keyof typeof exerciseTypesContract.ui_type_to_type;

export const UI_TYPES = Object.keys(
  exerciseTypesContract.ui_type_to_type,
) as UiType[];

export const UI_TYPE_LABELS: Record<UiType, string> = {
  multiple_choice: "Multiple Choice",
  true_or_false: "True or False",
  fill_in_the_blank: "Fill in the Blank",
  arrange_the_sentence: "Arrange the Sentence",
  translation_choice: "Translation Choice",
  dialogue_completion: "Dialogue Completion",
  collocation_choice: "Collocation Choice",
  dictation: "Dictation",
  grammar_correction: "Grammar Correction",
  image_based_choice: "Image Based Choice",
  listen_and_choose: "Listen and Choose",
  match_word_to_meaning: "Match Word to Meaning",
  vocabulary_flashcard: "Vocabulary Flashcard",
  pronunciation_practice: "Pronunciation Practice",
  reading_comprehension: "Reading Comprehension",
  short_writing_answer: "Short Writing Answer",
  speaking_repeat: "Speaking Repeat",
  categorization: "Categorization",
  cognitive_fluidity: "Cognitive Fluidity",
};

export const UI_TYPE_TO_TYPE = exerciseTypesContract.ui_type_to_type as Record<
  UiType,
  string
>;

export type ExerciseOption = {
  id: string;
  text: string;
  is_correct: boolean;
};

export type Exercise = {
  id: string;
  type: string;
  ui_type: string;
  question: string;
  options?: ExerciseOption[] | null;
  correct_answer: string;
  explanation?: string | null;
  hint?: string | null;
  audio_url?: string | null;
  image_url?: string | null;
  difficulty: number;
  points: number;
};

export type LessonContent = {
  exercises: Exercise[];
};

// ============================================================================
// Lesson Management
// ============================================================================

export type LessonItem = {
  id: string;
  unit_id: string;
  title: string;
  description?: string | null;
  outcome?: string | null;
  order_index: number;
  lesson_type: string;
  xp_reward: number;
  pass_threshold: number;
  total_exercises: number;
  estimated_minutes?: number;
  prerequisites: string[];
  created_at: string;
  updated_at: string;
};

export type LessonDetail = LessonItem & {
  content?: LessonContent | null;
};

export const listLessonsAdmin = async (params: { unit_id?: string; course_id?: string }) => {
  const url = new URL(`${ENV.backendUrl}/admin/lessons`);
  if (params.unit_id) url.searchParams.set("unit_id", params.unit_id);
  if (params.course_id) url.searchParams.set("course_id", params.course_id);
  return apiFetch<AdminResponse<LessonItem[]>>(url.toString());
};

export const createLesson = async (payload: {
  unit_id: string;
  title: string;
  description?: string;
  outcome?: string;
  order_index: number;
  lesson_type: string;
  xp_reward?: number;
  pass_threshold?: number;
  prerequisites?: string[];
}) =>
  apiFetch<AdminResponse<LessonItem>>(`${ENV.backendUrl}/admin/lessons`, {
    method: "POST",
    body: JSON.stringify(payload),
  });

export const updateLesson = async (id: string, payload: Partial<LessonItem>) =>
  apiFetch<AdminResponse<LessonItem>>(`${ENV.backendUrl}/admin/lessons/${id}`, {
    method: "PUT",
    body: JSON.stringify(payload),
  });

export const deleteLesson = async (id: string) =>
  apiFetch<AdminResponse<{ deleted: boolean }>>(`${ENV.backendUrl}/admin/lessons/${id}`, {
    method: "DELETE",
  });

export const getLessonDetail = async (id: string) =>
  apiFetch<AdminResponse<LessonDetail>>(`${ENV.backendUrl}/admin/lessons/${id}`);

export const updateLessonContent = async (
  id: string,
  exercises: Exercise[],
  estimatedMinutes: number
) =>
  apiFetch<AdminResponse<LessonDetail>>(`${ENV.backendUrl}/admin/lessons/${id}/content`, {
    method: "PUT",
    body: JSON.stringify({
      content: { exercises },
      estimated_minutes: estimatedMinutes,
      total_exercises: exercises.length,
    }),
  });

// ============================================================================
// Vocabulary Management
// ============================================================================

export type VocabItem = {
  id: string;
  word: string;
  definition?: string;
  translation?: Record<string, string>;
  part_of_speech: string;
  pronunciation?: string;
  difficulty_level: string;
};

export const listVocabulary = async (limit = 100, offset = 0) =>
  apiFetch<AdminResponse<VocabItem[]>>(`${ENV.backendUrl}/admin/vocabulary?limit=${limit}&offset=${offset}`);

export const createVocabulary = async (params: {
  word: string;
  definition: string;
  translation: string;
  part_of_speech?: string;
  pronunciation?: string;
  difficulty_level?: string;
}) => {
  const url = new URL(`${ENV.backendUrl}/admin/vocabulary`);
  Object.entries(params).forEach(([k, v]) => { if (v) url.searchParams.set(k, v); });
  return apiFetch<AdminResponse<VocabItem>>(url.toString(), { method: "POST" });
};

export const updateVocabulary = async (id: string, params: Partial<{
  word: string;
  definition: string;
  translation: string;
  part_of_speech: string;
  pronunciation: string;
  difficulty_level: string;
}>) => {
  const url = new URL(`${ENV.backendUrl}/admin/vocabulary/${id}`);
  Object.entries(params).forEach(([k, v]) => { if (v !== undefined) url.searchParams.set(k, v); });
  return apiFetch<AdminResponse<VocabItem>>(url.toString(), { method: "PUT" });
};

export const deleteVocabulary = async (id: string) =>
  apiFetch<AdminResponse<{ deleted: boolean }>>(`${ENV.backendUrl}/admin/vocabulary/${id}`, {
    method: "DELETE",
  });

export const bulkImportVocabulary = async (file: File) => {
  const formData = new FormData();
  formData.append("file", file);
  return apiFetch<AdminResponse<{ created: number; skipped: number; errors: string[] }>>(
    `${ENV.backendUrl}/admin/vocabulary/bulk-import`,
    { method: "POST", body: formData }
  );
};

export const extractPdfText = async (file: File) => {
  const formData = new FormData();
  formData.append("file", file);
  return apiFetch<AdminResponse<{ text: string }>>(
    `${ENV.backendUrl}/admin/import/extract-pdf-text`,
    { method: "POST", body: formData }
  );
};

// ============================================================================
// Content Analytics
// ============================================================================

export type ContentPerformance = {
  courses: Array<{
    course_id: string;
    course_title: string;
    enrollments: number;
    completions: number;
    completion_rate: number;
    avg_score: number;
    avg_time_minutes: number;
  }>;
  lessons: Array<{
    lesson_id: string;
    lesson_title: string;
    attempts: number;
    completions: number;
    avg_score: number;
  }>;
};

export type VocabEffectiveness = {
  total_words: number;
  avg_mastery_rate: number;
  avg_reviews_to_master: number;
  hardest_words: Array<{
    word: string;
    mastery_rate: number;
    avg_reviews: number;
  }>;
};

export const getContentPerformance = async () =>
  asAdminResponse(
    await apiFetch<ContentPerformance | AdminResponse<ContentPerformance>>(
      `${ENV.backendUrl}/admin/analytics/content-performance`
    )
  );

export const getVocabEffectiveness = async () =>
  asAdminResponse(
    await apiFetch<VocabEffectiveness | AdminResponse<VocabEffectiveness>>(
      `${ENV.backendUrl}/admin/analytics/vocabulary-effectiveness`
    )
  );

// ============================================================================
// System Info
// ============================================================================

export type SystemInfo = {
  app_name: string;
  app_env: string;
  debug: boolean;
  api_prefix: string;
  log_level: string;
  token_expire_minutes: number;
  refresh_token_days: number;
  cors_origins: string[];
  ai_service_url: string;
  google_oauth: boolean;
  firebase: boolean;
  totals: {
    users: number;
    courses: number;
    vocabulary: number;
    achievements: number;
  };
};

export const getSystemInfo = async () =>
  apiFetch<AdminResponse<SystemInfo>>(`${ENV.backendUrl}/admin/system-info`);

export type SystemInfoUpdatePayload = {
  app_name?: string;
  debug?: boolean;
  log_level?: string;
  token_expire_minutes?: number;
  refresh_token_days?: number;
  cors_origins?: string;
  ai_service_url?: string;
};

export const updateSystemInfo = async (payload: SystemInfoUpdatePayload) =>
  apiFetch<AdminResponse<SystemInfo>>(`${ENV.backendUrl}/admin/system-info`, {
    method: "PUT",
    body: JSON.stringify(payload),
  });
