import { View, Text, FlatList, Pressable, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import relativeTime from 'dayjs/plugin/relativeTime';
import 'dayjs/locale/fr';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { notificationService, type Notification } from '@/services/notification-service';

dayjs.extend(relativeTime);

const NOTIFICATION_ICONS: Record<string, string> = {
  join_request: '🔔',
  participant_joined: '✅',
  request_accepted: '🎉',
  request_refused: '❌',
  participant_removed: '🚫',
  participant_left: '👋',
  activity_cancelled: '🚨',
  activity_updated: '📝',
  confirm_presence: '📋',
};

export default function NotificationsScreen() {
  const { t, i18n } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();

  const { data: notifications, isLoading } = useQuery({
    queryKey: ['notifications'],
    queryFn: () => notificationService.getAll(),
  });

  const handlePress = async (notification: Notification) => {
    if (!notification.read_at) {
      await notificationService.markAsRead(notification.id);
      await queryClient.invalidateQueries({ queryKey: ['notifications'] });
      await queryClient.invalidateQueries({ queryKey: ['notifications-count'] });
    }

    if (notification.type === 'confirm_presence' && notification.data?.activity_id) {
      router.push(`/(auth)/confirm-presence/${notification.data.activity_id}`);
    } else if (notification.data?.conversation_id) {
      router.push(`/(auth)/conversation/${notification.data.conversation_id}`);
    } else if (notification.data?.activity_id) {
      router.push(`/(auth)/activity/${notification.data.activity_id}`);
    }
  };

  const handleMarkAllRead = async () => {
    await notificationService.markAllAsRead();
    await queryClient.invalidateQueries({ queryKey: ['notifications'] });
    await queryClient.invalidateQueries({ queryKey: ['notifications-count'] });
  };

  const hasUnread = notifications?.some((n) => !n.read_at);

  return (
    <View style={styles.container}>
      {hasUnread && (
        <Pressable style={styles.markAllButton} onPress={handleMarkAllRead}>
          <Text style={styles.markAllText}>{t('notifications.markAllRead')}</Text>
        </Pressable>
      )}

      {isLoading ? (
        <View style={styles.center}>
          <Text style={styles.loadingText}>...</Text>
        </View>
      ) : !notifications || notifications.length === 0 ? (
        <View style={styles.center}>
          <Text style={styles.emptyText}>{t('notifications.empty')}</Text>
        </View>
      ) : (
        <FlatList
          data={notifications}
          keyExtractor={(item) => item.id}
          renderItem={({ item }) => (
            <Pressable
              style={[styles.card, !item.read_at && styles.cardUnread]}
              onPress={() => handlePress(item)}
            >
              <Text style={styles.icon}>{NOTIFICATION_ICONS[item.type] ?? '🔔'}</Text>
              <View style={styles.cardContent}>
                <Text style={[styles.cardTitle, !item.read_at && styles.cardTitleUnread]}>
                  {item.title}
                </Text>
                <Text style={styles.cardBody} numberOfLines={2}>{item.body}</Text>
                <Text style={styles.cardTime}>
                  {dayjs(item.created_at).locale(i18n.language).fromNow()}
                </Text>
              </View>
              {!item.read_at && <View style={styles.unreadDot} />}
            </Pressable>
          )}
          contentContainerStyle={styles.list}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  markAllButton: {
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    alignItems: 'flex-end',
  },
  markAllText: {
    color: colors.cta,
    fontSize: fontSizes.sm,
  },
  list: {
    padding: spacing.md,
  },
  card: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    padding: spacing.md,
    marginBottom: spacing.sm,
  },
  cardUnread: {
    backgroundColor: colors.cta + '15',
  },
  icon: {
    fontSize: 24,
    marginRight: spacing.md,
  },
  cardContent: {
    flex: 1,
  },
  cardTitle: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    marginBottom: 2,
  },
  cardTitleUnread: {
    fontWeight: 'bold',
  },
  cardBody: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    marginBottom: 4,
  },
  cardTime: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    opacity: 0.7,
  },
  unreadDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: colors.cta,
    marginLeft: spacing.sm,
  },
  center: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  loadingText: {
    color: colors.textSecondary,
    fontSize: fontSizes.lg,
  },
  emptyText: {
    color: colors.textSecondary,
    fontSize: fontSizes.md,
  },
});
