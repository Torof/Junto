import { useMemo, useState } from 'react';
import { View, Text, Modal, Pressable, FlatList, StyleSheet } from 'react-native';
import { Share2, UserPlus } from 'lucide-react-native';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import * as Burnt from 'burnt';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { conversationService } from '@/services/conversation-service';
import { messageService } from '@/services/message-service';
import { UserAvatar } from './user-avatar';
import { LogoSpinner } from './logo-spinner';
import { InvitePartnersSheet } from './invite-partners-sheet';

interface Props {
  visible: boolean;
  activityId: string;
  onClose: () => void;
  onExternalShare?: () => void;
}

export function ShareActivitySheet({ visible, activityId, onClose, onExternalShare }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const [sendingTo, setSendingTo] = useState<string | null>(null);
  const [inviteOpen, setInviteOpen] = useState(false);

  const { data: conversations, isLoading } = useQuery({
    queryKey: ['conversations'],
    queryFn: () => conversationService.getAll(),
    enabled: visible,
  });
  // Share into a direct conversation. The hub RPC now returns all 3 types
  // (00368) under this shared cache key — filter to DM at render (never in the
  // queryFn: it would poison the hub's ['conversations'] cache).
  const dmConversations = (conversations ?? []).filter((c) => c.type === 'dm');

  const handleShare = async (conversationId: string) => {
    setSendingTo(conversationId);
    try {
      await messageService.shareActivity(conversationId, activityId);
      Burnt.toast({ title: t('activity.shared'), preset: 'done' });
      onClose();
    } catch {
      Burnt.toast({ title: t('auth.unknownError') });
    } finally {
      setSendingTo(null);
    }
  };

  return (
    <>
    <Modal visible={visible} animationType="slide" transparent onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose}>
        <Pressable style={styles.sheet} onPress={() => {}}>
          <View style={styles.handle} />
          <Text style={styles.title}>{t('activity.shareTitle')}</Text>

          <Pressable style={styles.inviteRow} onPress={() => setInviteOpen(true)}>
            <View style={styles.inviteIconWrap}>
              <UserPlus size={18} color="#FFFFFF" strokeWidth={2.4} />
            </View>
            <View style={{ flex: 1, minWidth: 0 }}>
              <Text style={styles.inviteLabel}>{t('contacts.inviteTitle', { defaultValue: 'Inviter des partenaires' })}</Text>
              <Text style={styles.inviteSub} numberOfLines={1}>{t('contacts.inviteSub', { defaultValue: 'Tes contacts + partenaires récents' })}</Text>
            </View>
          </Pressable>

          <Text style={styles.orLabel}>{t('activity.shareToConversation', { defaultValue: 'Ou partager dans une conversation' })}</Text>

          {isLoading ? (
            <View style={styles.center}><LogoSpinner /></View>
          ) : dmConversations.length === 0 ? (
            <Text style={styles.empty}>{t('activity.shareNoConversations')}</Text>
          ) : (
            <FlatList
              data={dmConversations}
              keyExtractor={(item) => item.id}
              renderItem={({ item }) => (
                <Pressable
                  style={[styles.row, sendingTo === item.id && styles.rowDisabled]}
                  onPress={() => handleShare(item.id)}
                  disabled={sendingTo !== null}
                >
                  <UserAvatar name={item.other_user_name ?? '?'} avatarUrl={item.other_user_avatar} size={40} />
                  <Text style={styles.name} numberOfLines={1}>{item.other_user_name ?? '?'}</Text>
                </Pressable>
              )}
            />
          )}

          {onExternalShare && (
            <Pressable
              style={styles.externalRow}
              onPress={() => { onClose(); onExternalShare(); }}
            >
              <View style={styles.externalIconWrap}>
                <Share2 size={18} color={colors.textPrimary} strokeWidth={2.2} />
              </View>
              <Text style={styles.externalLabel}>{t('activity.shareExternal')}</Text>
            </Pressable>
          )}
        </Pressable>
      </Pressable>
    </Modal>
    <InvitePartnersSheet visible={inviteOpen} activityId={activityId} onClose={() => setInviteOpen(false)} />
    </>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: colors.overlay, justifyContent: 'flex-end' },
  sheet: {
    backgroundColor: colors.background,
    borderTopLeftRadius: radius.lg,
    borderTopRightRadius: radius.lg,
    padding: spacing.lg,
    paddingBottom: spacing.xl + 16,
    maxHeight: '70%',
  },
  handle: { width: 40, height: 4, borderRadius: 2, backgroundColor: colors.textSecondary, alignSelf: 'center', marginBottom: spacing.lg, opacity: 0.4 },
  title: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold', marginBottom: spacing.md },
  inviteRow: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.md,
    paddingVertical: spacing.sm + 2, paddingHorizontal: spacing.sm,
    borderRadius: radius.md, borderWidth: 1.5, borderColor: colors.cta,
    backgroundColor: colors.cta + '12',
  },
  inviteIconWrap: {
    width: 40, height: 40, borderRadius: 20, backgroundColor: colors.cta,
    alignItems: 'center', justifyContent: 'center',
  },
  inviteLabel: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '800' },
  inviteSub: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: 1 },
  orLabel: {
    color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '700',
    textTransform: 'uppercase', letterSpacing: 0.6,
    marginTop: spacing.lg, marginBottom: spacing.xs,
  },
  empty: { color: colors.textSecondary, fontSize: fontSizes.md, textAlign: 'center', paddingVertical: spacing.xl },
  center: { paddingVertical: spacing.xl, alignItems: 'center' },
  row: { flexDirection: 'row', alignItems: 'center', gap: spacing.md, paddingVertical: spacing.sm },
  rowDisabled: { opacity: 0.4 },
  name: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '600' },
  externalRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    paddingVertical: spacing.md,
    marginTop: spacing.sm,
    borderTopWidth: 1,
    borderTopColor: colors.line,
  },
  externalIconWrap: {
    width: 40, height: 40, borderRadius: 20,
    backgroundColor: colors.surface,
    alignItems: 'center', justifyContent: 'center',
  },
  externalLabel: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '600' },
});
