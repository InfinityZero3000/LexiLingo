import React, { useCallback, useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "../components/AuthProvider";
import { ENV } from "../lib/env";
import { useI18n } from "../lib/i18n";

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
        window.google.accounts.id.renderButton(googleBtnRef.current, {
          type: "standard",
          theme: "filled_black",
          size: "large",
          text: "signin_with",
          shape: "pill",
          width: "380",
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
      {/* Decorative blobs */}
      <div className="login-blob login-blob-1" />
      <div className="login-blob login-blob-2" />
      <div className="login-blob login-blob-3" />

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
