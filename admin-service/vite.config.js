import { defineConfig, loadEnv } from "vite";
import react from "@vitejs/plugin-react";
const DEFAULT_API_URL = "https://api.lexilingo.me/api/v1";
const originOf = (value) => {
    if (!value)
        return null;
    try {
        return new URL(value).origin;
    }
    catch {
        return null;
    }
};
const unique = (items) => [...new Set(items.filter(Boolean))];
const buildCsp = (env) => {
    const backendUrl = env.VITE_BACKEND_URL || DEFAULT_API_URL;
    const aiUrl = env.VITE_AI_URL || DEFAULT_API_URL;
    const aiAdminUrl = env.VITE_AI_ADMIN_URL || "";
    const connectSources = unique([
        "'self'",
        originOf(backendUrl),
        originOf(aiUrl),
        originOf(aiAdminUrl),
        "https://accounts.google.com",
        "https://oauth2.googleapis.com",
    ]);
    return [
        "default-src 'self'",
        "base-uri 'self'",
        "object-src 'none'",
        "script-src 'self' 'unsafe-inline' https://accounts.google.com https://apis.google.com",
        "style-src 'self' 'unsafe-inline' https://accounts.google.com https://fonts.googleapis.com",
        "font-src 'self' https://fonts.gstatic.com",
        "img-src 'self' data: https://*.googleusercontent.com https://accounts.google.com https://cdn.jsdelivr.net",
        "frame-src https://accounts.google.com",
        `connect-src ${connectSources.join(" ")}`,
        "form-action 'self'",
    ].join("; ");
};
export default defineConfig(({ mode }) => {
    const env = loadEnv(mode, process.cwd(), "");
    return {
        plugins: [react()],
        server: {
            port: 5176,
            headers: {
                "Cross-Origin-Opener-Policy": "unsafe-none",
                "Content-Security-Policy": buildCsp(env),
                "X-Frame-Options": "SAMEORIGIN",
                "X-Content-Type-Options": "nosniff",
                "Referrer-Policy": "strict-origin-when-cross-origin",
                "Permissions-Policy": "camera=(), microphone=(), geolocation=(), payment=()",
            },
        },
    };
});
