import { apiFetch } from "./api";
import { ENV } from "./env";
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

export const loginRequest = async (email: string, password: string) => {
  return apiFetch<LoginResponse>(`${ENV.backendUrl}/auth/login`, {
    method: "POST",
    body: JSON.stringify({ email, password })
  });
};

export const googleLoginRequest = async (idToken: string) => {
  return apiFetch<LoginResponse>(`${ENV.backendUrl}/auth/google`, {
    method: "POST",
    body: JSON.stringify({ id_token: idToken, source: "admin" })
  });
};

export const refreshTokenRequest = async (refreshToken: string) => {
  return apiFetch<{ access_token: string; refresh_token: string; token_type: string }>(
    `${ENV.backendUrl}/auth/refresh`,
    {
      method: "POST",
      body: JSON.stringify({ refresh_token: refreshToken })
    }
  );
};

export const getCurrentUser = async () => {
  return apiFetch<UserProfile>(`${ENV.backendUrl}/auth/me`);
};
