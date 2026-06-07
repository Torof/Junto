import { useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { fontSizes, spacing } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';

export type PageType = 'pro' | 'offering' | 'activity';

interface Props {
  type: PageType;
  // Entity name appended after the type label, e.g.
  //   sphere + "Page pro · Pierre Dupont"
  //   sphere + "Activité récurrente · Mont Aiguille"
  // Optional so the component is still usable as a bare type marker.
  name?: string;
}

// Small colored sphere + natural-language label rendered into the
// navbar of the pro / offering / activity detail screens. The sphere
// is the silent at-a-glance type cue (orange = pro storefront, blue =
// catalog offering, green = scheduled activity); the prefix carries
// the rest of the meaning. Pin silhouettes in this slot were too
// busy for navbar use — a colored dot is enough at this scale.

const TYPE_COLORS: Record<PageType, string> = {
  pro: '#F4642A',
  offering: '#3B82F6',
  activity: '#2ECC71',
};

const TYPE_PREFIXES: Record<PageType, string> = {
  pro: 'Page pro',
  offering: 'Activité récurrente',
  activity: 'Sortie',
};

const SPHERE_SIZE = 10;

export function PageTypeBadge({ type, name }: Props) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const sphereColor = TYPE_COLORS[type];
  const text = name ? `${TYPE_PREFIXES[type]} · ${name}` : TYPE_PREFIXES[type];

  return (
    <View style={styles.wrap}>
      <View style={[styles.sphere, { backgroundColor: sphereColor }]} />
      <Text style={styles.label} numberOfLines={1}>{text}</Text>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  wrap: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    maxWidth: 260,
  },
  sphere: {
    width: SPHERE_SIZE,
    height: SPHERE_SIZE,
    borderRadius: SPHERE_SIZE / 2,
  },
  label: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '600',
    flexShrink: 1,
  },
});
