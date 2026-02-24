const splitList = (value?: string) =>
  value
    ? value
        .split(",")
        .map((item) => item.trim())
        .filter(Boolean)
    : [];

export const ENV = {
  backendUrl: (import.meta.env.VITE_BACKEND_URL as string) || "http://localhost:8000/api/v1",
  aiUrl: (import.meta.env.VITE_AI_URL as string) || "http://localhost:8001/api/v1",
  googleClientId: (import.meta.env.VITE_GOOGLE_CLIENT_ID as string) || "",
  adminEmails: splitList(import.meta.env.VITE_ADMIN_EMAILS as string | undefined),
  superAdminEmails: splitList(import.meta.env.VITE_SUPER_ADMIN_EMAILS as string | undefined)
};
