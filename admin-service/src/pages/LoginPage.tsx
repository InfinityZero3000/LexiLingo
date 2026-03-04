import React, { useCallback, useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "../components/AuthProvider";
import { ENV } from "../lib/env";
import { useI18n } from "../lib/i18n";
import GlobeBackground from "../components/login-globe/GlobeBackground";

export const LoginPage = () => {
  const { signInWithGoogle, loading } = useAuth();
  const navigate = useNavigate();
  const [error, setError] = useState<string | null>(null);
  const googleBtnRef = useRef<HTMLDivElement>(null);
  const [gsiReady, setGsiReady] = useState(false);
  const { t } = useI18n();

  const handleGoogleCallback = useCallback(
    async (response: CredentialResponse) => {
      setError(null);
      try {
        const role = await signInWithGoogle(response.credential);
        navigate(role === "super_admin" ? "/super" : "/admin", { replace: true });
      } catch (err: any) {
        const msg = err?.message || "";
        if (msg.includes("quyền") || msg.includes("admin") || msg.includes("Admin")) {
          setError(t.login.noPermission);
        } else if (msg.includes("inactive")) {
          setError(t.login.accountDisabled);
        } else {
          setError(msg || t.login.loginFailed);
        }
      }
    },
    [signInWithGoogle, navigate]
  );

  useEffect(() => {
    const clientId = ENV.googleClientId;
    if (!clientId) {
      setError(t.login.missingClientId);
      return;
    }

    const initGsi = () => {
      if (!window.google?.accounts?.id) return false;
      window.google.accounts.id.initialize({
        client_id: clientId,
        callback: handleGoogleCallback,
        auto_select: false,
        cancel_on_tap_outside: true,
        context: "signin",
        ux_mode: "popup",
      });
      if (googleBtnRef.current) {
        // Use container width capped at 360px so button fits all screen sizes
        const containerW = Math.min(
          googleBtnRef.current.offsetWidth || 300,
          360
        );
        window.google.accounts.id.renderButton(googleBtnRef.current, {
          type: "standard",
          theme: "filled_black",
          size: "large",
          text: "signin_with",
          shape: "pill",
          width: String(containerW),
          logo_alignment: "left",
        });
      }
      setGsiReady(true);
      return true;
    };

    if (!initGsi()) {
      // GSI script hasn't loaded yet — poll until ready
      const interval = setInterval(() => {
        if (initGsi()) clearInterval(interval);
      }, 200);
      const timeout = setTimeout(() => {
        clearInterval(interval);
        if (!gsiReady) setError(t.login.googleLoadFailed);
      }, 10000);
      return () => {
        clearInterval(interval);
        clearTimeout(timeout);
      };
    }
  }, [handleGoogleCallback]);

  return (
    <div className="login-page">
      {/* 3D Globe background */}
      <GlobeBackground />

      {/* Top-right info bar */}
      <div className="login-topbar">
        <a
          className="login-topbar-link"
          href="https://github.com/InfinityZero3000/LexiLingo"
          target="_blank"
          rel="noreferrer"
          aria-label="GitHub"
          title="GitHub Repository"
        >
          {/* GitHub */}
          <svg width="17" height="17" viewBox="0 0 24 24" fill="currentColor">
            <path d="M12 2C6.477 2 2 6.477 2 12c0 4.418 2.865 8.167 6.839 9.49.5.092.682-.217.682-.482 0-.237-.009-.868-.013-1.703-2.782.604-3.369-1.34-3.369-1.34-.454-1.154-1.11-1.462-1.11-1.462-.908-.62.069-.608.069-.608 1.003.07 1.531 1.03 1.531 1.03.892 1.529 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.11-4.555-4.943 0-1.091.39-1.984 1.029-2.683-.103-.253-.446-1.27.098-2.647 0 0 .84-.269 2.75 1.025A9.564 9.564 0 0 1 12 6.844a9.59 9.59 0 0 1 2.504.337c1.909-1.294 2.747-1.025 2.747-1.025.546 1.377.203 2.394.1 2.647.64.699 1.028 1.592 1.028 2.683 0 3.842-2.339 4.687-4.566 4.935.359.309.678.919.678 1.852 0 1.336-.012 2.415-.012 2.744 0 .267.18.579.688.481C19.138 20.163 22 16.417 22 12c0-5.523-4.477-10-10-10z" />
          </svg>
          <span>GitHub</span>
        </a>

        <div className="login-topbar-sep" />

        <a
          className="login-topbar-link"
          href="/docs"
          target="_blank"
          rel="noreferrer"
          aria-label="Docs"
          title="Documentation"
        >
          {/* Book / Docs */}
          <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20" />
            <path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z" />
            <path d="M8 7h8M8 11h6" />
          </svg>
          <span>Docs</span>
        </a>

        <div className="login-topbar-sep" />

        <a
          className="login-topbar-link"
          href="https://huggingface.co/InfinityZero3000"
          target="_blank"
          rel="noreferrer"
          aria-label="Hugging Face"
          title="Hugging Face Models"
        >
          {/* Hugging Face emoji-style icon */}
          <svg width="17" height="17" viewBox="0 0 24 24" fill="currentColor">
            <path d="M12 2a10 10 0 1 0 10 10A10 10 0 0 0 12 2zm-1 13.5a1.5 1.5 0 1 1 3 0 1.5 1.5 0 0 1-3 0zm-3.5-1a1 1 0 1 1 2 0 1 1 0 0 1-2 0zm7 0a1 1 0 1 1 2 0 1 1 0 0 1-2 0zm1.07-4.36a5.28 5.28 0 0 1-7.14 0 .75.75 0 1 1 1.01-1.11 3.78 3.78 0 0 0 5.12 0 .75.75 0 0 1 1.01 1.11z" />
          </svg>
          <span>HF Models</span>
        </a>

        <div className="login-topbar-sep" />

        <a
          className="login-topbar-link"
          href="mailto:nhthang312@gmail.com"
          aria-label="Email"
          title="Contact"
        >
          {/* Mail */}
          <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <rect x="2" y="4" width="20" height="16" rx="2" />
            <path d="m2 7 10 7 10-7" />
          </svg>
          <span>Contact</span>
        </a>

        <div className="login-topbar-sep" />

        <a
          className="login-topbar-link"
          href="https://discord.gg/"
          target="_blank"
          rel="noreferrer"
          aria-label="Discord"
          title="Discord Community"
        >
          {/* Discord */}
          <svg width="17" height="17" viewBox="0 0 24 24" fill="currentColor">
            <path d="M20.317 4.37a19.791 19.791 0 0 0-4.885-1.515.074.074 0 0 0-.079.037c-.21.375-.444.864-.608 1.25a18.27 18.27 0 0 0-5.487 0 12.64 12.64 0 0 0-.617-1.25.077.077 0 0 0-.079-.037A19.736 19.736 0 0 0 3.677 4.37a.07.07 0 0 0-.032.027C.533 9.046-.32 13.58.099 18.057c.002.022.015.043.033.054a19.9 19.9 0 0 0 5.993 3.03.078.078 0 0 0 .084-.028 14.09 14.09 0 0 0 1.226-1.994.076.076 0 0 0-.041-.106 13.107 13.107 0 0 1-1.872-.892.077.077 0 0 1-.008-.128 10.2 10.2 0 0 0 .372-.292.074.074 0 0 1 .077-.01c3.928 1.793 8.18 1.793 12.062 0a.074.074 0 0 1 .078.01c.12.098.246.198.373.292a.077.077 0 0 1-.006.127 12.299 12.299 0 0 1-1.873.892.077.077 0 0 0-.041.107c.36.698.772 1.362 1.225 1.993a.076.076 0 0 0 .084.028 19.839 19.839 0 0 0 6.002-3.03.077.077 0 0 0 .032-.054c.5-5.177-.838-9.674-3.549-13.66a.061.061 0 0 0-.031-.03zM8.02 15.33c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.956-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.956 2.418-2.157 2.418zm7.975 0c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.955-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.946 2.418-2.157 2.418z" />
          </svg>
          <span>Discord</span>
        </a>
      </div>

      {/* Hero text — left side */}
      <div className="login-hero">
        <p className="login-hero-eyebrow">AI-Powered English Learning</p>
        <h2 className="login-hero-title">
          Empower every<br />
          learner with <span className="login-hero-accent">intelligent</span><br />
          guidance
        </h2>
        <p className="login-hero-desc">
          Adaptive lessons, real-time pronunciation feedback,
          and a knowledge graph that grows with each student.
        </p>
        <div className="login-hero-features">
          <div className="login-hero-feature">
            <span className="login-hero-feature-icon">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M12 20h9" /><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z" />
              </svg>
            </span>
            <span>Personalized learning paths</span>
          </div>
          <div className="login-hero-feature">
            <span className="login-hero-feature-icon">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M12 2a10 10 0 1 0 10 10" /><path d="M12 6v6l4 2" />
              </svg>
            </span>
            <span>Spaced-repetition vocabulary</span>
          </div>
          <div className="login-hero-feature">
            <span className="login-hero-feature-icon">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
                <circle cx="12" cy="12" r="10" />
                <path d="M8.56 2.75c4.37 6.03 6.02 9.42 8.03 17.72m2.54-15.38c-3.72 4.35-8.94 5.66-16.88 5.85m19.5 1.9c-3.5-.93-6.63-.82-8.94 0-2.58.92-5.01 2.86-7.44 6.32" />
              </svg>
            </span>
            <span>Multi-language AI tutor (Qwen · Gemini)</span>
          </div>
        </div>
        <div className="login-hero-stats">
          <div className="login-hero-stat">
            <span className="login-hero-stat-num">50K+</span>
            <span className="login-hero-stat-label">Learners</span>
          </div>
          <div className="login-hero-stat-divider" />
          <div className="login-hero-stat">
            <span className="login-hero-stat-num">200+</span>
            <span className="login-hero-stat-label">Lessons</span>
          </div>
          <div className="login-hero-stat-divider" />
          <div className="login-hero-stat">
            <span className="login-hero-stat-num">98%</span>
            <span className="login-hero-stat-label">Satisfaction</span>
          </div>
        </div>
      </div>

      <div className="login-card">
        <div className="login-header">
          <div className="login-brand">
            <div className="login-brand-mark">
              <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20" />
                <path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z" />
                <path d="M8 7h8M8 11h6" />
              </svg>
            </div>
            <div>
              <div className="login-brand-title">LexiLingo</div>
              <div className="login-brand-sub">Admin Console</div>
            </div>
          </div>
        </div>

        <div className="login-body">
          <h1 className="login-title">{t.login.welcome}</h1>
          <p className="login-subtitle">
            {t.login.loginWithGoogle}
          </p>

          {/* Google Sign-In button rendered by GSI */}
          <div className="google-signin-area">
            {loading ? (
              <div className="login-loading">
                <span className="login-spinner" />
                <span>{t.login.authenticating}</span>
              </div>
            ) : (
              <div ref={googleBtnRef} className="google-btn-container" />
            )}
          </div>

          {error && (
            <div className="login-error">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <circle cx="12" cy="12" r="10" />
                <line x1="15" y1="9" x2="9" y2="15" />
                <line x1="9" y1="9" x2="15" y2="15" />
              </svg>
              <span>{error}</span>
            </div>
          )}
        </div>

        <div className="login-footer">
          <div className="login-security-badges">
            <div className="security-badge">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
              </svg>
              <span>{t.login.googleOAuth}</span>
            </div>
            <div className="security-badge">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
                <path d="M7 11V7a5 5 0 0 1 10 0v4" />
              </svg>
              <span>{t.login.adminOnly}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
