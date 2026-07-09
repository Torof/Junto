import { useMemo, useState } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { fontSizes, spacing } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';

interface Props {
  description: string | null | undefined;
}

const COLLAPSED_LINES = 4;
// Heuristic — line breaks plus a ~50-char-per-line average over the
// visible width. Avoids the onTextLayout measure dance which behaves
// inconsistently across RN versions when numberOfLines is set.
const OVERFLOW_CHAR_THRESHOLD = 200;

export function ActivityDescription({ description }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const [expanded, setExpanded] = useState(false);

  if (!description) return null;

  const overflowing =
    description.length > OVERFLOW_CHAR_THRESHOLD || description.split('\n').length > COLLAPSED_LINES;

  return (
    <View style={styles.container}>
      <Text
        style={styles.body}
        numberOfLines={expanded ? undefined : COLLAPSED_LINES}
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
  // Flat — the parent section provides the styled label + spacing.
  container: {},
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
