import { apiFetch } from "./api";
import { ENV } from "./env";

export const CEFR_LEVELS = ["A1", "A2", "B1", "B2", "C1", "C2"] as const;
export type CefrLevel = (typeof CEFR_LEVELS)[number];

export const CONTENT_AGENT_SOURCES = [
  "existing_cefr",
  "admin_upload",
  "oewn",
  "cmudict",
  "cefr_j",
  "wikidata",
  "tatoeba",
  "librispeech",
  "common_voice",
] as const;
export type ContentAgentSource = (typeof CONTENT_AGENT_SOURCES)[number];

export type ContentAgentLicenseMode =
  | "approved_dataset"
  | "public_domain_verified"
  | "metadata_only"
  | "label_only"
  | "admin_owned"
  | "disabled_pending_license"
  | "api_pending_license";

export const CONTENT_AGENT_ACTIVE_STATUSES = [
  "queued",
  "resolving_sources",
  "loading_snapshots",
  "normalizing_upload",
  "extracting",
  "normalizing",
  "classifying",
  "planning",
  "generating",
  "validating",
  "applying",
] as const;

export type ContentAgentJobStatus =
  | (typeof CONTENT_AGENT_ACTIVE_STATUSES)[number]
  | "preview_ready"
  | "completed"
  | "failed"
  | "cancelled";

export type ContentAgentUpload = {
  id: string;
  filename: string;
  checksum?: string;
  row_count: number;
  schema_version?: number;
  expires_at?: string;
  errors?: Array<{ row?: number; message: string } | string>;
};

export type ContentAgentJobCreate = {
  levels: readonly CefrLevel[];
  sources: readonly ContentAgentSource[];
  upload_id?: string;
  title_focus?: string;
  topic_focus: string[];
  units_per_course: number;
  lessons_per_unit: number;
  words_per_lesson: number;
  exercises_per_lesson: number;
  exercise_mix: {
    speaking: number;
    listening: number;
  };
  confidence_threshold: number;
  revision: boolean;
  apply_on_success: false;
};

export type ContentAgentProgress = {
  stage?: ContentAgentJobStatus | string;
  percentage?: number;
  percent?: number;
  message?: string;
  total_records?: number;
  processed_records?: number;
  rejected_records?: number;
  deduplicated_records?: number;
  processed?: number;
  rejected?: number;
  deduplicated?: number;
  counters?: Record<string, number>;
  [key: string]: unknown;
};

export type ContentAgentSourceManifestItem = {
  source_name: string;
  source_url?: string | null;
  license_mode?: ContentAgentLicenseMode | string;
  content_usage?:
    | "full_text"
    | "metadata_only"
    | "label_only"
    | string
    | string[];
  record_count?: number;
  checksum?: string;
  policy_version?: string;
  [key: string]: unknown;
};

export type ContentAgentCreatedEntityIds = {
  course_ids?: string[];
  courses?: string[];
  unit_ids?: string[];
  lesson_ids?: string[];
  [key: string]: unknown;
};

export type ContentAgentJob = {
  id: string;
  status: ContentAgentJobStatus;
  request_hash?: string;
  revision?: number;
  config: Partial<ContentAgentJobCreate> & Record<string, unknown>;
  progress: ContentAgentProgress;
  source_manifest: ContentAgentSourceManifestItem[];
  warnings: string[];
  blocking_errors: string[];
  created_entity_ids: ContentAgentCreatedEntityIds;
  error_message?: string | null;
  celery_task_id?: string | null;
  created_at: string;
  updated_at: string;
  started_at?: string | null;
  completed_at?: string | null;
};

export type ContentAgentVocabularyItem = {
  id?: string;
  word: string;
  part_of_speech?: string;
  definition?: string;
  translation_vi?: string;
  example?: string;
  reused?: boolean;
  [key: string]: unknown;
};

