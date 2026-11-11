import { useQuery } from "@tanstack/react-query";
import { getMyPermissions } from "./rbacApi";
import { authStore } from "./auth";

/** What the signed-in admin may do. While loading, everything shows so the UI never flickers empty; the server still decides. */
export const usePermissions = () => {
  const { data } = useQuery({ queryKey: ["my-permissions"], queryFn: getMyPermissions, staleTime: 60_000, enabled: Boolean(authStore.accessToken) });
  const can = (slug: string) => {
    if (!data || data.all) return true;
    const [resource] = slug.split(":");
    return data.permissions.includes(slug) || data.permissions.includes(`${resource}:manage`);
  };
  return { can };
};
