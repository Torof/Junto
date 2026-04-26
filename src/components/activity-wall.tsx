import { useState, useEffect, useMemo, useRef } from 'react';
import { View, Text, TextInput, Pressable, ScrollView, StyleSheet, Alert } from 'react-native';
import { useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import * as Burnt from 'burnt';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { wallService } from '@/services/wall-service';
import { getFriendlyError } from '@/utils/friendly-error';
import { useMessageStore } from '@/store/message-store';
import { UserAvatar } from './user-avatar';
import { supabase } from '@/services/supabase';
import { haptic } from '@/lib/haptics';

interface ActivityWallProps {
  activityId: string;
  isActive: boolean;
}

export function ActivityWall({ activityId, isActive }: ActivityWallProps) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const router = useRouter();
  const queryClient = useQueryClient();
  const [message, setMessage] = useState('');
  const [isSending, setIsSending] = useState(false);
  const scrollRef = useRef<ScrollView>(null);
  const markWallRead = useMessageStore((s) => s.markWallRead);

  const { data: messages, isLoading } = useQuery({
    queryKey: ['wall', activityId],
    queryFn: () => wallService.getMessages(activityId),
    refetchInterval: 15000,
  });

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
          (() => {
            const sides: ('left' | 'right')[] = [];
            messages.forEach((item, i) => {
              if (i === 0) { sides.push('left'); return; }
              sides.push(item.user_id !== messages[i - 1]?.user_id ? (sides[i - 1] === 'left' ? 'right' : 'left') : sides[i - 1]!);
            });
            return messages.map((item, index) => (
              <View key={item.id} style={[styles.messageRow, sides[index] === 'left' ? styles.messageLeft : styles.messageRight]}>
                <View style={styles.messageCard}>
                  <View style={styles.messageHeader}>
                    <Pressable
                      style={styles.authorLink}
                      onPress={() => item.user_id && router.push(`/(auth)/profile/${item.user_id}`)}
                      disabled={!item.user_id}
                    >
                      <UserAvatar name={item.display_name ?? '?'} avatarUrl={item.avatar_url} size={24} />
                      <Text style={styles.authorName} numberOfLines={1}>{item.display_name ?? t('wall.deletedUser')}</Text>
                    </Pressable>
                    <Text style={styles.messageTime}>{dayjs(item.created_at).format('H[h]mm')}</Text>
                  </View>
                  <Text style={styles.messageContent}>{item.content}</Text>
                </View>
              </View>
            ));
          })()
        )}
      </ScrollView>

      {isActive && (
        <View style={styles.inputRow}>
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
            <Text style={styles.sendText}>↑</Text>
          </Pressable>
        </View>
      )}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: {
    flex: 1,
  },
  sectionTitle: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    textTransform: 'uppercase',
    marginBottom: spacing.sm,
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
  messageRow: {
    flexDirection: 'row',
    marginBottom: spacing.xs,
  },
  messageLeft: {
    justifyContent: 'flex-start',
  },
  messageRight: {
    justifyContent: 'flex-end',
  },
  messageCard: {
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    padding: spacing.sm,
    maxWidth: '85%',
  },
  messageHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: spacing.xs,
  },
  avatar: {
    width: 24,
    height: 24,
    borderRadius: 12,
    backgroundColor: colors.background,
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: spacing.xs,
  },
  avatarText: {
    color: colors.cta,
    fontSize: fontSizes.xs,
    fontWeight: 'bold',
  },
  authorLink: {
    flexDirection: 'row',
    alignItems: 'center',
    flex: 1,
    gap: spacing.sm,
  },
  authorName: {
    color: colors.textPrimary,
    fontSize: fontSizes.xs,
    fontWeight: 'bold',
    flex: 1,
  },
  messageTime: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs - 2,
  },
  messageContent: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    paddingLeft: 24 + spacing.xs,
  },
  inputRow: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    paddingTop: spacing.sm,
    gap: spacing.xs,
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
  sendText: {
    color: colors.textPrimary,
    fontSize: 18,
    fontWeight: 'bold',
  },
});
