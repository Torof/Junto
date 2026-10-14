import i18n from 'i18next';
import { initReactI18next } from 'react-i18next';
import { getLocales } from 'expo-localization';
import AsyncStorage from '@react-native-async-storage/async-storage';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';

import fr from './fr.json';
import en from './en.json';

// Multilingual foundation (Scott 2026-10-14). The app language is resolved
// from a local PREFERENCE: 'auto' (the phone's language, narrowed to what we
// ship) or an explicit choice from Settings. The EFFECTIVE language is what
// i18next and dayjs run on; it is also mirrored to users.language (00445) by
// useLanguageSync so the server can one day compose notifications in the
// reader's language. Adding a language = a JSON file + its dayjs locale +
// one entry in SUPPORTED_LANGUAGES (+ the DB CHECK in 00445).
export const SUPPORTED_LANGUAGES = ['fr', 'en'] as const;
export type AppLanguage = (typeof SUPPORTED_LANGUAGES)[number];
export type LanguagePreference = 'auto' | AppLanguage;

const STORAGE_KEY = 'junto.language';
const FALLBACK: AppLanguage = 'en';

function isSupported(code: string | null | undefined): code is AppLanguage {
  return !!code && (SUPPORTED_LANGUAGES as readonly string[]).includes(code);
}

// First device locale we ship; English for everyone else (an Italian or a
// German gets English until their language exists).
export function deviceLanguage(): AppLanguage {
  for (const locale of getLocales()) {
    if (isSupported(locale.languageCode)) return locale.languageCode;
  }
  return FALLBACK;
}

export function resolveLanguage(pref: LanguagePreference): AppLanguage {
  return pref === 'auto' ? deviceLanguage() : pref;
}

let preference: LanguagePreference = 'auto';

// dayjs has no event bus: the global locale follows the app language so no
// screen has to pin `.locale('fr')` any more.
function applyLocale(lang: AppLanguage): void {
  dayjs.locale(lang);
}

const initial = deviceLanguage();

i18n.use(initReactI18next).init({
  resources: {
    fr: { translation: fr },
    en: { translation: en },
  },
  lng: initial,
  fallbackLng: FALLBACK,
  interpolation: {
    escapeValue: false,
  },
});
applyLocale(initial);

// Stored preference, applied as soon as storage answers (a few ms after the
// synchronous init above — only a user who chose a language DIFFERENT from
// the phone's sees the switch, and only on cold start).
export async function loadLanguagePreference(): Promise<void> {
  try {
    const raw = await AsyncStorage.getItem(STORAGE_KEY);
    if (raw === 'auto' || isSupported(raw)) {
      preference = raw;
      const lang = resolveLanguage(preference);
      applyLocale(lang);
      if (lang !== i18n.language) await i18n.changeLanguage(lang);
    }
  } catch {
    // Storage unavailable — stay on the device language.
  }
}
void loadLanguagePreference();

export function getLanguagePreference(): LanguagePreference {
  return preference;
}

export async function setLanguagePreference(pref: LanguagePreference): Promise<void> {
  preference = pref;
  try {
    await AsyncStorage.setItem(STORAGE_KEY, pref);
  } catch {
    // Not persisted, still applied for this session.
  }
  const lang = resolveLanguage(pref);
  applyLocale(lang);
  if (lang !== i18n.language) await i18n.changeLanguage(lang);
}

export default i18n;
