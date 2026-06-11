import { useState, useEffect, useMemo, useRef } from 'react';
import { View, Text, TextInput, Pressable, ScrollView, StyleSheet, Alert, Modal, KeyboardAvoidingView, Platform } from 'react-native';
import { useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import * as Burnt from 'burnt';
import { Send } from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { wallService, type WallMessageWithProfile } from '@/services/wall-service';
import { participationService } from '@/services/participation-service';
import { getFriendlyError } from '@/utils/friendly-error';
import { useMessageStore } from '@/store/message-store';
import { UserAvatar } from './user-avatar';
import { supabase } from '@/services/supabase';
import { haptic } from '@/lib/haptics';

interface ActivityWallProps {
  activityId: string;
  isActive: boolean;
  currentUserId: string | null;
}

export function ActivityWall({ activityId, isActive, currentUserId }: ActivityWallProps) {
  const { t, i18n } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const router = useRouter();
  const queryClient = useQueryClient();
  const [message, setMessage] = useState('');
  const [isSending, setIsSending] = useState(false);
  const [actionMenuMessage, setActionMenuMessage] = useState<WallMessageWithProfile | null>(null);
  const [editingMessage, setEditingMessage] = useState<WallMessageWithProfile | null>(null);
  const [editDraft, setEditDraft] = useState('');
  const [isSavingEdit, setIsSavingEdit] = useState(false);
  const scrollRef = useRef<ScrollView>(null);
  const markWallRead = useMessageStore((s) => s.markWallRead);

  const { data: messages, isLoading } = useQuery({
    queryKey: ['wall', activityId],
    queryFn: () => wallService.getMessages(activityId),
    // Realtime subscription is the primary update path — 60s is a
    // safety net for missed events only (prod audit D).
    refetchInterval: 60000,
  });

  // Reuse the participants query so we can decorate message authors whose
  // presence has been confirmed. This query is already populated by the
  // ParticipantList that lives in the same activity screen.
  const { data: participants } = useQuery({
    queryKey: ['participants', activityId],
    queryFn: () => participationService.getForActivity(activityId),
    staleTime: 15_000,
  });

  // Current user's public profile drives the composer avatar so the
  // input row reads as "you're posting as Marie".
  const { data: currentUserProfile } = useQuery({
    queryKey: ['currentUserProfile', currentUserId],
    queryFn: async () => {
      if (!currentUserId) return null;
      const { data } = await supabase
        .from('public_profiles')
        .select('id, display_name, avatar_url')
        .eq('id', currentUserId)
        .single();
      return data as { id: string; display_name: string; avatar_url: string | null } | null;
    },
    enabled: !!currentUserId,
    staleTime: 5 * 60_000,
  });

  const confirmedUserIds = useMemo(
    () => new Set((participants ?? []).filter((p) => p.confirmed_present === true).map((p) => p.user_id)),
    [participants],
  );

  // Auto-scroll to bottom when messages arrive + mark wall as read whenever
  // the user is on the chat tab (this component only mounts when active).
  useEffect(() => {
    if (messages !== undefined) {
      markWallRead(activityId);
      const t = setTimeout(() => scrollRef.current?.scrollToEnd({ animated: true }), 50);
      return () => clearTimeout(t);
    }
  }, [messages, activityId, markWallRead]);

  // Supabase Realtime subscription
  useEffect(() => {
    const channel = supabase
      .channel(`wall:${activityId}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'wall_messages',
          filter: `activity_id=eq.${activityId}`,
        },
        () => {
          queryClient.invalidateQueries({ queryKey: ['wall', activityId] });
        },
      )
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'wall_messages',
          filter: `activity_id=eq.${activityId}`,
        },
        () => {
          // Catches edits + soft-deletes so the list stays fresh without
          // waiting for the 15s poll.
          queryClient.invalidateQueries({ queryKey: ['wall', activityId] });
        },
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [activityId, queryClient]);

  const handleSend = async () => {
    haptic.light();
    if (!message.trim() || isSending) return;

    setIsSending(true);
    try {
      await wallService.send(activityId, message.trim());
      setMessage('');
      await queryClient.invalidateQueries({ queryKey: ['wall', activityId] });
    } catch (err) {
      const errMsg = err instanceof Error ? err.message : '';
      if (errMsg.includes('Operation not permitted')) {
        Burnt.toast({ title: t('wall.rateLimited') });
      } else {
        Alert.alert(t('auth.error'), getFriendlyError(err, 'sendWallMessage'));
      }
    } finally {
      setIsSending(false);
    }
  };

  const openActionMenu = (m: WallMessageWithProfile) => {
    haptic.light();
    setActionMenuMessage(m);
  };

  const handleStartEdit = () => {
    if (!actionMenuMessage) return;
    setEditDraft(actionMenuMessage.content);
    setEditingMessage(actionMenuMessage);
    setActionMenuMessage(null);
  };

  const handleSaveEdit = async () => {
    if (!editingMessage || !editDraft.trim() || isSavingEdit) return;
    setIsSavingEdit(true);
    try {
      await wallService.edit(editingMessage.id, editDraft.trim());
      await queryClient.invalidateQueries({ queryKey: ['wall', activityId] });
      setEditingMessage(null);
      setEditDraft('');
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'editWallMessage'));
    } finally {
      setIsSavingEdit(false);
    }
  };

  const handleDelete = () => {
    if (!actionMenuMessage) return;
    const target = actionMenuMessage;
    setActionMenuMessage(null);
    Alert.alert(
      t('wall.deleteConfirmTitle', { defaultValue: 'Supprimer le message ?' }),
      t('wall.deleteConfirmBody', { defaultValue: 'Cette action est définitive.' }),
      [
        { text: t('common.cancel', { defaultValue: 'Annuler' }), style: 'cancel' },
        {
          text: t('common.delete', { defaultValue: 'Supprimer' }),
          style: 'destructive',
          onPress: async () => {
            try {
              await wallService.remove(target.id);
              await queryClient.invalidateQueries({ queryKey: ['wall', activityId] });
            } catch (err) {
              Alert.alert(t('auth.error'), getFriendlyError(err, 'deleteWallMessage'));
            }
          },
        },
      ],
    );
  };

  // Date-separator label for a given ISO timestamp.
  const dateSeparatorLabel = (iso: string): string => {
    const days = dayjs(iso).startOf('day').diff(dayjs().startOf('day'), 'day');
    if (days === 0) return t('wall.dateToday', { defaultValue: "Aujourd'hui" });
    if (days === -1) return t('wall.dateYesterday', { defaultValue: 'Hier' });
    return dayjs(iso).locale(i18n.language === 'fr' ? 'fr' : 'en').format(
      i18n.language === 'fr' ? 'dddd D MMMM' : 'dddd MMMM D',
    );
  };

  return (
    <View style={styles.container}>
      <ScrollView
        ref={scrollRef}
        style={styles.messageScroll}
        contentContainerStyle={styles.messageScrollContent}
        keyboardShouldPersistTaps="handled"
        keyboardDismissMode="interactive"
      >
        {isLoading ? (
          <Text style={styles.loadingText}>...</Text>
        ) : !messages || messages.length === 0 ? (
          <Text style={styles.emptyText}>{t('wall.empty')}</Text>
        ) : (
          messages.map((item, index) => {
            const prev = messages[index - 1];
            const next = messages[index + 1];
            const isMine = !!currentUserId && item.user_id === currentUserId;
            const isFirstOfDay = !prev || !dayjs(item.created_at).isSame(dayjs(prev.created_at), 'day');
            const isFirstInGroup = isFirstOfDay || !prev || prev.user_id !== item.user_id;
            const isLastInGroup =
              !next ||
              next.user_id !== item.user_id ||
              !dayjs(item.created_at).isSame(dayjs(next.created_at), 'day');

            return (
              <View key={item.id}>
                {isFirstOfDay && (
                  <View style={styles.dateSeparator}>
                    <View style={styles.dateLine} />
                    <Text style={styles.dateLabel}>{dateSeparatorLabel(item.created_at)}</Text>
                    <View style={styles.dateLine} />
                  </View>
                )}
                <View
                  style={[
                    styles.messageRow,
                    isMine ? styles.messageRight : styles.messageLeft,
                    isFirstInGroup ? styles.firstInGroup : styles.midInGroup,
                  ]}
                >
                  <Pressable
                    onLongPress={isMine && item.user_id ? () => openActionMenu(item) : undefined}
                    delayLongPress={250}
                    style={[
                      styles.messageCard,
                      isMine ? styles.messageCardMine : styles.messageCardOther,
                    ]}
                  >
                    {isFirstInGroup && (
                      <View style={styles.messageHeader}>
                        <Pressable
                          style={styles.authorLink}
                          onPress={() => item.user_id && router.push(`/(auth)/profile/${item.user_id}`)}
                          disabled={!item.user_id}
                        >
                          <UserAvatar
                            name={item.display_name ?? '?'}
                            avatarUrl={item.avatar_url}
                            size={22}
                            confirmedPresent={!!item.user_id && confirmedUserIds.has(item.user_id)}
                          />
                          <Text style={styles.authorName} numberOfLines={1}>
                            {isMine
                              ? t('wall.youAuthor', { defaultValue: 'Toi' })
                              : item.display_name ?? t('wall.deletedUser')}
                          </Text>
                        </Pressable>
                      </View>
                    )}
                    <Text style={styles.messageContent}>{item.content}</Text>
                    <View style={styles.messageFooter}>
                      {item.edited_at && (
                        <Text style={styles.editedTag}>
                          {t('wall.editedTag', { defaultValue: 'modifié' })}
                        </Text>
                      )}
                      {isLastInGroup && (
                        <Text style={styles.messageTime}>{dayjs(item.created_at).format('H[h]mm')}</Text>
                      )}
                    </View>
                  </Pressable>
                </View>
              </View>
            );
          })
        )}
      </ScrollView>

      {isActive && (
        <View style={styles.inputRow}>
          {currentUserProfile && (
            <UserAvatar
              name={currentUserProfile.display_name}
              avatarUrl={currentUserProfile.avatar_url}
              size={28}
            />
          )}
          <TextInput
            style={styles.input}
            value={message}
            onChangeText={setMessage}
            placeholder={t('wall.placeholder')}
            placeholderTextColor={colors.textSecondary}
            maxLength={2000}
            multiline
          />
          <Pressable
            style={[styles.sendButton, (!message.trim() || isSending) && styles.sendDisabled]}
            onPress={handleSend}
            disabled={!message.trim() || isSending}
            hitSlop={8}
          >
            <Send size={16} color="#FFFFFF" strokeWidth={2.4} />
          </Pressable>
        </View>
      )}

      {/* Action menu — long-press on own message → Edit / Delete options.
          Centered modal matching the trust/org modals' visual family. */}
      <Modal
        visible={actionMenuMessage !== null}
        animationType="fade"
        transparent
        onRequestClose={() => setActionMenuMessage(null)}
      >
        <Pressable style={styles.modalBackdrop} onPress={() => setActionMenuMessage(null)}>
          <Pressable style={styles.actionMenuCard} onPress={(e) => e.stopPropagation()}>
            <Pressable style={styles.actionMenuItem} onPress={handleStartEdit}>
              <Text style={styles.actionMenuItemText}>
                {t('wall.actionEdit', { defaultValue: 'Modifier' })}
              </Text>
            </Pressable>
            <View style={styles.actionMenuDivider} />
            <Pressable style={styles.actionMenuItem} onPress={handleDelete}>
              <Text style={[styles.actionMenuItemText, { color: colors.error }]}>
                {t('wall.actionDelete', { defaultValue: 'Supprimer' })}
              </Text>
            </Pressable>
          </Pressable>
        </Pressable>
      </Modal>

      {/* Edit modal — prefilled with the current message content. Save
          fires the edit_wall_message RPC; the message gets an "modifié"
          tag once edited_at is set. */}
      <Modal
        visible={editingMessage !== null}
        animationType="fade"
        transparent
        onRequestClose={() => setEditingMessage(null)}
      >
        <KeyboardAvoidingView
          style={{ flex: 1 }}
          behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        >
          <Pressable style={styles.modalBackdrop} onPress={() => setEditingMessage(null)}>
            <Pressable style={styles.editCard} onPress={(e) => e.stopPropagation()}>
              <Text style={styles.editTitle}>
                {t('wall.editTitle', { defaultValue: 'Modifier le message' })}
              </Text>
              <TextInput
                style={styles.editInput}
                value={editDraft}
                onChangeText={setEditDraft}
                multiline
                autoFocus
                maxLength={2000}
              />
              <View style={styles.editActions}>
                <Pressable
                  style={styles.editCancelBtn}
                  onPress={() => setEditingMessage(null)}
                  hitSlop={4}
                >
                  <Text style={styles.editCancelText}>
                    {t('common.cancel', { defaultValue: 'Annuler' })}
                  </Text>
                </Pressable>
                <Pressable
                  style={[styles.editSaveBtn, (!editDraft.trim() || isSavingEdit) && { opacity: 0.5 }]}
                  onPress={handleSaveEdit}
                  disabled={!editDraft.trim() || isSavingEdit}
                  hitSlop={4}
                >
                  <Text style={styles.editSaveText}>
                    {t('common.save', { defaultValue: 'Enregistrer' })}
                  </Text>
                </Pressable>
              </View>
            </Pressable>
          </Pressable>
        </KeyboardAvoidingView>
      </Modal>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: {
    flex: 1,
  },
  loadingText: {
    color: colors.textSecondary,
    fontSize: fontSizes.md,
    textAlign: 'center',
    paddingVertical: spacing.lg,
  },
  emptyText: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
    textAlign: 'center',
    paddingVertical: spacing.lg,
  },
  messageScroll: {
    flex: 1,
  },
  messageScrollContent: {
    paddingBottom: spacing.sm,
    flexGrow: 1,
  },

  // Day-divider — thin lines flanking a small label, sits before the
  // first message of a new day so scrolling history keeps date context.
  dateSeparator: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    paddingVertical: spacing.sm,
  },
  dateLine: {
    flex: 1,
    height: 1,
    backgroundColor: colors.line,
  },
  dateLabel: {
    color: colors.textMuted,
    fontSize: fontSizes.xs,
    fontWeight: '600',
    textTransform: 'capitalize',
  },

  // Side alignment + group spacing. firstInGroup gets larger top margin
  // so a new author starts visually separated; midInGroup messages snug
  // up to the previous one (1px) so the run reads as one block.
  messageRow: {
    flexDirection: 'row',
  },
  messageLeft: {
    justifyContent: 'flex-start',
  },
  messageRight: {
    justifyContent: 'flex-end',
  },
  firstInGroup: {
    marginTop: spacing.sm,
  },
  midInGroup: {
    marginTop: 1,
  },

  messageCard: {
    borderRadius: radius.md,
    paddingVertical: spacing.xs + 2,
    paddingHorizontal: spacing.sm + 2,
    maxWidth: '85%',
  },
  // Mine: cta-tinted bg with mild border so own messages are clearly
  // distinct from incoming. Tail-curve bottom-right corner subtly
  // sharpened so the bubble points "from me".
  messageCardMine: {
    backgroundColor: colors.cta + '24',
    borderTopRightRadius: radius.md,
    borderBottomRightRadius: radius.sm,
  },
  // Others: plain surface with line border. Sharper bottom-left corner
  // points "from them".
  messageCardOther: {
    backgroundColor: colors.surface,
    borderTopLeftRadius: radius.md,
    borderBottomLeftRadius: radius.sm,
  },

  messageHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: spacing.xs - 2,
  },
  authorLink: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs + 2,
    flex: 1,
  },
  authorName: {
    color: colors.textPrimary,
    fontSize: fontSizes.xs,
    fontWeight: '700',
    flex: 1,
  },
  messageContent: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    lineHeight: 19,
  },
  messageFooter: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'flex-end',
    gap: 4,
    marginTop: 2,
  },
  editedTag: {
    color: colors.textMuted,
    fontSize: fontSizes.xs - 2,
    fontStyle: 'italic',
  },
  messageTime: {
    color: colors.textMuted,
    fontSize: fontSizes.xs - 1,
  },

  // Composer — current user's avatar on the left so it reads "you're
  // posting", text input flexes to fill, send button pinned right.
  inputRow: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    paddingTop: spacing.sm,
    gap: spacing.xs + 2,
    borderTopWidth: 1,
    borderTopColor: colors.line,
  },
  input: {
    flex: 1,
    backgroundColor: colors.surface,
    color: colors.textPrimary,
    borderRadius: radius.md,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    fontSize: fontSizes.sm,
    maxHeight: 100,
  },
  sendButton: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: colors.cta,
    alignItems: 'center',
    justifyContent: 'center',
  },
  sendDisabled: {
    opacity: 0.4,
  },

  // Action menu (long-press) + edit modal — same scrim + centered card
  // grammar as the trust-pillar / org modals.
  modalBackdrop: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.92)',
    alignItems: 'center',
    justifyContent: 'center',
    padding: spacing.lg,
  },
  actionMenuCard: {
    width: '100%',
    maxWidth: 320,
    backgroundColor: colors.background,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.line,
    overflow: 'hidden',
  },
  actionMenuItem: {
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.lg,
    alignItems: 'center',
  },
  actionMenuItemText: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    fontWeight: '600',
  },
  actionMenuDivider: {
    height: 1,
    backgroundColor: colors.line,
  },
  editCard: {
    width: '100%',
    maxWidth: 380,
    backgroundColor: colors.background,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.line,
    padding: spacing.lg,
  },
  editTitle: {
    color: colors.textPrimary,
    fontSize: fontSizes.lg,
    fontWeight: 'bold',
    marginBottom: spacing.md,
  },
  editInput: {
    backgroundColor: colors.surface,
    color: colors.textPrimary,
    borderRadius: radius.md,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm + 2,
    fontSize: fontSizes.sm,
    minHeight: 80,
    maxHeight: 200,
    textAlignVertical: 'top',
    marginBottom: spacing.md,
  },
  editActions: {
    flexDirection: 'row',
    gap: spacing.sm,
  },
  editCancelBtn: {
    flex: 1,
    height: 44,
    borderRadius: radius.md,
    backgroundColor: colors.surfaceAlt,
    borderWidth: 1,
    borderColor: colors.line,
    alignItems: 'center',
    justifyContent: 'center',
  },
  editCancelText: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '600',
  },
  editSaveBtn: {
    flex: 1.4,
    height: 44,
    borderRadius: radius.md,
    backgroundColor: colors.cta,
    alignItems: 'center',
    justifyContent: 'center',
  },
  editSaveText: {
    color: '#FFFFFF',
    fontSize: fontSizes.sm,
    fontWeight: '700',
  },
});
