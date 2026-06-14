import { describe, expect, it } from "vitest";

import { resolveRole, type UserProfile } from "./auth";

const user = (overrides: Partial<UserProfile> = {}): UserProfile => ({
  id: "user-1",
  email: "learner@example.com",
  username: "learner",
  ...overrides,
});

describe("resolveRole", () => {
  it("prefers an explicit super-admin role", () => {
    expect(resolveRole(user({ role: "super_admin", is_admin: true }))).toBe(
      "super_admin",
    );
  });

  it("accepts the backend admin flag", () => {
    expect(resolveRole(user({ is_admin: true }))).toBe("admin");
  });

  it("does not grant access without a backend role or configured allowlist", () => {
    expect(resolveRole(user())).toBeNull();
  });
});
