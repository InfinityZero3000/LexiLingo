import { apiFetch } from "./api";
import { ENV } from "./env";

export type AdminResponse<T> = {
  success: boolean;
  message?: string;
  data?: T;
  error?: string;
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
