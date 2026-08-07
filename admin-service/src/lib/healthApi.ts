import { ENV } from "./env";

function _healthHeaders(): Record<string, string> | undefined {
  return ENV.apiKey ? { "X-Api-Key": ENV.apiKey } : undefined;
}

function _adminHeaders(accessToken?: string): Record<string, string> {
  return {
    ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
    ...(ENV.apiKey ? { "X-Api-Key": ENV.apiKey } : {}),
  };
}

export const checkBackendHealth = (): Promise<Response> =>
  fetch(ENV.backendHealthUrl, { headers: _healthHeaders() });

export const checkAiHealth = (): Promise<Response> =>
  fetch(ENV.aiHealthUrl, { headers: _healthHeaders() });

export const getAiConfig = (accessToken?: string): Promise<Response> =>
  fetch(`${ENV.aiAdminUrl}/config`, { headers: _adminHeaders(accessToken) });

export const updateAiConfig = (body: unknown, accessToken?: string): Promise<Response> =>
  fetch(`${ENV.aiAdminUrl}/config`, {
    method: "PUT",
    headers: { "Content-Type": "application/json", ..._adminHeaders(accessToken) },
    body: JSON.stringify(body),
  });
