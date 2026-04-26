import { useMemo, useState } from 'react';
import { View, Text, Modal, Pressable, FlatList, StyleSheet } from 'react-native';
import { Share2 } from 'lucide-react-native';
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

  const { data: conversations, isLoading } = useQuery({
    queryKey: ['conversations'],
    queryFn: () => conversationService.getAll(),
    enabled: visible,
  });

  const handleShare = async (conversationId: string) => {
    setSendingTo(conversationId);
    try {
      await messageService.shareActivity(conversationId, activityId);
      Burnt.toast({ title: t('activity.shared'), preset: 'done' });
      onClose();
    } catch (err) {
      const errMsg = err instanceof Error ? err.message : '';
      if (errMsg.includes('Operation not permitted')) {
        Burnt.toast({ title: t('messagerie.rateLimited') });
      } else {
        Burnt.toast({ title: t('auth.unknownError') });
      }
    } finally {
      setSendingTo(null);
    }
  };

  return (
    <Modal visible={visible} animationType="slide" transparent onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose}>
        <Pressable style={styles.sheet} onPress={() => {}}>
          <View style={styles.handle} />
          <Text style={styles.title}>{t('activity.shareTitle')}</Text>
          {isLoading ? (
            <View style={styles.center}><LogoSpinner /></View>
          ) : !conversations || conversations.length === 0 ? (
            <Text style={styles.empty}>{t('activity.shareNoConversations')}</Text>
          ) : (
            <FlatList
              data={conversations}
              keyExtractor={(item) => item.id}
              renderItem={({ item }) => (
                <Pressable
                  style={[styles.row, sendingTo === item.id && styles.rowDisabled]}
                  onPress={() => handleShare(item.id)}
                  disabled={sendingTo !== null}
                >
                  <UserAvatar name={item.other_user_name} avatarUrl={item.other_user_avatar} size={40} />
                  <Text style={styles.name} numberOfLines={1}>{item.other_user_name}</Text>
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
