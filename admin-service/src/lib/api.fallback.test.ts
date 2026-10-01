import { beforeEach, describe, expect, it, vi } from "vitest";

// vi.mock is hoisted above plain declarations, so the stub has to be too.
const { ENV } = vi.hoisted(() => ({
  ENV: {
    backendUrl: "",
    backendUrlFallback: "",
    aiUrl: "",
    aiUrlFallback: "",
    apiKey: "",
  },
}));

vi.mock("./env", () => ({ ENV }));
vi.mock("./auth", () => ({ authStore: { accessToken: null, refreshToken: null, clear: vi.fn() } }));

import { resolveFallbackTarget } from "./api";

/**
 * Which fallback host a failed request retries against.
 *
 * VITE_BACKEND_URL and VITE_AI_URL default to the SAME value, and the old
 * resolver tested backendUrl first — so once anyone set only
 * VITE_BACKEND_URL_FALLBACK, every ai-service call retried against the
 * backend's fallback host instead.
 */
describe("resolveFallbackTarget", () => {
  beforeEach(() => {
    ENV.backendUrl = "https://api.example/api/v1";
    ENV.aiUrl = "https://api.example/api/v1";
    ENV.backendUrlFallback = "";
    ENV.aiUrlFallback = "";
  });

  it("returns null when no fallback is configured", () => {
    // Production ships both blank, so the whole mechanism is inert there.
    expect(resolveFallbackTarget("https://api.example/api/v1/courses")).toBeNull();
  });

  it("returns null for a URL under neither base", () => {
    ENV.backendUrlFallback = "https://backup.example/api/v1";
    expect(resolveFallbackTarget("https://unrelated.example/thing")).toBeNull();
  });

  it("uses the one configured fallback when both services share a host", () => {
    ENV.aiUrlFallback = "https://ai-backup.example/api/v1";
    const target = resolveFallbackTarget("https://api.example/api/v1/ai/translate");
    expect(target?.fallback).toBe("https://ai-backup.example/api/v1");
  });

  it("keeps each service on its own fallback when the hosts differ", () => {
    ENV.backendUrl = "https://backend.example/api/v1";
    ENV.aiUrl = "https://ai.example/api/v1";
    ENV.backendUrlFallback = "https://backend-backup.example/api/v1";
    ENV.aiUrlFallback = "https://ai-backup.example/api/v1";

    expect(resolveFallbackTarget("https://ai.example/api/v1/stt")?.fallback).toBe(
      "https://ai-backup.example/api/v1"
    );
    expect(resolveFallbackTarget("https://backend.example/api/v1/courses")?.fallback).toBe(
      "https://backend-backup.example/api/v1"
    );
  });

  it("prefers the longer base when one is a prefix of the other", () => {
    ENV.backendUrl = "https://api.example";
    ENV.aiUrl = "https://api.example/ai";
    ENV.backendUrlFallback = "https://backend-backup.example";
    ENV.aiUrlFallback = "https://ai-backup.example";

    const target = resolveFallbackTarget("https://api.example/ai/translate");
    expect(target?.base).toBe("https://api.example/ai");
    expect(target?.fallback).toBe("https://ai-backup.example");
  });

  it("strips the matched base so the path is rebuilt on the fallback host", () => {
    ENV.backendUrl = "https://backend.example/api/v1";
    ENV.backendUrlFallback = "https://backup.example/api/v1";

    const target = resolveFallbackTarget("https://backend.example/api/v1/courses?page=2")!;
    const path = "https://backend.example/api/v1/courses?page=2".slice(target.base.length);
    expect(`${target.fallback}${path}`).toBe("https://backup.example/api/v1/courses?page=2");
  });
});
