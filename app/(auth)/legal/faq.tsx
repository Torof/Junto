import { useMemo, useState } from 'react';
import { ScrollView, View, Pressable, StyleSheet } from 'react-native';
import { AppText } from '@/components/app-text';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';

const FAQ_KEYS = [
  'create',
  'join',
  'leave',
  'transport',
  'gear',
  'messaging',
  'alerts',
  'reliability',
  'levels',
  'badges',
  'presence',
  'block',
  'report',
  'pro',
  'delete',
] as const;

export default function FaqScreen() {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const insets = useSafeAreaInsets();
  const [expanded, setExpanded] = useState<string | null>(null);

  return (
    <ScrollView style={styles.container} contentContainerStyle={[styles.content, { paddingBottom: insets.bottom + spacing.xl }]}>
      <AppText style={styles.title}>{t('faq.title')}</AppText>
      <AppText style={styles.intro}>{t('faq.intro')}</AppText>

      {FAQ_KEYS.map((key) => {
        const isOpen = expanded === key;
        return (
          <Pressable
            key={key}
            style={styles.item}
            onPress={() => setExpanded(isOpen ? null : key)}
          >
            <View style={styles.questionRow}>
              <AppText style={styles.question}>{t(`faq.${key}.q`)}</AppText>
              <AppText style={styles.arrow}>{isOpen ? '−' : '+'}</AppText>
            </View>
            {isOpen && (
              <AppText style={styles.answer}>{t(`faq.${key}.a`)}</AppText>
            )}
          </Pressable>
        );
      })}
    </ScrollView>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.lg },
  title: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold', marginBottom: spacing.sm },
  intro: { color: colors.textSecondary, fontSize: fontSizes.sm, lineHeight: 20, marginBottom: spacing.xl },
  item: { borderWidth: 1, borderColor: colors.lineStrong,
    backgroundColor: colors.surfaceAlt,
    borderRadius: radius.md,
    padding: spacing.md,
    marginBottom: spacing.sm,
  },
  questionRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  question: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600', flex: 1 },
  arrow: { color: colors.textSecondary, fontSize: fontSizes.lg, fontWeight: 'bold', width: 20, textAlign: 'center' },
  answer: { color: colors.textSecondary, fontSize: fontSizes.sm, lineHeight: 20, marginTop: spacing.sm },
});
