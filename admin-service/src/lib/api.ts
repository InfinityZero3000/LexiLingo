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

// Track refresh state to avoid concurrent refresh calls
let isRefreshing = false;
let refreshPromise: Promise<boolean> | null = null;

// ─────────────────────────────────────────────────────────────────────────────
// Fallback fetch: thử primary URL trước, nếu network error → thử fallback.
// Chỉ fallback khi lỗi là TypeError (connection refused / DNS / network down).
// Lỗi HTTP (4xx, 5xx) KHÔNG fallback — đó là response hợp lệ từ server.
// ─────────────────────────────────────────────────────────────────────────────
async function fetchWithFallback(
  primaryUrl: string,
  options: RequestInit
): Promise<Response> {
  // Xác định base và fallback tương ứng
  let fallbackBase = "";
  if (primaryUrl.startsWith(ENV.backendUrl)) {
    fallbackBase = ENV.backendUrlFallback;
  } else if (primaryUrl.startsWith(ENV.aiUrl)) {
    fallbackBase = ENV.aiUrlFallback;
  }

  try {
    return await fetch(primaryUrl, options);
  } catch (err) {
    // Chỉ fallback khi là network error (không phải HTTP error)
    if (!(err instanceof TypeError) || !fallbackBase) {
      throw err;
    }

    // Tái cấu trúc URL với fallback base
    const primaryBase = primaryUrl.startsWith(ENV.backendUrl)
      ? ENV.backendUrl
      : ENV.aiUrl;
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
        },
        body: JSON.stringify({ refresh_token: refreshToken }),
      });

      if (!response.ok) {
        authStore.clear();
        return false;
      }

      const data = await response.json();
      authStore.accessToken = data.access_token;
      if (data.refresh_token) {
        authStore.refreshToken = data.refresh_token;
      }
      return true;
    } catch {
      authStore.clear();
      return false;
    } finally {
      isRefreshing = false;
      refreshPromise = null;
    }
  })();

  return refreshPromise;
}

// ─────────────────────────────────────────────────────────────────────────────
// Main API fetch — gọi với full URL, tự động attach token + refresh + fallback
// ─────────────────────────────────────────────────────────────────────────────
export const apiFetch = async <T>(
  url: string,
  options: RequestInit = {}
): Promise<T> => {
  const makeRequest = async (token: string | null) => {
    const headers = new Headers(options.headers);
    headers.set("Accept", "application/json");

    if (!(options.body instanceof FormData)) {
      headers.set("Content-Type", "application/json");
    }

    if (token) {
      headers.set("Authorization", `Bearer ${token}`);
    }

    return fetchWithFallback(url, { ...options, headers });
  };

  // First attempt
  let response = await makeRequest(authStore.accessToken);

  // If 401 and we have a refresh token, try to refresh and retry once
  if (response.status === 401 && authStore.refreshToken) {
    const refreshed = await tryRefreshToken();
    if (refreshed) {
      response = await makeRequest(authStore.accessToken);
    } else {
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
    const message =
      typeof payload === "string"
        ? payload
        : payload?.detail || payload?.message || "Request failed";
    throw new ApiError(message, response.status, payload);
  }

  return payload as T;
};
