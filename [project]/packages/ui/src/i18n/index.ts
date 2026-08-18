import { createMemo, createSignal } from "solid-js";
import { pl } from "./pl";
import { en } from "./en";

export type Locale = "pl" | "en";
export type TranslationKey = keyof typeof pl;

const dictionaries: Record<Locale, Record<TranslationKey, string>> = { pl, en };

const DEFAULT_LOCALE: Locale = "pl";

const [locale, setLocaleSignal] = createSignal<Locale>(DEFAULT_LOCALE);

export function setLocale(next: Locale): void {
  setLocaleSignal(next);
}

export function getLocale(): Locale {
  return locale();
}

/** Reactive translation lookup - falls back to the key itself if missing. */
export const t = createMemo(() => {
  const dictionary = dictionaries[locale()];
  return (key: string): string => dictionary[key as TranslationKey] ?? key;
});