export type ContentAgentExercise = {
  id: string;
  type: string;
  ui_type: string;
  phase?: "pre_task" | "task_cycle" | "language_focus" | string;
  question: string;
  correct_answer: string;
  options?: unknown;
  explanation?: string;
  audio_url?: string;
  [key: string]: unknown;
};

export type ContentAgentLessonPreview = {
  title: string;
  outcome?: string | null;
  order_index: number;
  vocabulary: ContentAgentVocabularyItem[];
  exercises: ContentAgentExercise[];
  [key: string]: unknown;
};

export type ContentAgentRecordUpdate = {
  question?: string;
  options?: unknown;
  correct_answer?: string;
  explanation?: string;
  lesson_outcome?: string;
};

export type ContentAgentUnitPreview = {
  title: string;
  order_index: number;
  lessons: ContentAgentLessonPreview[];
  [key: string]: unknown;
};

export type ContentAgentCoursePreview = {
  title: string;
  description?: string | null;
  language: string;
  level: CefrLevel | string;
  tags: string[];
  units: ContentAgentUnitPreview[];
  [key: string]: unknown;
};

export type ContentAgentPreview = {
  schema_version: number;
  prompt_version: string;
  generation_key: string;
  source_manifest: ContentAgentSourceManifestItem[];
  courses: ContentAgentCoursePreview[];
  quality: {
    blocking_errors: string[];
    warnings: string[];
    metrics: Record<string, unknown>;
  };
};

export type ContentAgentJobList = {
  jobs: ContentAgentJob[];
  total: number;
};

export type ContentQaQueue = {
  reviewable: ContentAgentJob[];
  failed: ContentAgentJob[];
  applied: ContentAgentJob[];
  total: number;
};

type ApiEnvelope<T> = {
  success?: boolean;
  data?: T;
  message?: string;
  error?: string;
};

export interface SourceSnapshot {
  source_id: string;
  source_name: string;
  source_version: string;
  snapshot_id: string;
  official_url: string;
  license_id: string;
  license_url: string;
  attribution_text: string;
  retrieved_at: string;
  raw_checksum: string;
  normalized_sha256: string;
  normalized_bytes: number;
  record_checksum_root: string;
  adapter_version: number;
  record_count: number;
  status: "active";
  enabled: boolean;
}

const baseUrl = `${ENV.backendUrl}/admin/content-agent`;

const unwrap = <T>(payload: T | ApiEnvelope<T>): T => {
  if (
    payload &&
    typeof payload === "object" &&
    "data" in payload &&
    (payload as ApiEnvelope<T>).data !== undefined
  ) {
    return (payload as ApiEnvelope<T>).data as T;
  }

  return payload as T;
};

const jobUrl = (jobId: string, action?: string) =>
  `${baseUrl}/jobs/${encodeURIComponent(jobId)}${action ? `/${action}` : ""}`;

export const uploadContentAgentFile = async (
  file: File,
  rightsConfirmed = false,
): Promise<ContentAgentUpload> => {
  const formData = new FormData();
  formData.append("file", file);
  const payload = await apiFetch<
    ContentAgentUpload | ApiEnvelope<ContentAgentUpload>
  >(`${baseUrl}/uploads?rights_confirmed=${rightsConfirmed ? "true" : "false"}`, {
    method: "POST",
    body: formData,
  });
  return unwrap(payload);
};

export const createContentAgentJob = async (
  config: ContentAgentJobCreate,
): Promise<ContentAgentJob> => {
  const payload = await apiFetch<ContentAgentJob | ApiEnvelope<ContentAgentJob>>(
    `${baseUrl}/jobs`,
    {
      method: "POST",
      body: JSON.stringify(config),
    },
  );
  return unwrap(payload);
};

export const listContentAgentJobs = async (): Promise<ContentAgentJobList> => {
  const payload = unwrap(
    await apiFetch<
      | ContentAgentJob[]
      | ContentAgentJobList
      | ApiEnvelope<ContentAgentJob[] | ContentAgentJobList>
    >(`${baseUrl}/jobs`),
  );

  if (Array.isArray(payload)) {
    return { jobs: payload, total: payload.length };
  }

  const list = payload as ContentAgentJobList & {
    items?: ContentAgentJob[];
  };
  const jobs = list.jobs ?? list.items ?? [];
  return {
    jobs,
    total: typeof list.total === "number" ? list.total : jobs.length,
  };
};

