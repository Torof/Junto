import { useState, useMemo } from 'react';
import { View, Text, Modal, Pressable, TextInput, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';

interface Props {
  visible: boolean;
  isLate: boolean;
  isSubmitting: boolean;
  onCancel: () => void;
  onConfirm: (reason?: string) => void;
}

export function LeaveActivityModal({ visible, isLate, isSubmitting, onCancel, onConfirm }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const [reason, setReason] = useState('');
  const styles = useMemo(() => createStyles(colors), [colors]);

  return (
    <Modal visible={visible} animationType="fade" transparent onRequestClose={onCancel}>
      <View style={styles.backdrop}>
        <View style={styles.sheet}>
          <Text style={styles.title}>{t('cancel.leaveTitle')}</Text>
          <Text style={[styles.body, isLate && styles.bodyWarning]}>
            {isLate ? `⚠️ ${t('cancel.leaveLateWarning')}` : t('cancel.leaveSafe')}
          </Text>

          <TextInput
            style={styles.input}
            value={reason}
            onChangeText={setReason}
            placeholder={t('cancel.reasonPlaceholderLeave')}
            placeholderTextColor={colors.textSecondary}
            multiline
            maxLength={200}
          />

          <View style={styles.actions}>
            <Pressable style={styles.secondaryButton} onPress={onCancel}>
              <Text style={styles.secondaryText}>{t('cancel.keep')}</Text>
            </Pressable>
            <Pressable
              style={[styles.primaryButton, isSubmitting && styles.disabled]}
              onPress={() => onConfirm(reason.trim() || undefined)}
              disabled={isSubmitting}
            >
              <Text style={styles.primaryText}>{isSubmitting ? '...' : t('cancel.leaveConfirm')}</Text>
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
  body: { color: colors.textPrimary, fontSize: fontSizes.sm, lineHeight: 20 },
  bodyWarning: { color: colors.warning, fontWeight: 'bold' },
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
