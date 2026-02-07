import React from "react";
import { Navigate, Outlet } from "react-router-dom";
import { Role } from "../lib/auth";
import { useAuth } from "./AuthProvider";

export const RequireRole = ({ allowed }: { allowed: Role[] }) => {
  const { role } = useAuth();

  if (!role || !allowed.includes(role)) {
    return <Navigate to="/no-access" replace />;
  }

  return <Outlet />;
};
