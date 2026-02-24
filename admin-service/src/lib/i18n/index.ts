/**
 * i18n System for LexiLingo Admin
 * Supports Vietnamese (vi) and English (en)
 */
import React, { createContext, useContext, useState, useCallback, useMemo, useEffect } from "react";
import vi, { type Translations } from "./vi";
import en from "./en";

export type Locale = "vi" | "en";

const LOCALE_KEY = "lexi_admin_locale";

const translations: Record<Locale, Translations> = { vi, en };

export const localeNames: Record<Locale, string> = {
  vi: "Tiếng Việt",
  en: "English",
};

type I18nContextValue = {
  locale: Locale;
  t: Translations;
  setLocale: (locale: Locale) => void;
  localeNames: Record<Locale, string>;
};

const I18nContext = createContext<I18nContextValue | undefined>(undefined);

function getSavedLocale(): Locale {
  try {
    const saved = localStorage.getItem(LOCALE_KEY);
    if (saved === "vi" || saved === "en") return saved;
  } catch {}
  return "vi"; // Default: Vietnamese
}

export const I18nProvider = ({ children }: { children: React.ReactNode }) => {
  const [locale, setLocaleState] = useState<Locale>(getSavedLocale);

  const setLocale = useCallback((newLocale: Locale) => {
    setLocaleState(newLocale);
    try { localStorage.setItem(LOCALE_KEY, newLocale); } catch {}
  }, []);

  const t = translations[locale];

  const value = useMemo(
    () => ({ locale, t, setLocale, localeNames }),
    [locale, t, setLocale]
  );

  return React.createElement(I18nContext.Provider, { value }, children);
};

export const useI18n = () => {
  const ctx = useContext(I18nContext);
  if (!ctx) throw new Error("useI18n must be used within I18nProvider");
  return ctx;
};

// Re-export types
export type { Translations };
