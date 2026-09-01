import i18n from '@/i18n';

type ErrorAction =
  | 'createActivity'
  | 'updateActivity'
  | 'joinActivity'
  | 'leaveActivity'
  | 'cancelActivity'
  | 'sendMessage'
  | 'sendWallMessage'
  | 'editWallMessage'
  | 'deleteWallMessage'
  | 'createAlert'
  | 'deleteAlert'
  | 'confirmPresence'
  | 'uploadAvatar'
  | 'sendReport'
  | 'generic';

export function getFriendlyError(err: unknown, action: ErrorAction = 'generic'): string {
  // Supabase/PostgREST errors are plain objects ({ message, code, details }),
  // NOT Error instances — read the message from either shape so coded
  // `junto.*` failures surface their specific friendly message.
  const rawMsg =
    err instanceof Error
      ? err.message
      : typeof err === 'object' && err !== null && typeof (err as { message?: unknown }).message === 'string'
        ? (err as { message: string }).message
        : '';
  const raw = rawMsg.toLowerCase();
  const t = i18n.t.bind(i18n);

  // Coded, non-sensitive server errors: a SECURITY DEFINER function raised
  // `junto.<code>` for a user-actionable failure (rate limit, validation,
  // capacity, premium gate) — safe to surface specifically. Sensitive
  // failures (auth, ownership, suspension, access) still raise the generic
  // "Operation not permitted" and fall through to the action message below.
  const coded = rawMsg.match(/junto\.([a-z_]+)/);
  if (coded) {
    const msg = t(`errors.code.${coded[1]}`, { defaultValue: '' });
    if (msg) return msg;
  }

  // Specific errors we can detect regardless of action
  if (raw.includes('network') || raw.includes('failed to fetch') || raw.includes('timeout')) {
    return t('errors.network');
  }
  if (raw.includes('rate limit') || raw.includes('too many')) {
    return t('errors.rateLimit');
  }
  if (raw.includes('jwt') || raw.includes('session expired') || raw.includes('auth')) {
    return t('errors.sessionExpired');
  }

  // Operation-specific fallbacks (DB returns generic "Operation not permitted")
  return t(`errors.${action}`);
}
