import { View, Text, FlatList, Pressable, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import relativeTime from 'dayjs/plugin/relativeTime';
import 'dayjs/locale/fr';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { conversationService, type Conversation } from '@/services/conversation-service';
import { UserAvatar } from '@/components/user-avatar';
import { useMessageStore } from '@/store/message-store';
import { supabase } from '@/services/supabase';

dayjs.extend(relativeTime);

export default function MessagerieScreen() {
  const { t, i18n } = useTranslation();
  const router = useRouter();

  const { markSeen } = useMessageStore();

  const { data: currentUserId } = useQuery({
    queryKey: ['currentUser-id'],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id,
  });

  const { data: conversations, isLoading } = useQuery({
    queryKey: ['conversations'],
    queryFn: async () => {
      const result = await conversationService.getAll();
      markSeen();
      return result;
    },
  });

  if (isLoading) {
    return (
      <View style={styles.center}>
        <Text style={styles.loadingText}>...</Text>
      </View>
    );
  }

  if (!conversations || conversations.length === 0) {
    return (
      <View style={styles.center}>
        <Text style={styles.emptyText}>{t('messagerie.empty')}</Text>
      </View>
    );
  }

  return (
    <FlatList
      data={conversations}
      keyExtractor={(item) => item.id}
      renderItem={({ item }) => {
        const isUnread = item.last_message_sender_id != null && item.last_message_sender_id !== currentUserId;
        return (
        <Pressable
          style={styles.card}
          onPress={() => router.push(`/(auth)/conversation/${item.id}`)}
        >
          <UserAvatar name={item.other_user_name} avatarUrl={item.other_user_avatar} size={48} />
          <View style={styles.cardContent}>
            <View style={styles.cardHeader}>
              <Text style={[styles.name, isUnread && styles.nameUnread]} numberOfLines={1}>{item.other_user_name}</Text>
              {item.last_message_at && (
                <Text style={styles.time}>
                  {dayjs(item.last_message_at).locale(i18n.language).fromNow()}
                </Text>
              )}
            </View>
            {item.last_message_content && (
              <Text style={[styles.preview, isUnread && styles.previewUnread]} numberOfLines={1}>{item.last_message_content}</Text>
            )}
          </View>
          {isUnread && <View style={styles.unreadDot} />}
        </Pressable>
      );
      }}
      contentContainerStyle={styles.list}
      style={styles.container}
    />
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  list: { padding: spacing.md },
  center: { flex: 1, backgroundColor: colors.background, alignItems: 'center', justifyContent: 'center' },
  loadingText: { color: colors.textSecondary, fontSize: fontSizes.lg },
  emptyText: { color: colors.textSecondary, fontSize: fontSizes.md },
  card: {
    flexDirection: 'row', alignItems: 'center',
    backgroundColor: colors.surface, borderRadius: radius.md,
    padding: spacing.md, marginBottom: spacing.sm, gap: spacing.md,
  },
  cardContent: { flex: 1 },
  cardHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  name: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: 'bold', flex: 1 },
  nameUnread: { color: colors.cta },
  time: { color: colors.textSecondary, fontSize: fontSizes.xs },
  preview: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: 2 },
  previewUnread: { color: colors.textPrimary, fontWeight: 'bold' },
  unreadDot: { width: 8, height: 8, borderRadius: 4, backgroundColor: colors.cta, marginLeft: spacing.sm },
});
