import { Linking } from 'react-native';
import * as WebBrowser from 'expo-web-browser';

// The legal texts live on the website only (Scott 2026-10-26, backlog walk):
// the in-app copies had already drifted from it (two different contact
// addresses). Same env-driven host as the share links; the askandgo domain
// will change this one constant.
const WEB_HOST = process.env.EXPO_PUBLIC_JUNTO_WEB_HOST ?? 'getjunto.app';

export type LegalPage = 'terms' | 'privacy';

export function legalUrl(page: LegalPage): string {
  return `https://${WEB_HOST}/legal/${page}`;
}

// In-app browser sheet; plain system browser if it is unavailable.
export async function openLegalPage(page: LegalPage): Promise<void> {
  const url = legalUrl(page);
  try {
    await WebBrowser.openBrowserAsync(url);
  } catch {
    Linking.openURL(url).catch(() => {});
  }
}