export const buildContentQaQueue = (
  jobs: readonly ContentAgentJob[],
): ContentQaQueue => {
  const reviewable = jobs.filter((job) => job.status === "preview_ready");
  const failed = jobs.filter((job) => job.status === "failed");
  const applied = jobs.filter((job) => job.status === "completed");

  return {
    reviewable,
    failed,
    applied,
    total: jobs.length,
  };
};

export const listContentQaQueue = async (): Promise<ContentQaQueue> => {
  const { jobs } = await listContentAgentJobs();
  return buildContentQaQueue(jobs);
};

export const getContentAgentJob = async (
  jobId: string,
): Promise<ContentAgentJob> => {
  const payload = await apiFetch<ContentAgentJob | ApiEnvelope<ContentAgentJob>>(
    jobUrl(jobId),
  );
  return unwrap(payload);
};

export const getContentAgentPreview = async (
  jobId: string,
): Promise<ContentAgentPreview> => {
  const payload = unwrap(
    await apiFetch<
      | ContentAgentPreview
      | { artifact?: ContentAgentPreview; preview?: ContentAgentPreview }
      | ApiEnvelope<
          | ContentAgentPreview
          | { artifact?: ContentAgentPreview; preview?: ContentAgentPreview }
        >
    >(jobUrl(jobId, "preview")),
  );

  if ("courses" in payload) {
    return payload as ContentAgentPreview;
  }

  const response = payload as {
    artifact?: ContentAgentPreview;
    preview?: ContentAgentPreview;
  };
  const preview = response.artifact ?? response.preview;
  if (!preview) {
    throw new Error("Content agent preview is missing from the response.");
  }
  return preview;
};

const postJobAction = async (
  jobId: string,
  action: "apply" | "retry" | "cancel",
): Promise<ContentAgentJob> => {
  const payload = await apiFetch<ContentAgentJob | ApiEnvelope<ContentAgentJob>>(
    jobUrl(jobId, action),
    { method: "POST" },
  );
  return unwrap(payload);
};

export const applyContentAgentJob = (jobId: string) =>
  apiFetch<
    | ContentAgentJob
    | {
        job: ContentAgentJob;
        course_ids: string[];
      }
    | ApiEnvelope<
        | ContentAgentJob
        | {
            job: ContentAgentJob;
            course_ids: string[];
          }
      >
  >(jobUrl(jobId, "apply"), { method: "POST" }).then((payload) => {
    const result = unwrap(payload);
    if ("job" in result) {
      return {
        ...result.job,
        created_entity_ids: {
          ...result.job.created_entity_ids,
          course_ids: result.course_ids,
        },
      };
    }
    return result;
  });

export const updateContentAgentRecord = async (
  jobId: string,
  recordId: string,
  update: ContentAgentRecordUpdate,
): Promise<ContentAgentPreview> => {
  const payload = await apiFetch<
    { artifact: ContentAgentPreview } | ApiEnvelope<{ artifact: ContentAgentPreview }>
  >(`${jobUrl(jobId, "records")}/${encodeURIComponent(recordId)}`, {
    method: "PATCH",
    body: JSON.stringify(update),
  });
  return unwrap(payload).artifact;
};

export const retryContentAgentJob = (jobId: string) =>
  postJobAction(jobId, "retry");

export const cancelContentAgentJob = (jobId: string) =>
  postJobAction(jobId, "cancel");

export const getSourceCatalog = async (): Promise<SourceSnapshot[]> => {
  const payload = await apiFetch<
    SourceSnapshot[] | ApiEnvelope<SourceSnapshot[]>
  >(`${baseUrl}/sources`);
  const result = unwrap(payload);
  return Array.isArray(result) ? result : [];
};
