import { create } from "zustand";

export type Theme = "light" | "dark";

const KEY = "lexilingo-admin-theme";

const initial = (): Theme => {
  try {
    const saved = localStorage.getItem(KEY);
    if (saved === "light" || saved === "dark") return saved;
  } catch {}
  return window.matchMedia?.("(prefers-color-scheme: dark)").matches ? "dark" : "light";
};

const apply = (theme: Theme) => {
  document.documentElement.dataset.theme = theme;
};

export const useTheme = create<{ theme: Theme; toggle: () => void }>((set, get) => {
  const theme = initial();
  apply(theme);
  return {
    theme,
    toggle: () => {
      const next: Theme = get().theme === "dark" ? "light" : "dark";
      apply(next);
      try { localStorage.setItem(KEY, next); } catch {}
      set({ theme: next });
    },
  };
});
