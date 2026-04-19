export const darkColors = {
  background: '#0D1B2A',
  surface: '#1B3A5C',
  cta: '#F4642A',

  textPrimary: '#F5F5F0',
  textSecondary: '#8A9BB0',

  success: '#2ECC71',
  error: '#E74C3C',
  warning: '#F39C12',

  pinStart: '#22c55e',
  pinMeeting: '#3b82f6',
  pinEnd: '#ef4444',
  pinObjective: '#F5A623',

  pinBackground: '#F5F5F0',
  border: 'transparent',
  overlay: 'rgba(0,0,0,0.5)',
};

export const lightColors = {
  background: '#F5F5F0',
  surface: '#E0DDD8',
  cta: '#F4642A',

  textPrimary: '#1A1A1A',
  textSecondary: '#6B7280',

  success: '#2ECC71',
  error: '#E74C3C',
  warning: '#F39C12',

  pinStart: '#22c55e',
  pinMeeting: '#3b82f6',
  pinEnd: '#ef4444',
  pinObjective: '#F5A623',

  pinBackground: '#E8E4DF',
  border: '#C8C4BF',
  overlay: 'rgba(0,0,0,0.3)',
};

export type AppColors = typeof darkColors;

// Static fallback for files not yet migrated to useColors()
export const colors = darkColors;
