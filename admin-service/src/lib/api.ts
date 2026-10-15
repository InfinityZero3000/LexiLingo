import { authStore } from "./auth";
import { ENV } from "./env";

export type ApiResponse<T> = {
  success: boolean;
  message?: string;
  data?: T;
  error?: string;
};

export class ApiError extends Error {
  status: number;
  payload?: any;

  constructor(message: string, status: number, payload?: any) {
    super(message);
    this.status = status;
    this.payload = payload;
  }
}

type ApiFetchOptions = RequestInit & {
  skipAuth?: boolean;
};

// Track refresh state to avoid concurrent refresh calls
let isRefreshing = false;
let refreshPromise: Promise<boolean> | null = null;

const TOKEN_REFRESH_BUFFER_MS = 30_000;

const getJwtExpiryMs = (token: string): number => {
  try {
    const [, payload] = token.split(".");
    if (!payload) return 0;

    const normalized = payload.replace(/-/g, "+").replace(/_/g, "/");
    const padded = normalized.padEnd(
      normalized.length + ((4 - (normalized.length % 4)) % 4),
      "="
    );
    const decoded = JSON.parse(window.atob(padded));
    return typeof decoded.exp === "number" ? decoded.exp * 1000 : 0;
  } catch {
    return 0;
  }
};

const shouldRefreshAccessToken = (token: string | null): boolean => {
  if (!token) return true;
  const expiryMs = getJwtExpiryMs(token);
  return !expiryMs || expiryMs - Date.now() <= TOKEN_REFRESH_BUFFER_MS;
};

// ─────────────────────────────────────────────────────────────────────────────
// Fallback fetch: thử primary URL trước, nếu network error → thử fallback.
// Chỉ fallback khi lỗi là TypeError (connection refused / DNS / network down).
// Lỗi HTTP (4xx, 5xx) KHÔNG fallback — đó là response hợp lệ từ server.
// ─────────────────────────────────────────────────────────────────────────────
// Chọn cặp (base, fallback) cho một URL.
//
// backendUrl và aiUrl mặc định TRÙNG NHAU (cùng DEFAULT_API_URL), nên bản cũ —
// kiểm tra backendUrl trước — gán fallback của backend cho cả request AI. Lọc
// bỏ base chưa cấu hình fallback để trường hợp cùng host dùng đúng cái đang có,
// và chọn base dài nhất khi một base là tiền tố của base kia.
export const resolveFallbackTarget = (
  primaryUrl: string
): { base: string; fallback: string } | null => {
  const match = ([
    { base: ENV.backendUrl, fallback: ENV.backendUrlFallback },
    { base: ENV.aiUrl, fallback: ENV.aiUrlFallback },
  ] as const)
    .filter((c) => c.base && c.fallback && primaryUrl.startsWith(c.base))
    .sort((a, b) => b.base.length - a.base.length)[0];
  return match ? { base: match.base, fallback: match.fallback } : null;
};

