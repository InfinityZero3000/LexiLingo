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

/**
 * Attempt to refresh the access token using the stored refresh token.
 * Returns true if refresh succeeded, false otherwise.
 */
async function tryRefreshToken(): Promise<boolean> {
  const refreshToken = authStore.refreshToken;
  if (!refreshToken) return false;

  // If already refreshing, wait for the existing promise
  if (isRefreshing && refreshPromise) {
    return refreshPromise;
  }

  isRefreshing = true;
  refreshPromise = (async () => {
    try {
      const response = await fetch(`${ENV.backendUrl}/auth/refresh`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        body: JSON.stringify({ refresh_token: refreshToken }),
      });

      if (!response.ok) {
        // Refresh failed — clear session
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

    return fetch(url, { ...options, headers });
  };

  // First attempt
  let response = await makeRequest(authStore.accessToken);

  // If 401 and we have a refresh token, try to refresh and retry once
  if (response.status === 401 && authStore.refreshToken) {
    const refreshed = await tryRefreshToken();
    if (refreshed) {
      // Retry with the new access token
      response = await makeRequest(authStore.accessToken);
    } else {
      // Refresh failed, redirect to login
      window.location.href = "/login";
      throw new ApiError("Session expired. Please log in again.", 401);
    }
  }

  const contentType = response.headers.get("content-type") || "";
  const payload = contentType.includes("application/json")
    ? await response.json()
    : await response.text();

  if (!response.ok) {
    // If still 401 after refresh attempt, redirect to login
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
