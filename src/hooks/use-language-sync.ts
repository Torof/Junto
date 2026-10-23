import { useEffect, useRef } from 'react';
import { useTranslation } from 'react-i18next';
import { useAuth } from '@/hooks/use-auth';
import { userService } from '@/services/user-service';

// Mirrors the EFFECTIVE app language to users.language (00445) — once per
// session and per language, so the server knows which language to speak to
// this user (notifications, later). Fire-and-forget: a failure is retried at
// the next change, never surfaced.
export function useLanguageSync(): void {
  const { session } = useAuth();
  const { i18n } = useTranslation();
  const synced = useRef<string | null>(null);

  const userId = session?.user?.id ?? null;
  const language = i18n.language;

  useEffect(() => {
    if (!userId) return;
    const key = `${userId}:${language}`;
    if (synced.current === key) return;
    synced.current = key;
    userService.setLanguage(language).catch((err: unknown) => {
      synced.current = null;
    });
  }, [userId, language]);
}
