import { ApiError } from "./api";
import { updateUserRole } from "./userManagementApi";
import type { ConfirmOptions } from "../components/ConfirmDialog";

export type RoleTarget = { slug: string } | { level: number };

export type RoleGrantText = {
  passwordTitle: string;
  passwordMessage: string;
  passwordConfirm: string;
  googleRequired: string;
};

const refusalReason = (error: unknown): string | undefined =>
  error instanceof ApiError ? error.payload?.error?.details?.reason : undefined;

/**
 * Changes a user's role. Admins sign in with Google only, so the server refuses an admin
 * role for an account that has never used Google, and asks before it removes a password.
 * Resolves false when the super admin declines that question.
 */
export async function assignRole(
  userId: string,
  target: RoleTarget,
  confirm: (options: ConfirmOptions) => Promise<boolean>,
  text: RoleGrantText,
): Promise<boolean> {
  const send = (extra: { remove_password?: boolean } = {}) => updateUserRole(userId, { ...target, ...extra });
  try {
    await send();
    return true;
  } catch (error) {
    const reason = refusalReason(error);
    if (reason === "google_sign_in_required") throw new Error(text.googleRequired);
    if (reason !== "password_will_be_removed") throw error;
    const email = (error as ApiError).payload?.error?.details?.email ?? "";
    const ok = await confirm({
      title: text.passwordTitle,
      message: text.passwordMessage.replace("{email}", email),
      confirmLabel: text.passwordConfirm,
      danger: true,
    });
    if (!ok) return false;
    await send({ remove_password: true });
    return true;
  }
}
