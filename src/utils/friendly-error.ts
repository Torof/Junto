import i18n from '@/i18n';

type ErrorAction =
  | 'createActivity'
  | 'updateActivity'
  | 'joinActivity'
  | 'leaveActivity'
  | 'cancelActivity'
  | 'sendMessage'
  | 'sendWallMessage'
  | 'createAlert'
  | 'deleteAlert'
  | 'rateParticipants'
  | 'uploadAvatar'
  | 'sendReport'
  | 'generic';

export function getFriendlyError(err: unknown, action: ErrorAction = 'generic'): string {
  const raw = err instanceof Error ? err.message.toLowerCase() : '';
  const t = i18n.t.bind(i18n);

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
