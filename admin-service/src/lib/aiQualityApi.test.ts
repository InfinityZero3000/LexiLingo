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

import { getAiQualitySummary } from "./aiQualityApi";

describe("aiQualityApi", () => {
  beforeEach(() => {
    apiFetchMock.mockReset();
    apiFetchMock.mockResolvedValue({
      events: [],
      summary: { total_events: 0 },
      total: 0,
      source: "ai:audit:all",
    });
  });

  it("loads the backend AI audit quality summary with a bounded limit", async () => {
    await getAiQualitySummary(250);

    expect(apiFetchMock).toHaveBeenCalledWith(
      "https://backend.example/api/v1/ai-audit/quality-summary?limit=250",
    );
  });
});
