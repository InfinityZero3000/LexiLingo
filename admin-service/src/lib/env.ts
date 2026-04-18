const splitList = (value?: string) =>
  value
    ? value
        .split(",")
        .map((item) => item.trim())
        .filter(Boolean)
    : [];

const trimTrailingSlash = (url: string) => url.replace(/\/+$/, "");
const stripApiV1 = (url: string) => trimTrailingSlash(url).replace(/\/api\/v1$/, "");

const env = (import.meta.env.VITE_ENV as string) || "development";
const backendUrl = trimTrailingSlash((import.meta.env.VITE_BACKEND_URL as string) || "http://localhost:8000/api/v1");
const aiUrl = trimTrailingSlash((import.meta.env.VITE_AI_URL as string) || "http://localhost:8001/api/v1");
const useGateway = ((import.meta.env.VITE_USE_GATEWAY as string) || "false").toLowerCase() === "true";
const gatewayBase = stripApiV1(backendUrl);

export const ENV = {
  /** "development" | "production" */
  env,
  isDev:  env === "development",
  isProd: env === "production",

  /** Backend primary URL — local (dev) hoặc Render.com (prod) */
  backendUrl,
  /** Backend fallback URL — thử khi primary không reach được */
  backendUrlFallback: (import.meta.env.VITE_BACKEND_URL_FALLBACK as string) || "",

  /** AI service primary URL */
  aiUrl,
  /** AI service fallback URL */
  aiUrlFallback: (import.meta.env.VITE_AI_URL_FALLBACK as string) || "",

  /** Kong/API Gateway mode */
  useGateway,
  /** Gateway API key for protected routes */
  apiKey: (import.meta.env.VITE_API_KEY as string) || "",
  /** AI admin key required by ai-service /admin/config */
  aiAdminApiKey: (import.meta.env.VITE_AI_ADMIN_API_KEY as string) || "",
  /** Explicit AI admin URL. If omitted, auto-derive based on gateway mode. */
  aiAdminUrl:
    (import.meta.env.VITE_AI_ADMIN_URL as string) ||
    (useGateway
      ? `${gatewayBase}/api/v1/ai-admin`
      : `${stripApiV1(aiUrl)}/api/v1/admin`),

  /** Health endpoints differ between direct services and gateway */
  backendHealthUrl: useGateway ? `${gatewayBase}/backend-health` : `${stripApiV1(backendUrl)}/health`,
  aiHealthUrl: useGateway ? `${gatewayBase}/ai-health` : `${stripApiV1(aiUrl)}/health`,

  googleClientId:   (import.meta.env.VITE_GOOGLE_CLIENT_ID as string) || "",
  adminEmails:      splitList(import.meta.env.VITE_ADMIN_EMAILS as string | undefined),
  superAdminEmails: splitList(import.meta.env.VITE_SUPER_ADMIN_EMAILS as string | undefined),
};
