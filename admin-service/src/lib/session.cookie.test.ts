import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const { ENV } = vi.hoisted(() => ({
  ENV: {
    backendUrl: "https://api.lexilingo.me/api/v1",
    backendUrlFallback: "",
    aiUrl: "https://api.lexilingo.me/api/v1",
    aiUrlFallback: "",
    apiKey: "",
    adminEmails: [] as string[],
    superAdminEmails: [] as string[],
  },
}));
vi.mock("./env", () => ({ ENV }));

import { apiFetch } from "./api";
import { authStore } from "./auth";
import { googleLoginRequest, logoutRequest } from "./authApi";
import { sessionTransport } from "./sessionTransport";

const stored = new Map<string, string>();
const location = { hostname: "admin.lexilingo.me", href: "", pathname: "/admin" };

const token = (secondsFromNow: number, tag = "a") =>
  `h.${btoa(JSON.stringify({ exp: Math.floor(Date.now() / 1000) + secondsFromNow, tag }))}.s`;

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

const sent = (call: unknown[]) => JSON.parse((call[1] as RequestInit).body as string);

beforeEach(() => {
  stored.clear();
  location.hostname = "admin.lexilingo.me";
  location.href = "";
  ENV.backendUrl = "https://api.lexilingo.me/api/v1";
  vi.stubGlobal("window", { atob: (v: string) => atob(v), location });
  vi.stubGlobal("localStorage", {
    getItem: (k: string) => stored.get(k) ?? null,
    setItem: (k: string, v: string) => void stored.set(k, v),
    removeItem: (k: string) => void stored.delete(k),
  });
});
afterEach(() => vi.unstubAllGlobals());

describe("where the refresh token lives", () => {
  it.each([
    ["admin.lexilingo.me", "https://api.lexilingo.me/api/v1", "cookie"],
    ["localhost", "http://localhost:8000/api/v1", "cookie"],
    ["localhost", "https://api.lexilingo.me/api/v1", "token"],
    ["localhost", "http://127.0.0.1:8000/api/v1", "token"],
    ["lexilingo-admin.vercel.app", "https://api.lexilingo.me/api/v1", "token"],
    ["admin.lexilingo.me", "https://lexilingo.me.attacker.example/api/v1", "token"],
  ])("page %s with API %s uses %s", (page, api, expected) => {
    location.hostname = page;
    ENV.backendUrl = api;
    expect(sessionTransport()).toBe(expected);
  });

  it("stores no refresh token when the server kept it in the cookie", () => {
    authStore.refreshToken = "old";
    authStore.saveSession("access", "");
    expect([...stored.values()]).not.toContain("old");
    expect(authStore.refreshToken).toBeNull();
    expect(authStore.cookieSession).toBe(true);
    authStore.clear();
    expect(stored.size).toBe(0);
  });

  it("keeps working with a server that still returns the token", () => {
    authStore.saveSession("access", "refresh");
    expect(authStore.refreshToken).toBe("refresh");
    expect(authStore.cookieSession).toBe(false);
  });
});

describe("cookie session requests", () => {
  it("signs in asking for the cookie, and sends credentials", async () => {
    const fetchMock = vi.fn().mockResolvedValue(json(200, {}));
    vi.stubGlobal("fetch", fetchMock);
    await googleLoginRequest("id-token");
    expect(sent(fetchMock.mock.calls[0])).toEqual({ id_token: "id-token", source: "admin", session: "cookie" });
    expect(fetchMock.mock.calls[0][1].credentials).toBe("include");
  });

  it("refreshes from the cookie without a token in the page", async () => {
    authStore.saveSession(token(-10), "");
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(json(200, { access_token: token(3600, "new"), refresh_token: "" }))
      .mockResolvedValueOnce(json(200, { ok: true }));
    vi.stubGlobal("fetch", fetchMock);

    await apiFetch(`${ENV.backendUrl}/admin/courses`);

    expect(sent(fetchMock.mock.calls[0])).toEqual({ session: "cookie" });
    expect(fetchMock.mock.calls[0][1].credentials).toBe("include");
    expect(authStore.refreshToken).toBeNull();
    expect(authStore.cookieSession).toBe(true);
  });

  it("moves a token stored earlier into the cookie", async () => {
    authStore.accessToken = token(-10);
    authStore.refreshToken = "stored-before";
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(json(200, { access_token: token(3600, "new"), refresh_token: "" }))
      .mockResolvedValueOnce(json(200, { ok: true }));
    vi.stubGlobal("fetch", fetchMock);

    await apiFetch(`${ENV.backendUrl}/admin/courses`);

    expect(sent(fetchMock.mock.calls[0])).toEqual({ refresh_token: "stored-before", session: "cookie" });
    expect([...stored.values()]).not.toContain("stored-before");
    expect(authStore.cookieSession).toBe(true);
  });

  it("keeps the session another tab renewed while this refresh was refused", async () => {
    authStore.saveSession(token(-10), "");
    vi.stubGlobal("fetch", vi.fn(async (url: string) => {
      if (url.endsWith("/auth/refresh")) {
        authStore.accessToken = token(3600, "other-tab");
        return json(401, { detail: "reused" });
      }
      return json(200, { ok: true });
    }));

    await apiFetch(`${ENV.backendUrl}/admin/courses`);

    expect(authStore.cookieSession).toBe(true);
    expect(location.href).toBe("");
  });

  it("ends a cookie session the server rejects", async () => {
    authStore.saveSession(token(-10), "");
    vi.stubGlobal("fetch", vi.fn(async () => json(401, { detail: "no" })));

    await expect(apiFetch(`${ENV.backendUrl}/admin/courses`)).rejects.toThrow();

    expect(authStore.cookieSession).toBe(false);
    expect(location.href).toBe("/login");
  });

  it("revokes on the server when signing out", async () => {
    const fetchMock = vi.fn().mockResolvedValue(json(200, { message: "ok" }));
    vi.stubGlobal("fetch", fetchMock);

    await logoutRequest({ accessToken: "access", refreshToken: null });

    expect(fetchMock.mock.calls[0][0]).toMatch(/\/auth\/logout$/);
    expect(sent(fetchMock.mock.calls[0])).toEqual({ session: "cookie" });
    expect(fetchMock.mock.calls[0][1].credentials).toBe("include");
    expect((fetchMock.mock.calls[0][1].headers as Headers).get("Authorization")).toBe("Bearer access");
  });
});
