const splitList = (value?: string) =>
  value
    ? value
        .split(",")
        .map((item) => item.trim())
        .filter(Boolean)
    : [];

const env = (import.meta.env.VITE_ENV as string) || "development";

export const ENV = {
  /** "development" | "production" */
  env,
  isDev:  env === "development",
  isProd: env === "production",

  /** Backend primary URL — local (dev) hoặc Render.com (prod) */
  backendUrl: (import.meta.env.VITE_BACKEND_URL as string) || "http://localhost:8000/api/v1",
  /** Backend fallback URL — thử khi primary không reach được */
  backendUrlFallback: (import.meta.env.VITE_BACKEND_URL_FALLBACK as string) || "",

  /** AI service primary URL */
  aiUrl: (import.meta.env.VITE_AI_URL as string) || "http://localhost:8001/api/v1",
  /** AI service fallback URL */
  aiUrlFallback: (import.meta.env.VITE_AI_URL_FALLBACK as string) || "",

  googleClientId:   (import.meta.env.VITE_GOOGLE_CLIENT_ID as string) || "",
  adminEmails:      splitList(import.meta.env.VITE_ADMIN_EMAILS as string | undefined),
  superAdminEmails: splitList(import.meta.env.VITE_SUPER_ADMIN_EMAILS as string | undefined),
};
