import React from "react";
import { Navigate, Outlet } from "react-router-dom";
import { useAuth } from "./AuthProvider";
import { authStore } from "../lib/auth";

export const RequireAuth = () => {
  const { user, loading } = useAuth();

  if (loading && authStore.accessToken) {
    return <div className="loading">Đang xác thực phiên...</div>;
  }

  if (!user) {
    return <Navigate to="/login" replace />;
  }

  return <Outlet />;
};
