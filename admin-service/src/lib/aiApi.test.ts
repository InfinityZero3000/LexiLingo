import { beforeEach, describe, expect, it, vi } from "vitest";

const { apiFetchMock } = vi.hoisted(() => ({ apiFetchMock: vi.fn() }));

vi.mock("./api", () => ({ apiFetch: apiFetchMock }));
vi.mock("./env", () => ({
  ENV: {
    backendUrl: "https://backend.example/api/v1",
    aiUrl: "https://ai.example/api/v1",
    aiAdminUrl: "https://backend.example/api/v1/admin/ai-proxy",
  },
}));

import { getMonitoringDashboard } from "./aiApi";

describe("aiApi", () => {
  beforeEach(() => {
    apiFetchMock.mockReset();
    apiFetchMock.mockResolvedValue({});
  });

  it("reads the AI dashboard through the backend proxy, never straight from ai-service", async () => {
    // ai-service gates this route on X-Admin-Key, which the browser must never hold.
    await getMonitoringDashboard();

    expect(apiFetchMock).toHaveBeenCalledWith("https://backend.example/api/v1/admin/ai-proxy/monitoring/dashboard");
  });
});
