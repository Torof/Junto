import { useState, useMemo } from 'react';
import { View, Text, Modal, Pressable, TextInput, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';

interface Props {
  visible: boolean;
  isSubmitting: boolean;
  onCancel: () => void;
  onConfirm: (reason: string) => void;
}

const CATEGORIES: Array<{ key: string; icon: string }> = [
  { key: 'weather', icon: '🌧️' },
  { key: 'personal', icon: '🤒' },
  { key: 'lowSignups', icon: '👥' },
  { key: 'conditions', icon: '📍' },
];

export function CancelActivityModal({ visible, isSubmitting, onCancel, onConfirm }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const [category, setCategory] = useState<string | null>(null);
  const [details, setDetails] = useState('');

  const trimmedDetails = details.trim();
  const finalReason = (() => {
    const catLabel = category ? t(`cancel.cat.${category}`) : null;
    if (catLabel && trimmedDetails) return `${catLabel} — ${trimmedDetails}`;
    if (catLabel) return catLabel;
    if (trimmedDetails) return trimmedDetails;
    return '';
  })();
  const canSubmit = finalReason.length >= 3 && !isSubmitting;

  return (
    <Modal visible={visible} animationType="fade" transparent onRequestClose={onCancel}>
      <View style={styles.backdrop}>
        <View style={styles.sheet}>
          <Text style={styles.title}>{t('cancel.cancelTitle')}</Text>
          <Text style={styles.body}>{t('cancel.cancelSubtitle')}</Text>

          <View style={styles.categoryRow}>
            {CATEGORIES.map((c) => (
              <Pressable
                key={c.key}
                style={[styles.categoryPill, category === c.key && styles.categoryPillActive]}
                onPress={() => setCategory(category === c.key ? null : c.key)}
              >
                <Text style={styles.categoryIcon}>{c.icon}</Text>
                <Text style={[styles.categoryLabel, category === c.key && styles.categoryLabelActive]}>
                  {t(`cancel.cat.${c.key}`)}
                </Text>
              </Pressable>
            ))}
          </View>

          <TextInput
            style={styles.input}
            value={details}
            onChangeText={setDetails}
            placeholder={t('cancel.reasonPlaceholderCancel')}
            placeholderTextColor={colors.textSecondary}
            multiline
            maxLength={200}
          />

          <View style={styles.actions}>
            <Pressable style={styles.secondaryButton} onPress={onCancel}>
              <Text style={styles.secondaryText}>{t('cancel.keep')}</Text>
            </Pressable>
            <Pressable
              style={[styles.primaryButton, !canSubmit && styles.disabled]}
              onPress={() => canSubmit && onConfirm(finalReason)}
              disabled={!canSubmit}
            >
              <Text style={styles.primaryText}>{isSubmitting ? '...' : t('cancel.cancelConfirm')}</Text>
            </Pressable>
          </View>
        </View>
      </View>
    </Modal>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: colors.overlay, alignItems: 'center', justifyContent: 'center', padding: spacing.lg },
  sheet: {
    width: '100%', maxWidth: 360, backgroundColor: colors.surface,
    borderRadius: radius.lg, padding: spacing.lg, gap: spacing.md,
  },
  title: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold' },
  body: { color: colors.textSecondary, fontSize: fontSizes.sm, lineHeight: 20 },
  categoryRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs },
  categoryPill: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.xs,
    backgroundColor: colors.background, borderRadius: radius.full,
    paddingHorizontal: spacing.sm, paddingVertical: spacing.xs,
    borderWidth: 1, borderColor: 'transparent',
  },
  categoryPillActive: { borderColor: colors.cta, backgroundColor: colors.cta + '20' },
  categoryIcon: { fontSize: 14 },
  categoryLabel: { color: colors.textSecondary, fontSize: fontSizes.xs },
  categoryLabelActive: { color: colors.cta, fontWeight: 'bold' },
  input: {
    backgroundColor: colors.background, color: colors.textPrimary,
    borderRadius: radius.md, padding: spacing.md, fontSize: fontSizes.sm,
    minHeight: 70, textAlignVertical: 'top',
  },
  actions: { flexDirection: 'row', gap: spacing.sm, marginTop: spacing.xs },
  secondaryButton: {
    flex: 1, paddingVertical: spacing.sm, borderRadius: radius.full,
    alignItems: 'center', borderWidth: 1, borderColor: colors.textSecondary,
  },
  secondaryText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: 'bold' },
  primaryButton: {
    flex: 1, paddingVertical: spacing.sm, borderRadius: radius.full,
    alignItems: 'center', backgroundColor: colors.error,
  },
  primaryText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: 'bold' },
  disabled: { opacity: 0.5 },
});
