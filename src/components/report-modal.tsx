import { useState } from 'react';
import { View, Text, TextInput, Pressable, Modal, StyleSheet, Alert } from 'react-native';
import { useTranslation } from 'react-i18next';
import * as Burnt from 'burnt';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { reportService } from '@/services/report-service';

interface ReportModalProps {
  visible: boolean;
  targetType: 'user' | 'activity' | 'wall_message' | 'private_message';
  targetId: string;
  onClose: () => void;
}

export function ReportModal({ visible, targetType, targetId, onClose }: ReportModalProps) {
  const { t } = useTranslation();
  const [reason, setReason] = useState('');
  const [isSending, setIsSending] = useState(false);

  const handleSubmit = async () => {
    if (reason.trim().length < 10) {
      Alert.alert(t('auth.error'), t('report.tooShort'));
      return;
    }
    setIsSending(true);
    try {
      await reportService.create(targetType, targetId, reason.trim());
      Burnt.toast({ title: t('report.submitted'), preset: 'done' });
      setReason('');
      onClose();
    } catch {
      Alert.alert(t('auth.error'), t('auth.unknownError'));
    } finally {
      setIsSending(false);
    }
  };

  return (
    <Modal visible={visible} animationType="slide" transparent>
      <Pressable style={styles.backdrop} onPress={onClose}>
        <Pressable style={styles.sheet} onPress={() => {}}>
          <View style={styles.handle} />
          <Text style={styles.title}>{t('report.title')}</Text>
          <Text style={styles.subtitle}>{t('report.subtitle')}</Text>

          <TextInput
            style={styles.input}
            value={reason}
            onChangeText={setReason}
            placeholder={t('report.placeholder')}
            placeholderTextColor={colors.textSecondary}
            multiline
            maxLength={1000}
          />

          <Text style={styles.charCount}>{reason.length}/1000</Text>

          <Pressable
            style={[styles.submitButton, (reason.trim().length < 10 || isSending) && styles.disabled]}
            onPress={handleSubmit}
            disabled={reason.trim().length < 10 || isSending}
          >
            <Text style={styles.submitText}>{isSending ? '...' : t('report.submit')}</Text>
          </Pressable>
        </Pressable>
      </Pressable>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.5)', justifyContent: 'flex-end' },
  sheet: { backgroundColor: colors.background, borderTopLeftRadius: radius.lg, borderTopRightRadius: radius.lg, padding: spacing.lg, paddingBottom: spacing.xl + 16 },
  handle: { width: 40, height: 4, borderRadius: 2, backgroundColor: colors.textSecondary, alignSelf: 'center', marginBottom: spacing.lg, opacity: 0.4 },
  title: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold', marginBottom: spacing.xs },
  subtitle: { color: colors.textSecondary, fontSize: fontSizes.sm, marginBottom: spacing.lg },
  input: {
    backgroundColor: colors.surface, color: colors.textPrimary, borderRadius: radius.md,
    paddingHorizontal: spacing.md, paddingVertical: spacing.md, fontSize: fontSizes.sm,
    minHeight: 100, textAlignVertical: 'top',
  },
  charCount: { color: colors.textSecondary, fontSize: fontSizes.xs, alignSelf: 'flex-end', marginTop: spacing.xs },
  submitButton: { backgroundColor: colors.error, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.md },
  disabled: { opacity: 0.4 },
  submitText: { color: '#fff', fontSize: fontSizes.md, fontWeight: 'bold' },
});
