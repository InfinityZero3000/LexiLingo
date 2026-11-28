import { describe, expect, it } from "vitest";
import { resolveRole } from "./auth";

const profile = (role_slug: string, is_admin: boolean, is_super_admin = false) => ({
  id: "1", email: "someone@example.com", username: "someone", role_slug, is_admin, is_super_admin,
});

describe("resolveRole", () => {
  it("lets a custom admin-level role into the admin web", () => {
    expect(resolveRole(profile("editor", true))).toBe("admin");
  });

  it("sends a session that did not sign in with Google back to sign-in", () => {
    expect(resolveRole({ ...profile("super_admin", true, true), admin_access: false })).toBeNull();
    expect(resolveRole({ ...profile("admin", true), admin_access: true })).toBe("admin");
  });

  it("keeps the built-in roles as they were", () => {
    expect(resolveRole(profile("admin", true))).toBe("admin");
    expect(resolveRole(profile("super_admin", true, true))).toBe("super_admin");
    expect(resolveRole(profile("user", false))).toBeNull();
  });
});
