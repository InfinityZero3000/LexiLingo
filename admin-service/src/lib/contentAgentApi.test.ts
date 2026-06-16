import { beforeEach, describe, expect, it, vi } from "vitest";

const { apiFetchMock } = vi.hoisted(() => ({
  apiFetchMock: vi.fn(),
}));

vi.mock("./api", () => ({
  apiFetch: apiFetchMock,
}));

vi.mock("./env", () => ({
  ENV: {
    backendUrl: "https://backend.example/api/v1",
  },
}));

import {
  applyContentAgentJob,
  cancelContentAgentJob,
  createContentAgentJob,
  getContentAgentJob,
  getContentAgentPreview,
  listContentAgentJobs,
  retryContentAgentJob,
  uploadContentAgentFile,
} from "./contentAgentApi";

describe("contentAgentApi", () => {
  beforeEach(() => {
    apiFetchMock.mockReset();
    apiFetchMock.mockResolvedValue({ data: { id: "job-1" } });
  });

  it("uploads source files as multipart form data", async () => {
    const file = new File(["word,cefr_level\nhello,A1"], "words.csv", {
      type: "text/csv",
    });

    await uploadContentAgentFile(file, true);

    expect(apiFetchMock).toHaveBeenCalledOnce();
    const [url, options] = apiFetchMock.mock.calls[0];
    expect(url).toBe(
      "https://backend.example/api/v1/admin/content-agent/uploads?rights_confirmed=true",
    );
    expect(options.method).toBe("POST");
    expect(options.body).toBeInstanceOf(FormData);
    expect(options.body.get("file")).toBe(file);
  });

  it("creates a preview-only job with JSON configuration", async () => {
    const payload = {
      levels: ["A1", "B1"] as const,
      sources: ["existing_cefr"] as const,
      words_per_lesson: 10,
      exercises_per_lesson: 10,
      exercise_mix: { speaking: 2, listening: 2 },
      units_per_course: 3,
      lessons_per_unit: 4,
      confidence_threshold: 0.75,
      topic_focus: [],
      revision: false,
      apply_on_success: false as const,
    };

    await createContentAgentJob(payload);

    expect(apiFetchMock).toHaveBeenCalledWith(
      "https://backend.example/api/v1/admin/content-agent/jobs",
      {
        method: "POST",
        body: JSON.stringify(payload),
      },
    );
  });

  it("uses the approved list, detail, and preview endpoints", async () => {
    apiFetchMock
      .mockResolvedValueOnce({ data: { jobs: [], total: 0 } })
      .mockResolvedValueOnce({ data: { id: "job-1" } })
      .mockResolvedValueOnce({ data: { courses: [] } });

    await listContentAgentJobs();
    await getContentAgentJob("job-1");
    await getContentAgentPreview("job-1");

    expect(apiFetchMock.mock.calls.map(([url]) => url)).toEqual([
      "https://backend.example/api/v1/admin/content-agent/jobs",
      "https://backend.example/api/v1/admin/content-agent/jobs/job-1",
      "https://backend.example/api/v1/admin/content-agent/jobs/job-1/preview",
    ]);
  });

  it.each([
    ["apply", applyContentAgentJob],
    ["retry", retryContentAgentJob],
    ["cancel", cancelContentAgentJob],
  ])("posts to the %s action", async (action, request) => {
    await request("job-1");

    expect(apiFetchMock).toHaveBeenCalledWith(
      `https://backend.example/api/v1/admin/content-agent/jobs/job-1/${action}`,
      { method: "POST" },
    );
  });

  it("normalizes direct and enveloped list responses", async () => {
    apiFetchMock.mockResolvedValueOnce([
      { id: "job-1", status: "queued" },
    ]);
    await expect(listContentAgentJobs()).resolves.toMatchObject({
      jobs: [{ id: "job-1" }],
      total: 1,
    });

    apiFetchMock.mockResolvedValueOnce({
      data: { jobs: [{ id: "job-2", status: "failed" }], total: 4 },
    });
    await expect(listContentAgentJobs()).resolves.toMatchObject({
      jobs: [{ id: "job-2" }],
      total: 4,
    });
  });
});
