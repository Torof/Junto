import { useMemo, useState } from 'react';
import { View, Pressable, StyleSheet, Modal } from 'react-native';
import { AppText } from '@/components/app-text';
import { useTranslation } from 'react-i18next';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import * as Burnt from 'burnt';
import dayjs from 'dayjs';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { discoveryService, type DiscoveryCard } from '@/services/discovery-service';
import { conversationService } from '@/services/conversation-service';
import { LogoSpinner } from '@/components/logo-spinner';
import { SportIcon } from '@/components/sport-icon';
import { getFriendlyError } from '@/utils/friendly-error';

// Contact / invite a Découverte match — shared by the lists and the full card.
// The ['discovery-cards'] cache is the source of truth: on success it is
// patched (contact_state 'pending') so the state survives any screen (audit
// H2); `sendingTo` locks against a double tap (M2). Returns the invite picker
// as an element to render once in the screen.
export function useDiscoveryActions() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const [sendingTo, setSendingTo] = useState<string | null>(null);
  const [inviteTargetId, setInviteTargetId] = useState<string | null>(null);

  const { data: invitable, isLoading: invitableLoading } = useQuery({
    queryKey: ['invitable-activities', inviteTargetId],
    queryFn: () => discoveryService.getInvitableActivities(inviteTargetId as string),
    enabled: !!inviteTargetId,
  });

  const markPending = (userId: string) => {
    queryClient.setQueryData<DiscoveryCard[] | undefined>(['discovery-cards'], (old) =>
      old?.map((c) => (c.user_id === userId ? { ...c, contact_state: 'pending' as const } : c)),
    );
  };

  const contact = async (userId: string) => {
    if (sendingTo) return;
    setSendingTo(userId);
    try {
      await conversationService.sendContactRequest(userId, t('discovery.contactMessage', { defaultValue: 'Salut ! On matche sur Découverte — ça te dit une sortie ?' }), 'discovery');
      markPending(userId);
      Burnt.toast({ title: t('discovery.contactSent', { defaultValue: 'Demande envoyée' }), preset: 'done' });
    } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
    finally { setSendingTo(null); }
  };

  const invite = async (activityId: string) => {
    const target = inviteTargetId;
    if (!target || sendingTo) return;
    setSendingTo(target);
    try {
      await discoveryService.sendDiscoveryInvite(target, activityId);
      markPending(target);
      setInviteTargetId(null);
      Burnt.toast({ title: t('discovery.inviteSent', { defaultValue: 'Invitation envoyée' }), preset: 'done' });
    } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
    finally { setSendingTo(null); }
  };

  // Invite picker — one of my activities that matches their dispo. The request
  // stays a contact request until they accept (gate intact).
  const inviteSheet = (
    <Modal visible={!!inviteTargetId} transparent animationType="slide" onRequestClose={() => setInviteTargetId(null)}>
      <Pressable style={styles.backdrop} onPress={() => setInviteTargetId(null)}>
        <Pressable style={styles.sheet} onPress={(e) => e.stopPropagation()}>
          <AppText style={styles.title}>{t('discovery.inviteTitle', { defaultValue: 'Inviter à une sortie' })}</AppText>
          {invitableLoading ? (
            <View style={styles.center}><LogoSpinner size={32} /></View>
          ) : (invitable ?? []).length === 0 ? (
            <AppText style={styles.empty}>
              {t('discovery.inviteEmpty', { defaultValue: 'Aucune de tes sorties ne correspond à sa dispo. Crée une sortie qui matche son sport et ses dates.' })}
            </AppText>
          ) : (
            (invitable ?? []).map((a) => (
              <Pressable key={a.id} style={[styles.row, sendingTo ? styles.faded : null]} onPress={() => invite(a.id)} disabled={!!sendingTo} accessibilityRole="button">
                <SportIcon sportKey={a.sport_key} size={20} />
                <View style={{ flex: 1, minWidth: 0 }}>
                  <AppText style={styles.rowTitle} numberOfLines={1}>{a.title}</AppText>
                  <AppText style={styles.rowMeta}>{dayjs(a.starts_at).format('ddd D MMM · H[h]mm')}</AppText>
                </View>
              </Pressable>
            ))
          )}
          <Pressable style={styles.cancel} onPress={() => setInviteTargetId(null)}>
            <AppText style={styles.cancelText}>{t('common.cancel', { defaultValue: 'Annuler' })}</AppText>
          </Pressable>
        </Pressable>
      </Pressable>
    </Modal>
  );

  return { sendingTo, contact, openInvite: setInviteTargetId, inviteSheet };
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: colors.overlay, justifyContent: 'flex-end' },
  sheet: {
    backgroundColor: colors.background,
    borderTopLeftRadius: radius.xl,
    borderTopRightRadius: radius.xl,
    padding: spacing.lg,
    gap: spacing.sm,
    paddingBottom: spacing.xl,
  },
  center: { alignItems: 'center', justifyContent: 'center', paddingVertical: spacing.xl },
  title: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800', marginBottom: spacing.xs },
  empty: { color: colors.textSecondary, fontSize: fontSizes.md, lineHeight: 22, paddingVertical: spacing.md },
  row: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.md,
    paddingVertical: spacing.sm + 2, borderBottomWidth: 1, borderBottomColor: colors.line,
  },
  rowTitle: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  rowMeta: { color: colors.textSecondary, fontSize: fontSizes.sm, marginTop: 2, textTransform: 'capitalize' },
  faded: { opacity: 0.5 },
  cancel: { alignItems: 'center', paddingVertical: spacing.md, marginTop: spacing.xs },
  cancelText: { color: colors.textSecondary, fontSize: fontSizes.md, fontWeight: '700' },
});
