// A relative "/api/v1/..." resolves against the admin site itself, where the SPA rewrite
// answers instead of the backend.
import { beforeEach, describe, expect, it, vi } from "vitest";
import * as notification from "./notificationCampaignApi";
import * as ranking from "./rankingAgentApi";

const apiFetch = vi.hoisted(() => vi.fn(async () => ({ data: [] })));
vi.mock("./api", () => ({ apiFetch }));
vi.mock("./env", () => ({ ENV: { backendUrl: "https://backend.example/api/v1" } }));

describe.each([
  ["ranking-agent", ranking],
  ["notification-campaign", notification],
] as const)("%s API", (prefix, module) => {
  beforeEach(() => apiFetch.mockClear());

  it("sends every request to the configured backend", async () => {
    const requests = Object.entries(module).filter(
      ([name, value]) => typeof value === "function" && /^(create|list|get|apply|cancel|retry)[A-Z]/.test(name),
    ) as Array<[string, (...args: unknown[]) => Promise<unknown>]>;
    expect(requests.length).toBeGreaterThanOrEqual(6);

    for (const [, call] of requests) await call("job-1", 0);

    for (const [url] of apiFetch.mock.calls as unknown as string[][]) {
      expect(url.startsWith(`https://backend.example/api/v1/admin/${prefix}/jobs`)).toBe(true);
    }
  });
});
