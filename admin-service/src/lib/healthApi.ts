import { ENV } from "./env";

function _healthHeaders(): Record<string, string> | undefined {
  return ENV.apiKey ? { "X-Api-Key": ENV.apiKey } : undefined;
}

export const checkBackendHealth = (): Promise<Response> =>
  fetch(ENV.backendHealthUrl, { headers: _healthHeaders() });

export const checkAiHealth = (): Promise<Response> =>
  fetch(ENV.aiHealthUrl, { headers: _healthHeaders() });
