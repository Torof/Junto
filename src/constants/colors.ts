export const darkColors = {
  background: '#0D1B2A',
  surface: '#1B3A5C',
  surfaceAlt: '#142D48',
  cta: '#F4642A',

  textPrimary: '#F5F5F0',
  textSecondary: '#8A9BB0',
  textMuted: '#5B6B85',

  success: '#2ECC71',
  error: '#E74C3C',
  warning: '#F39C12',

  pinStart: '#22c55e',
  pinMeeting: '#3b82f6',
  pinEnd: '#ef4444',
  pinObjective: '#F5A623',

  pinBackground: '#F5F5F0',
  pinBorder: '#0D1B2A',
  border: 'transparent',
  line: 'rgba(255,255,255,0.08)',
  overlay: 'rgba(0,0,0,0.5)',
};

export const lightColors = {
  background: '#F5F5F0',
  surface: '#E0DDD8',
  surfaceAlt: '#D4D0CB',
  cta: '#F4642A',

  textPrimary: '#1A1A1A',
  textSecondary: '#6B7280',
  textMuted: '#9CA3AF',

  success: '#2ECC71',
  error: '#E74C3C',
  warning: '#F39C12',

  pinStart: '#22c55e',
  pinMeeting: '#3b82f6',
  pinEnd: '#ef4444',
  pinObjective: '#F5A623',

  pinBackground: '#FFFFFF',
  pinBorder: '#1A1A1A',
  border: '#9E9A95',
  line: 'rgba(0,0,0,0.08)',
  overlay: 'rgba(0,0,0,0.3)',
};

export type AppColors = typeof darkColors;

// Static fallback for files not yet migrated to useColors()
export const colors = darkColors;
