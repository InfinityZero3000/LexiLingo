import { apiFetch } from "./api";
import { ENV } from "./env";
import { credentialsFor, sessionTransport } from "./sessionTransport";
import { UserProfile } from "./auth";

export type LoginResponse = {
  access_token: string;
  refresh_token: string;
  token_type: string;
  user_id: string;
  username: string;
  email: string;
  role?: string;
};

export const googleLoginRequest = async (idToken: string) => {
  const transport = sessionTransport();
  return apiFetch<LoginResponse>(`${ENV.backendUrl}/auth/google`, {
    skipAuth: true,
    method: "POST",
    ...credentialsFor(transport),
    body: JSON.stringify({ id_token: idToken, source: "admin", session: transport })
  });
};

/** Revokes the session on the server and, in cookie mode, clears the cookie. */
export const logoutRequest = async (session: { accessToken: string | null; refreshToken: string | null }) => {
  const transport = sessionTransport();
  return apiFetch<{ message: string }>(`${ENV.backendUrl}/auth/logout`, {
    skipAuth: true,
    method: "POST",
    keepalive: true,
    ...credentialsFor(transport),
    headers: session.accessToken ? { Authorization: `Bearer ${session.accessToken}` } : {},
    body: JSON.stringify({
      ...(session.refreshToken ? { refresh_token: session.refreshToken } : {}),
      session: transport
    })
  });
};

export const getCurrentUser = async () => {
  return apiFetch<UserProfile>(`${ENV.backendUrl}/auth/me`);
};
