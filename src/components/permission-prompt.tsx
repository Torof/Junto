import { useMemo } from 'react';
import { Modal, Pressable, StyleSheet, View } from 'react-native';
import { useTranslation } from 'react-i18next';
import { Bell, Camera, MapPin } from 'lucide-react-native';
import { AppText } from '@/components/app-text';
import { PressableScale } from '@/components/pressable-scale';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { usePermissionPromptStore } from '@/store/permission-prompt-store';

// The card shown before any OS permission dialog (lib/permissions.ts): what
// the permission is for, right now, in one sentence — then « Autoriser » opens
// the OS dialog, « Plus tard » does nothing. When the OS will no longer ask,
// the card points to the settings instead. Mounted once, at the root.
export function PermissionPrompt() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const card = usePermissionPromptStore((s) => s.card);
  const answer = usePermissionPromptStore((s) => s.answer);

  const Icon = card?.kind === 'notifications' ? Bell : card?.kind === 'camera' ? Camera : MapPin;

  return (
    <Modal visible={card !== null} transparent animationType="fade" onRequestClose={() => answer(false)} statusBarTranslucent>
      <Pressable style={styles.backdrop} onPress={() => answer(false)}>
        <Pressable style={styles.card} onPress={(e) => e.stopPropagation()}>
          {card && (
            <>
              <View style={styles.iconWrap}>
                <Icon size={26} color={colors.cta} strokeWidth={2.3} />
              </View>
              <AppText style={styles.title}>{t(`permAsk.${card.kind}.title`)}</AppText>
              <AppText style={styles.body}>{t(`permAsk.${card.kind}.${card.reason}`)}</AppText>
              {card.blocked && <AppText style={styles.blocked}>{t('permAsk.blocked')}</AppText>}
              <PressableScale style={styles.primary} onPress={() => answer(true)}>
                <AppText style={styles.primaryText}>{t(card.blocked ? 'permAsk.openSettings' : 'permAsk.allow')}</AppText>
              </PressableScale>
              <PressableScale style={styles.secondary} onPress={() => answer(false)} hitSlop={6}>
                <AppText style={styles.secondaryText}>{t('permAsk.later')}</AppText>
              </PressableScale>
            </>
          )}
        </Pressable>
      </Pressable>
    </Modal>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  backdrop: {
    flex: 1,
    backgroundColor: colors.overlay,
    justifyContent: 'flex-end',
    padding: spacing.md,
    paddingBottom: spacing.xl,
  },
  card: {
    backgroundColor: colors.surface,
    borderRadius: radius.xl,
    padding: spacing.lg,
    alignItems: 'center',
    gap: spacing.sm,
    ...shadows.raised,
  },
  iconWrap: {
    width: 56,
    height: 56,
    borderRadius: 28,
    backgroundColor: colors.cta + '1A',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: spacing.xs,
  },
  title: {
    color: colors.textPrimary,
    fontSize: fontSizes.lg + 2,
    fontWeight: '800',
    textAlign: 'center',
  },
  body: {
    color: colors.textSecondary,
    fontSize: fontSizes.md - 1,
    lineHeight: 22,
    textAlign: 'center',
  },
  blocked: {
    color: colors.textMuted,
    fontSize: fontSizes.sm - 1,
    lineHeight: 19,
    textAlign: 'center',
  },
  primary: {
    alignSelf: 'stretch',
    marginTop: spacing.sm,
    backgroundColor: colors.cta,
    borderRadius: radius.full,
    paddingVertical: 14,
    alignItems: 'center',
  },
  primaryText: { color: colors.onCta, fontSize: fontSizes.md, fontWeight: '700' },
  secondary: { paddingVertical: spacing.sm, paddingHorizontal: spacing.lg },
  secondaryText: { color: colors.textSecondary, fontSize: fontSizes.md - 1, fontWeight: '600' },
});
