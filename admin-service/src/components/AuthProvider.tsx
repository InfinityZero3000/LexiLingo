import React, { createContext, useContext, useEffect, useMemo, useState } from "react";
import { authStore, resolveRole, Role, UserProfile } from "../lib/auth";
import { getCurrentUser, googleLoginRequest, logoutRequest } from "../lib/authApi";
import { endsSession, NoAdminRoleError } from "../lib/api";

type AuthContextValue = {
  user: UserProfile | null;
  role: Role | null;
  loading: boolean;
  signInWithGoogle: (idToken: string) => Promise<Role>;
  signOut: () => void;
  refreshProfile: () => Promise<void>;
};

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

const hasStoredSession = () =>
  Boolean(authStore.accessToken || authStore.refreshToken || authStore.cookieSession);

/** Tells the server too: forgetting the tokens alone would leave the session (and cookie) alive. */
const endServerSession = () => {
  const session = { accessToken: authStore.accessToken, refreshToken: authStore.refreshToken };
  authStore.clear();
  // Best effort: the browser is signed out either way.
  void logoutRequest(session).catch(() => undefined);
};

export const AuthProvider = ({ children }: { children: React.ReactNode }) => {
  const [user, setUser] = useState<UserProfile | null>(authStore.user);
  const [role, setRole] = useState<Role | null>(authStore.role);
  const [loading, setLoading] = useState(hasStoredSession);

  const processLogin = async (accessToken: string, refreshToken: string) => {
    authStore.saveSession(accessToken, refreshToken);
    const profile = await getCurrentUser();
    const resolvedRole = resolveRole(profile);

    if (!resolvedRole) {
      endServerSession();
      throw new Error("Tài khoản không có quyền truy cập Admin Dashboard.");
    }

    authStore.user = profile;
    authStore.role = resolvedRole;
    setUser(profile);
    setRole(resolvedRole);
    return resolvedRole;
  };

  const signInWithGoogle = async (idToken: string) => {
    setLoading(true);
    try {
      const login = await googleLoginRequest(idToken);
      return await processLogin(login.access_token, login.refresh_token);
    } finally {
      setLoading(false);
    }
  };

  const signOut = () => {
    endServerSession();
    setUser(null);
    setRole(null);
    // Revoke Google session so user can pick account again
    if (window.google?.accounts?.id) {
      window.google.accounts.id.disableAutoSelect();
    }
  };

  const refreshProfile = async () => {
    if (!hasStoredSession()) return;
    setLoading(true);
    try {
      const profile = await getCurrentUser();
      const resolvedRole = resolveRole(profile);
      if (!resolvedRole) {
        endServerSession();
        setUser(null);
        setRole(null);
        throw new Error("Tài khoản không có quyền truy cập Admin Dashboard.");
      }
      authStore.user = profile;
      authStore.role = resolvedRole;
      setUser(profile);
      setRole(resolvedRole);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    let cancelled = false;

    const bootstrapSession = async () => {
      if (!hasStoredSession()) {
        setLoading(false);
        return;
      }

      setLoading(true);
      try {
        const profile = await getCurrentUser();
        const resolvedRole = resolveRole(profile);

        if (!resolvedRole) {
          throw new NoAdminRoleError("Tài khoản không có quyền truy cập Admin Dashboard.");
        }

        authStore.user = profile;
        authStore.role = resolvedRole;

        if (!cancelled) {
          setUser(profile);
          setRole(resolvedRole);
        }
      } catch (error) {
        // A restart or a dropped connection says nothing about the session:
        // keep the tokens so a reload picks it up again.
        // Signed in but no longer an admin: end it on the server too.
        if (error instanceof NoAdminRoleError) endServerSession();
        else if (endsSession(error)) authStore.clear();
        if (!cancelled) {
          setUser(null);
          setRole(null);
        }
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    };

    void bootstrapSession();

    return () => {
      cancelled = true;
    };
  }, []);

  const value = useMemo(
    () => ({ user, role, loading, signInWithGoogle, signOut, refreshProfile }),
    [user, role, loading]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
};

export const useAuth = () => {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within AuthProvider");
  return ctx;
};