async function fetchWithFallback(
  primaryUrl: string,
  options: RequestInit
): Promise<Response> {
  const target = resolveFallbackTarget(primaryUrl);

  try {
    return await fetch(primaryUrl, options);
  } catch (err) {
    // Chỉ fallback khi là network error (không phải HTTP error)
    if (!(err instanceof TypeError) || !target) {
      throw err;
    }

    const { base: primaryBase, fallback: fallbackBase } = target;
    const path = primaryUrl.slice(primaryBase.length);
    const fallbackUrl = `${fallbackBase}${path}`;

    console.warn(
      `[API] Primary không reach được (${primaryBase}), thử fallback: ${fallbackBase}`
    );

    try {
      return await fetch(fallbackUrl, options);
    } catch {
      throw new Error(
        `[API] Không thể kết nối đến cả primary (${primaryBase}) ` +
        `lẫn fallback (${fallbackBase}). Kiểm tra kết nối mạng hoặc trạng thái server.`
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Refresh token (cũng có fallback)
// ─────────────────────────────────────────────────────────────────────────────
async function tryRefreshToken(): Promise<boolean> {
  const refreshToken = authStore.refreshToken;
  if (!refreshToken) return false;

  if (isRefreshing && refreshPromise) {
    return refreshPromise;
  }

  isRefreshing = true;
  refreshPromise = (async () => {
    try {
      const response = await fetchWithFallback(`${ENV.backendUrl}/auth/refresh`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          ...(ENV.apiKey ? { "X-Api-Key": ENV.apiKey } : {}),
        },
        body: JSON.stringify({ refresh_token: refreshToken }),
      });

      if (!response.ok) {
        // Only a rejected token ends the session. A 500/503 or a rate limit
        // means the server could not answer, not that the refresh token is
        // invalid — clearing on those logged the admin out over a blip and
        // lost whatever they had open.
        if (response.status === 401 || response.status === 403) {
          authStore.clear();
        }
        return false;
      }

      const data = await response.json();
      authStore.accessToken = data.access_token;
      if (data.refresh_token) {
        authStore.refreshToken = data.refresh_token;
      }
      return true;
    } catch {
      // Network error: the server never answered, so the token is still as
      // valid as it was. Keep it and let the caller surface the failure.
      return false;
    } finally {
      isRefreshing = false;
      refreshPromise = null;
    }
  })();

  return refreshPromise;
}

async function getUsableAccessToken(): Promise<string | null> {
  const token = authStore.accessToken;

  if (!authStore.refreshToken) {
    return token;
  }

  if (shouldRefreshAccessToken(token)) {
    const refreshed = await tryRefreshToken();
    if (refreshed) {
      return authStore.accessToken;
    }
  }

  return authStore.accessToken;
}

// ─────────────────────────────────────────────────────────────────────────────
// Main API fetch — gọi với full URL, tự động attach token + refresh + fallback
// ─────────────────────────────────────────────────────────────────────────────
export const apiFetch = async <T>(
  url: string,
  options: ApiFetchOptions = {}
): Promise<T> => {
  const { skipAuth = false, ...requestOptions } = options;

  const makeRequest = async (token: string | null) => {
    const headers = new Headers(requestOptions.headers);
    headers.set("Accept", "application/json");

    if (!(requestOptions.body instanceof FormData)) {
      headers.set("Content-Type", "application/json");
    }

    if (!skipAuth && token) {
      headers.set("Authorization", `Bearer ${token}`);
    }

    if (ENV.apiKey) {
      headers.set("X-Api-Key", ENV.apiKey);
    }

    return fetchWithFallback(url, { ...requestOptions, headers });
  };

  // First attempt
  let response = await makeRequest(skipAuth ? null : await getUsableAccessToken());

  // If 401 and we have a refresh token, try to refresh and retry once
  if (!skipAuth && response.status === 401 && authStore.refreshToken) {
    const refreshed = await tryRefreshToken();
    if (refreshed) {
      response = await makeRequest(authStore.accessToken);
    } else if (!authStore.refreshToken) {
      // tryRefreshToken only clears the store when the server actually
      // rejected the token. Still holding one means the refresh failed for
      // another reason (network, 503), so keep the session and let the caller
      // show the error instead of bouncing to /login.
      window.location.href = "/login";
      throw new ApiError("Session expired. Please log in again.", 401);
    }
  }

  const contentType = response.headers.get("content-type") || "";
  const payload = contentType.includes("application/json")
    ? await response.json()
    : await response.text();

  if (!response.ok) {
    if (response.status === 401) {
      authStore.clear();
      window.location.href = "/login";
    }
    
    let message = "Request failed";
    if (typeof payload === "string") {
      message = payload;
    } else if (payload && typeof payload === "object") {
      if (Array.isArray(payload.detail)) {
        message = payload.detail.map((err: any) => err.msg || JSON.stringify(err)).join(", ");
      } else if (typeof payload.detail === "string") {
        message = payload.detail;
      } else if (typeof payload.message === "string") {
        message = payload.message;
      } else if (typeof payload.error?.message === "string") {
        message = payload.error.message;
      } else if (payload.detail || payload.message) {
        message = JSON.stringify(payload.detail || payload.message);
      }
    }
    
    throw new ApiError(message, response.status, payload);
  }

  return payload as T;
};
