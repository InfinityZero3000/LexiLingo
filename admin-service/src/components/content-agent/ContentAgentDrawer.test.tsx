import { describe, expect, it, vi } from "vitest";

import type { ContentAgentJob } from "../../lib/contentAgentApi";
import {
  applyContentAgentPreview,
  canApplyContentAgentJob,
  isContentAgentJobActive,
  summarizeContentAgentPreview,
} from "./ContentAgentDrawer";

const job = (overrides: Partial<ContentAgentJob> = {}): ContentAgentJob => ({
  id: "job-1",
  status: "preview_ready",
  config: {},
  progress: { percentage: 100 },
  source_manifest: [],
  warnings: [],
  blocking_errors: [],
  created_entity_ids: {},
  created_at: "2026-06-15T00:00:00Z",
  updated_at: "2026-06-15T00:01:00Z",
  ...overrides,
});

describe("ContentAgentDrawer state", () => {
  it("polls only non-terminal pipeline stages", () => {
    expect(isContentAgentJobActive("resolving_sources")).toBe(true);
    expect(isContentAgentJobActive("loading_snapshots")).toBe(true);
    expect(isContentAgentJobActive("normalizing_upload")).toBe(true);
    expect(isContentAgentJobActive("generating")).toBe(true);
    expect(isContentAgentJobActive("applying")).toBe(true);
    expect(isContentAgentJobActive("preview_ready")).toBe(false);
    expect(isContentAgentJobActive("completed")).toBe(false);
    expect(isContentAgentJobActive("failed")).toBe(false);
  });

  it("disables apply when validation has blocking errors", () => {
    expect(canApplyContentAgentJob(job())).toBe(true);
    expect(
      canApplyContentAgentJob(
        job({ blocking_errors: ["Lesson 2 has an invalid exercise"] }),
      ),
    ).toBe(false);
    expect(canApplyContentAgentJob(job({ status: "generating" }))).toBe(false);
  });

  it("summarizes preview vocabulary and speaking/listening exercises", () => {
    expect(
      summarizeContentAgentPreview({
        schema_version: 2,
        prompt_version: "cefr-course-v2",
        generation_key: "key",
        source_manifest: [],
        courses: [
          {
            title: "A1 Foundations",
            description: "",
            language: "en",
            level: "A1",
            tags: [],
            units: [
              {
                title: "Daily life",
                order_index: 1,
                lessons: [
                  {
                    title: "Morning",
                    order_index: 1,
                    vocabulary: [{ word: "wake", part_of_speech: "verb" }],
                    exercises: [
                      {
                        id: "e1",
                        type: "speaking",
                        ui_type: "speaking_repeat",
                        question: "Repeat.",
                        correct_answer: "I wake up.",
                      },
                      {
                        id: "e2",
                        type: "listening",
                        ui_type: "dictation",
                        question: "Type what you hear.",
                        correct_answer: "I wake up.",
                      },
                    ],
                  },
                ],
              },
            ],
          },
        ],
        quality: {
          blocking_errors: [],
          warnings: [],
          metrics: { duplicate_reuse_count: 3 },
        },
      }),
    ).toEqual({
      courses: 1,
      units: 1,
      lessons: 1,
      vocabulary: 1,
      speaking: 1,
      listening: 1,
      duplicateReuse: 3,
    });
  });

  it("reports a successful apply and lets the page refresh courses", async () => {
    const apply = vi.fn().mockResolvedValue(
      job({
        status: "completed",
        created_entity_ids: { course_ids: ["course-1"] },
      }),
    );
    const onApplied = vi.fn();

    const result = await applyContentAgentPreview("job-1", apply, onApplied);

    expect(apply).toHaveBeenCalledWith("job-1");
    expect(onApplied).toHaveBeenCalledWith(result);
    expect(result.created_entity_ids.course_ids).toEqual(["course-1"]);
  });

  it("blocking errors from job and preview both prevent apply", () => {
    expect(
      canApplyContentAgentJob(
        job({ blocking_errors: ["Missing required field: definition"] }),
      ),
    ).toBe(false);

    expect(
      canApplyContentAgentJob(
        job({ blocking_errors: ["Invalid POS enum: VERB", "Missing license"] }),
      ),
    ).toBe(false);
  });

  it("canApply is true only when status is preview_ready and no blocking errors", () => {
    expect(canApplyContentAgentJob(job({ status: "preview_ready", blocking_errors: [] }))).toBe(true);
    expect(canApplyContentAgentJob(job({ status: "completed", blocking_errors: [] }))).toBe(false);
    expect(canApplyContentAgentJob(job({ status: "failed", blocking_errors: [] }))).toBe(false);
    expect(canApplyContentAgentJob(job({ status: "preview_ready", blocking_errors: ["err"] }))).toBe(false);
  });

  it("validation report shows error count through blocking_errors array", () => {
    const jobWithErrors = job({
      blocking_errors: ["Error 1", "Error 2", "Error 3"],
    });
    expect(jobWithErrors.blocking_errors).toHaveLength(3);
    expect(canApplyContentAgentJob(jobWithErrors)).toBe(false);
  });
});
