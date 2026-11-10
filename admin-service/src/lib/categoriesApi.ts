import { apiFetch } from "./api";
import { ENV } from "./env";

type Envelope<T> = { success: boolean; message?: string; data: T };

export type CourseCategory = {
  id: string;
  name: string;
  slug: string;
  description?: string | null;
  icon?: string | null;
  color?: string | null;
  order_index: number;
  is_active: boolean;
  /** Published courses in the category, counted live by the server. */
  course_count: number;
};

export type CategoryInput = {
  name: string;
  slug: string;
  description?: string | null;
  icon?: string | null;
  color?: string | null;
  order_index: number;
  is_active: boolean;
};

const base = () => `${ENV.backendUrl}/categories`;
const body = (payload: unknown) => JSON.stringify(payload);

/** Includes hidden categories, which learners never see. */
export const listCategories = async () =>
  (await apiFetch<Envelope<CourseCategory[]>>(`${base()}?active_only=false`)).data;

export const createCategory = (input: CategoryInput) =>
  apiFetch<Envelope<CourseCategory>>(base(), { method: "POST", body: body(input) });

export const updateCategory = (id: string, input: Partial<CategoryInput>) =>
  apiFetch<Envelope<CourseCategory>>(`${base()}/${id}`, { method: "PUT", body: body(input) });

/** Soft delete: the category is hidden from learners and its courses keep the link. */
export const hideCategory = (id: string) =>
  apiFetch<Envelope<{ id: string }>>(`${base()}/${id}`, { method: "DELETE" });
