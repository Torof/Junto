import { type ReactNode } from 'react';
import { Text, StyleSheet, View } from 'react-native';
import { fontSizes, radius, spacing, glow } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import { PressableScale } from '@/components/pressable-scale';

// Canon 2026-09 — the THREE button shapes (replaces 153 ad-hoc styles):
//   primary → solid cta pill, onCta 700 text, optional glorified glow
//   link    → icon + quiet 600 textSecondary text, no box
//   icon    → round 40, surface background
interface AppButtonProps {
  variant?: 'primary' | 'link' | 'icon';
  label?: string;
  icon?: ReactNode;
  onPress?: () => void;
  disabled?: boolean;
  glorified?: boolean;   // primary only: colored glow for THE one CTA of a screen
  fullWidth?: boolean;   // primary only: opt-in (canon: content-width default)
  destructive?: boolean; // link only: error color
}

export function AppButton({
  variant = 'primary', label, icon, onPress, disabled = false,
  glorified = false, fullWidth = false, destructive = false,
}: AppButtonProps) {
  const colors = useColors();

  if (variant === 'icon') {
    return (
      <PressableScale
        onPress={onPress}
        disabled={disabled}
        hitSlop={6}
        style={[styles.iconBtn, { backgroundColor: colors.surface }, disabled && styles.disabled]}
      >
        {icon}
      </PressableScale>
    );
  }

  if (variant === 'link') {
    const c = destructive ? colors.error : colors.textSecondary;
    return (
      <PressableScale onPress={onPress} disabled={disabled} hitSlop={6} style={[styles.link, disabled && styles.disabled]}>
        {icon}
        {label ? <Text style={[styles.linkText, { color: c }]}>{label}</Text> : null}
      </PressableScale>
    );
  }

  return (
    <PressableScale
      onPress={onPress}
      disabled={disabled}
      style={[
        styles.primary,
        { backgroundColor: colors.cta },
        glorified && glow(colors.cta),
        fullWidth && styles.fullWidth,
        disabled && styles.disabled,
      ]}
    >
      {icon}
      {label ? <Text style={[styles.primaryText, { color: colors.onCta }]}>{label}</Text> : null}
    </PressableScale>
  );
}

const styles = StyleSheet.create({
  primary: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6,
    borderRadius: radius.full,
    paddingVertical: spacing.sm + 4, paddingHorizontal: spacing.lg,
    alignSelf: 'flex-start',
  },
  fullWidth: { alignSelf: 'stretch' },
  primaryText: { fontSize: fontSizes.sm + 1, fontWeight: '700' },
  link: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  linkText: { fontSize: fontSizes.sm, fontWeight: '600' },
  iconBtn: { width: 40, height: 40, borderRadius: radius.full, alignItems: 'center', justifyContent: 'center' },
  disabled: { opacity: 0.45 },
});
