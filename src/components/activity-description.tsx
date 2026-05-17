import { useMemo, useState } from 'react';
import { View, Text, Pressable, StyleSheet, LayoutChangeEvent } from 'react-native';
import { useTranslation } from 'react-i18next';
import { fontSizes, spacing } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';

interface Props {
  description: string | null | undefined;
}

const COLLAPSED_LINES = 4;

export function ActivityDescription({ description }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const [expanded, setExpanded] = useState(false);
  const [overflowing, setOverflowing] = useState(false);

  // Render once with no clamp to measure, then clamp on subsequent
  // renders. Only show the Voir-plus toggle if content actually
  // exceeds the collapsed line count.
  const onTextLayout = (e: LayoutChangeEvent & { nativeEvent: { lines: { length: number }[] } }) => {
    const lineCount = (e.nativeEvent.lines as unknown as unknown[]).length;
    if (lineCount > COLLAPSED_LINES && !overflowing) setOverflowing(true);
  };

  if (!description) return null;

  return (
    <View style={styles.container}>
      <Text style={styles.title}>{t('activity.description')}</Text>
      <Text
        style={styles.body}
        numberOfLines={expanded ? undefined : COLLAPSED_LINES}
        onTextLayout={onTextLayout as never}
      >
        {description}
      </Text>
      {overflowing && (
        <Pressable onPress={() => setExpanded((v) => !v)} hitSlop={6}>
          <Text style={styles.toggle}>
            {expanded ? t('activity.descSeeLess', { defaultValue: 'Voir moins' }) : t('activity.descSeeMore', { defaultValue: 'Voir plus' })}
          </Text>
        </Pressable>
      )}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: {
    // Flat — parent (Where card in the info tab) provides the outline.
    marginTop: spacing.md,
  },
  title: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '700',
    letterSpacing: 1,
    textTransform: 'uppercase',
    marginBottom: spacing.xs,
  },
  body: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    lineHeight: 22,
  },
  toggle: {
    color: colors.cta,
    fontSize: fontSizes.sm,
    fontWeight: '700',
    marginTop: spacing.xs,
  },
});
