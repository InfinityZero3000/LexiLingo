import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
export default defineConfig({
    plugins: [react()],
    server: {
        port: 5173,
        headers: {
            // Only allow resources from own origin + Google GSI + fonts + backend API
            "Content-Security-Policy": [
                "default-src 'self'",
                "script-src 'self' 'unsafe-inline' 'unsafe-eval' https://accounts.google.com https://apis.google.com",
                "style-src 'self' 'unsafe-inline' https://accounts.google.com https://fonts.googleapis.com",
                "font-src 'self' https://fonts.gstatic.com",
                "img-src 'self' data: https://*.googleusercontent.com https://accounts.google.com",
                "frame-src https://accounts.google.com",
                "connect-src 'self' http://localhost:8000 http://localhost:8001 https://accounts.google.com",
            ].join("; "),
            // Prevent clickjacking — no embedding in iframes from other origins
            "X-Frame-Options": "SAMEORIGIN",
            // Prevent MIME type sniffing
            "X-Content-Type-Options": "nosniff",
            // Only send origin as referrer
            "Referrer-Policy": "strict-origin-when-cross-origin",
            // Restrict browser features
            "Permissions-Policy": "camera=(), microphone=(), geolocation=(), payment=()",
        }
    }
});
