import React, { createContext, useContext, useEffect, useMemo, useState } from "react";
import { authStore, resolveRole, Role, UserProfile } from "../lib/auth";
import { getCurrentUser, loginRequest, googleLoginRequest } from "../lib/authApi";

type AuthContextValue = {
  user: UserProfile | null;
  role: Role | null;
  loading: boolean;
  signIn: (email: string, password: string) => Promise<Role>;
  signInWithGoogle: (idToken: string) => Promise<Role>;
  signOut: () => void;
  refreshProfile: () => Promise<void>;
};

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export const AuthProvider = ({ children }: { children: React.ReactNode }) => {
  const [user, setUser] = useState<UserProfile | null>(authStore.user);
  const [role, setRole] = useState<Role | null>(authStore.role);
  const [loading, setLoading] = useState(false);

  const processLogin = async (accessToken: string, refreshToken: string) => {
    authStore.accessToken = accessToken;
    authStore.refreshToken = refreshToken;
    const profile = await getCurrentUser();
    const resolvedRole = resolveRole(profile);

    if (!resolvedRole) {
      authStore.clear();
      throw new Error("Tài khoản không có quyền truy cập Admin Dashboard.");
    }

    authStore.user = profile;
    authStore.role = resolvedRole;
    setUser(profile);
    setRole(resolvedRole);
    return resolvedRole;
  };

  const signIn = async (email: string, password: string) => {
    setLoading(true);
    try {
      const login = await loginRequest(email, password);
      return await processLogin(login.access_token, login.refresh_token);
    } finally {
      setLoading(false);
    }
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
    authStore.clear();
    setUser(null);
    setRole(null);
    // Revoke Google session so user can pick account again
    if (window.google?.accounts?.id) {
      window.google.accounts.id.disableAutoSelect();
    }
  };

  const refreshProfile = async () => {
    if (!authStore.accessToken) return;
    setLoading(true);
    try {
      const profile = await getCurrentUser();
      const resolvedRole = resolveRole(profile);
      authStore.user = profile;
      authStore.role = resolvedRole;
      setUser(profile);
      setRole(resolvedRole);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (authStore.accessToken && !user) {
      void refreshProfile();
    }
  }, [user]);

  const value = useMemo(
    () => ({ user, role, loading, signIn, signInWithGoogle, signOut, refreshProfile }),
    [user, role, loading]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
};

export const useAuth = () => {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within AuthProvider");
  return ctx;
};
