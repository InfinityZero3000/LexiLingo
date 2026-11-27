import { ENV } from "./env";

const ADMIN_HOST = "admin.lexilingo.me";

/**
 * Where the refresh token lives. "cookie" keeps it in an HttpOnly cookie that scripts
 * cannot read. That only works when the browser sends the cookie to the API, so
 * previews and a local page pointed at a remote API keep the stored token.
 */
export const sessionTransport = (): "cookie" | "token" => {
  try {
    const page = window.location.hostname;
    const api = new URL(ENV.backendUrl).hostname;
    if (page && api === page) return "cookie";
    if (page === ADMIN_HOST && api.endsWith(".lexilingo.me")) return "cookie";
  } catch {
    // A relative or malformed API URL: keep the stored token.
  }
  return "token";
};

export const credentialsFor = (transport: "cookie" | "token"): RequestInit =>
  transport === "cookie" ? { credentials: "include" } : {};
