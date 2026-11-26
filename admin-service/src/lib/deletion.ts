import { ApiError } from "./api";
import type { Translations } from "./i18n/vi";

export const fillText = (template: string, values: Record<string, string | number>): string =>
  template.replace(/\{(\w+)\}/g, (whole, key) => (key in values ? String(values[key]) : whole));

/** The server's refusal in the admin's language; any other error keeps its own message. */
export const describeDeletionError = (error: unknown, t: Translations): string => {
  const details = error instanceof ApiError ? error.payload?.error?.details : undefined;
  if (details?.reason === "published") return t.deletion.published;
  if (details?.reason === "in_use") {
    const labels: Record<string, string> = t.deletion.usage;
    const used = Object.entries(details.usage ?? {})
      .map(([key, count]) => fillText(labels[key] ?? `{n} ${key}`, { n: Number(count) }))
      .join(", ");
    return fillText(t.deletion.inUse, { used });
  }
  return error instanceof Error && error.message ? error.message : t.common.deleteFailed;
};
