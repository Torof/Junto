import { useMemo, useState } from 'react';
import { View, Text, FlatList, Pressable, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import relativeTime from 'dayjs/plugin/relativeTime';
import 'dayjs/locale/fr';
import {
  Bell, UserPlus, UserCheck, UserMinus, Check, X, LogOut, Ban,
  Pencil, Star, AlertTriangle, MessageCircle, MapPinCheck, AlarmClock,
  type LucideIcon,
} from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { notificationService, type Notification } from '@/services/notification-service';

dayjs.extend(relativeTime);

type IconMeta = { icon: LucideIcon; color: string };

const getNotificationIcons = (colors: AppColors): Record<string, IconMeta> => ({
  join_request: { icon: UserPlus, color: colors.cta },
  participant_joined: { icon: UserCheck, color: colors.success },
  request_accepted: { icon: Check, color: colors.success },
  request_refused: { icon: X, color: colors.error },
  participant_removed: { icon: UserMinus, color: colors.error },
  participant_left: { icon: LogOut, color: colors.textSecondary },
  participant_left_late: { icon: AlertTriangle, color: colors.warning },
  activity_cancelled: { icon: Ban, color: colors.error },
  activity_updated: { icon: Pencil, color: colors.cta },
  rate_participants: { icon: Star, color: colors.warning },
  presence_reminder: { icon: MapPinCheck, color: colors.cta },
  presence_last_call: { icon: AlarmClock, color: colors.warning },
  alert_match: { icon: Bell, color: colors.cta },
  new_message: { icon: MessageCircle, color: colors.textPrimary },
});

const getDefaultIcon = (colors: AppColors): IconMeta => ({ icon: Bell, color: colors.textSecondary });

const ACTIONABLE_TYPES = new Set([
  'join_request',
  'seat_request',
  'contact_request',
  'presence_reminder',
  'presence_last_call',
  'rate_participants',
]);

type Tab = 'action' | 'updates';

export default function NotificationsScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const notificationIcons = useMemo(() => getNotificationIcons(colors), [colors]);
  const defaultIcon = useMemo(() => getDefaultIcon(colors), [colors]);
  const { t, i18n } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();

  const [activeTab, setActiveTab] = useState<Tab>('action');

  const { data: notifications, isLoading } = useQuery({
    queryKey: ['notifications'],
    queryFn: () => notificationService.getAll(),
  });

  const actionable = useMemo(
    () => (notifications ?? []).filter((n) => ACTIONABLE_TYPES.has(n.type)),
    [notifications],
  );
  const updates = useMemo(
    () => (notifications ?? []).filter((n) => !ACTIONABLE_TYPES.has(n.type)),
    [notifications],
  );
  const visible = activeTab === 'action' ? actionable : updates;
  const actionableUnread = actionable.filter((n) => !n.read_at).length;

  const handlePress = async (notification: Notification) => {
    if (!notification.read_at) {
      await notificationService.markAsRead(notification.id);
      await queryClient.invalidateQueries({ queryKey: ['notifications'] });
      await queryClient.invalidateQueries({ queryKey: ['notifications-count'] });
    }

    if (notification.type === 'rate_participants' && notification.data?.activity_id) {
      router.push(`/(auth)/peer-review/${notification.data.activity_id}`);
    } else if (notification.type === 'contact_request' || notification.type === 'seat_request') {
      router.push('/(auth)/(tabs)/messagerie?tab=requests');
    } else if (notification.type === 'contact_request_accepted') {
      router.push('/(auth)/(tabs)/messagerie');
    } else if (notification.type === 'seat_request_accepted' && notification.data?.conversation_id) {
      router.push(`/(auth)/conversation/${notification.data.conversation_id}`);
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
      {/* Tab bar */}
      <View style={styles.tabBar}>
        <Pressable
          style={[styles.tab, activeTab === 'action' && styles.tabActive]}
          onPress={() => setActiveTab('action')}
        >
          <Text style={[styles.tabText, activeTab === 'action' && styles.tabTextActive]}>
            {t('notifications.tabAction')}
          </Text>
          {actionableUnread > 0 && (
            <View style={styles.badge}>
              <Text style={styles.badgeText}>{actionableUnread}</Text>
            </View>
          )}
        </Pressable>
        <Pressable
          style={[styles.tab, activeTab === 'updates' && styles.tabActive]}
          onPress={() => setActiveTab('updates')}
        >
          <Text style={[styles.tabText, activeTab === 'updates' && styles.tabTextActive]}>
            {t('notifications.tabUpdates')}
          </Text>
        </Pressable>
      </View>

      {hasUnread && (
        <Pressable style={styles.markAllButton} onPress={handleMarkAllRead}>
          <Text style={styles.markAllText}>{t('notifications.markAllRead')}</Text>
        </Pressable>
      )}

      {isLoading ? (
        <View style={styles.center}>
          <Text style={styles.loadingText}>...</Text>
        </View>
      ) : visible.length === 0 ? (
        <View style={styles.center}>
          <Text style={styles.emptyText}>
            {activeTab === 'action' ? t('notifications.emptyAction') : t('notifications.emptyUpdates')}
          </Text>
        </View>
      ) : (
        <FlatList
          data={visible}
          keyExtractor={(item) => item.id}
          renderItem={({ item }) => {
            const meta = notificationIcons[item.type] ?? defaultIcon;
            const IconComp = meta.icon;
            return (
            <Pressable
              style={[styles.card, !item.read_at && styles.cardUnread]}
              onPress={() => handlePress(item)}
            >
              <View style={[styles.iconWrap, { backgroundColor: meta.color + '22' }]}>
                <IconComp size={20} color={meta.color} strokeWidth={2.2} />
              </View>
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
            );
          }}
          contentContainerStyle={styles.list}
        />
      )}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  tabBar: {
    flexDirection: 'row',
    paddingHorizontal: spacing.md,
    paddingTop: spacing.sm,
    paddingBottom: spacing.xs,
    gap: spacing.sm,
  },
  tab: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: spacing.xs,
    paddingVertical: spacing.sm,
    borderRadius: radius.full,
    backgroundColor: colors.surface,
  },
  tabActive: { backgroundColor: colors.cta },
  tabText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600' },
  tabTextActive: { color: colors.textPrimary },
  badge: {
    minWidth: 20, height: 20, borderRadius: 10,
    backgroundColor: colors.error,
    alignItems: 'center', justifyContent: 'center',
    paddingHorizontal: 6,
  },
  badgeText: { color: colors.textPrimary, fontSize: fontSizes.xs - 1, fontWeight: 'bold' },
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
  iconWrap: {
    width: 40,
    height: 40,
    borderRadius: 20,
    alignItems: 'center',
    justifyContent: 'center',
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
