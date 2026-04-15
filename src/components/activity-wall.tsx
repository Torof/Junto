import { useState, useEffect } from 'react';
import { View, Text, TextInput, Pressable, StyleSheet, Alert } from 'react-native';
import { useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import * as Burnt from 'burnt';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { wallService, type WallMessageWithProfile } from '@/services/wall-service';
import { getFriendlyError } from '@/utils/friendly-error';
import { UserAvatar } from './user-avatar';
import { supabase } from '@/services/supabase';

interface ActivityWallProps {
  activityId: string;
  isActive: boolean;
}

export function ActivityWall({ activityId, isActive }: ActivityWallProps) {
  const { t } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const [message, setMessage] = useState('');
  const [isSending, setIsSending] = useState(false);

  const { data: messages, isLoading } = useQuery({
    queryKey: ['wall', activityId],
    queryFn: () => wallService.getMessages(activityId),
    refetchInterval: 15000,
  });

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
      <Text style={styles.sectionTitle}>{t('wall.title')}</Text>

      {isLoading ? (
        <Text style={styles.loadingText}>...</Text>
      ) : !messages || messages.length === 0 ? (
        <Text style={styles.emptyText}>{t('wall.empty')}</Text>
      ) : (
        <View style={styles.messageList}>
          {messages.map((item) => (
            <View key={item.id} style={styles.messageCard}>
              <View style={styles.messageHeader}>
                <Pressable
                  style={styles.authorLink}
                  onPress={() => item.user_id && router.push(`/(auth)/profile/${item.user_id}`)}
                  disabled={!item.user_id}
                >
                  <UserAvatar name={item.display_name ?? '?'} avatarUrl={item.avatar_url} size={24} />
                  <Text style={styles.authorName}>{item.display_name ?? t('wall.deletedUser')}</Text>
                </Pressable>
                <Text style={styles.messageTime}>{dayjs(item.created_at).format('HH:mm')}</Text>
              </View>
              <Text style={styles.messageContent}>{item.content}</Text>
            </View>
          ))}
        </View>
      )}

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
          >
            <Text style={styles.sendText}>↑</Text>
          </Pressable>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    marginTop: spacing.lg,
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
  messageList: {
    maxHeight: 300,
  },
  messageCard: {
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    padding: spacing.sm,
    marginBottom: spacing.xs,
  },
  messageHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 4,
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
    marginTop: spacing.sm,
    gap: spacing.xs,
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
