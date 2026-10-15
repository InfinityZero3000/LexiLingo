import { beforeEach, describe, expect, it, vi } from "vitest";

const { ENV, authStore } = vi.hoisted(() => ({
  ENV: {
    backendUrl: "https://backend.example/api/v1",
    backendUrlFallback: "",
    aiUrl: "https://ai.example/api/v1",
    aiUrlFallback: "",
    apiKey: "",
  },
  authStore: {
    accessToken: null as string | null,
    refreshToken: null as string | null,
    clear: vi.fn(),
  },
}));

vi.mock("./env", () => ({ ENV }));
vi.mock("./auth", () => ({ authStore }));

import { ApiError, apiFetch } from "./api";

// This suite runs in node (no jsdom installed, and it is not worth adding for
// two globals). api.ts reads `window.atob` to find a token's exp and
// `window.location.href` to bounce an ended session to /login.
const location = { href: "" };
vi.stubGlobal("window", { atob: (v: string) => atob(v), location });

/** A JWT whose `exp` is `secondsFromNow` away. Only the payload is read. */
const token = (secondsFromNow: number) => {
  const payload = btoa(
    JSON.stringify({ exp: Math.floor(Date.now() / 1000) + secondsFromNow })
  );
  return `header.${payload}.signature`;
};

const jsonResponse = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });

/**
 * Losing the admin session.
 *
 * A failed refresh used to clear the store unconditionally — a 503 or a
 * two-second network blip logged the admin out and discarded whatever they had
 * open. Only a server that actually rejects the token should end the session.
 */
describe("apiFetch token refresh", () => {
  beforeEach(() => {
    authStore.accessToken = token(3600);
    authStore.refreshToken = "refresh-token";
    authStore.clear.mockClear();
    location.href = "";
  });

  it("keeps the session when the refresh request cannot reach the server", async () => {
    authStore.accessToken = token(-10); // expired, forces a refresh attempt
    const fetchMock = vi
      .fn()
      .mockRejectedValueOnce(new TypeError("Failed to fetch")) // refresh
      .mockResolvedValueOnce(jsonResponse(200, { ok: true })); // retried call
    vi.stubGlobal("fetch", fetchMock);

    await apiFetch(`${ENV.backendUrl}/admin/courses`);

    expect(authStore.clear).not.toHaveBeenCalled();
    expect(authStore.refreshToken).toBe("refresh-token");
    expect(location.href).toBe("");
  });

  it("keeps the session when refresh answers 503", async () => {
    authStore.accessToken = token(-10);
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse(503, { detail: "unavailable" }))
      .mockResolvedValueOnce(jsonResponse(200, { ok: true }));
    vi.stubGlobal("fetch", fetchMock);

    await apiFetch(`${ENV.backendUrl}/admin/courses`);

    expect(authStore.clear).not.toHaveBeenCalled();
    expect(location.href).toBe("");
  });

  it("ends the session when refresh answers 401", async () => {
    authStore.accessToken = token(-10);
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse(401, { detail: "invalid token" }))
      .mockResolvedValueOnce(jsonResponse(401, { detail: "unauthorized" }));
    vi.stubGlobal("fetch", fetchMock);

    await expect(apiFetch(`${ENV.backendUrl}/admin/courses`)).rejects.toThrow(ApiError);
    expect(authStore.clear).toHaveBeenCalled();
    expect(location.href).toBe("/login");
  });

  it("retries the original call once with the refreshed token", async () => {
    authStore.accessToken = token(3600); // valid, so the 401 drives the refresh
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse(401, { detail: "expired" }))
      .mockResolvedValueOnce(jsonResponse(200, { access_token: "fresh-token" }))
      .mockResolvedValueOnce(jsonResponse(200, { data: "ok" }));
    vi.stubGlobal("fetch", fetchMock);

    await apiFetch(`${ENV.backendUrl}/admin/courses`);

    expect(fetchMock).toHaveBeenCalledTimes(3);
    const retryHeaders = fetchMock.mock.calls[2][1].headers as Headers;
    expect(retryHeaders.get("Authorization")).toBe("Bearer fresh-token");
  });

  it("refreshes once when several calls race on an expired token", async () => {
    authStore.accessToken = token(-10);
    let refreshCalls = 0;
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string) => {
        if (url.endsWith("/auth/refresh")) {
          refreshCalls += 1;
          return jsonResponse(200, { access_token: token(3600) });
        }
        return jsonResponse(200, { ok: true });
      })
    );

    await Promise.all([
      apiFetch(`${ENV.backendUrl}/admin/courses`),
      apiFetch(`${ENV.backendUrl}/admin/units`),
      apiFetch(`${ENV.backendUrl}/admin/lessons`),
    ]);

    expect(refreshCalls).toBe(1);
  });

  it("still ends the session when the token is expired AND refresh is down", async () => {
    // The boundary of the fix above: keeping the session only helps while the
    // access token still works. Once the server rejects it and refresh cannot
    // answer, there is nothing left to make a request with.
    authStore.accessToken = token(-10);
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string) =>
        url.endsWith("/auth/refresh")
          ? jsonResponse(503, { detail: "unavailable" })
          : jsonResponse(401, { detail: "unauthorized" })
      )
    );

    await expect(apiFetch(`${ENV.backendUrl}/admin/courses`)).rejects.toThrow(ApiError);
    expect(authStore.clear).toHaveBeenCalled();
    expect(location.href).toBe("/login");
  });

  it("sends no Authorization header when skipAuth is set", async () => {
    const fetchMock = vi.fn().mockResolvedValue(jsonResponse(200, { ok: true }));
    vi.stubGlobal("fetch", fetchMock);

    await apiFetch(`${ENV.backendUrl}/health`, { skipAuth: true });

    const headers = fetchMock.mock.calls[0][1].headers as Headers;
    expect(headers.has("Authorization")).toBe(false);
  });

  it("surfaces a FastAPI validation list as one readable message", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        jsonResponse(422, { detail: [{ msg: "title required" }, { msg: "bad level" }] })
      )
    );

    await expect(apiFetch(`${ENV.backendUrl}/admin/courses`)).rejects.toThrow(
      "title required, bad level"
    );
  });
});
