import { useMemo } from 'react';
import { View, Text, FlatList, Pressable, StyleSheet, ActivityIndicator } from 'react-native';
import { useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import relativeTime from 'dayjs/plugin/relativeTime';
import 'dayjs/locale/fr';
import {
  Bell, UserPlus, UserCheck, UserMinus, Check, X, LogOut, Ban,
  Pencil, Star, AlertTriangle, MessageCircle, AlarmClock, Hourglass, QrCode,
  Car, CarFront, CarTaxiFront, Mail, MailCheck, Users, BadgeCheck, Trophy,
  type LucideIcon,
} from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { notificationService, type Notification } from '@/services/notification-service';
import { PushDeniedBanner } from '@/components/push-denied-banner';
import * as Burnt from 'burnt';
import { getFriendlyError } from '@/utils/friendly-error';

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
  presence_pre_warning: { icon: Hourglass, color: colors.cta },
  presence_pre_warning_10min: { icon: AlarmClock, color: colors.cta },
  presence_validate_warning: { icon: AlarmClock, color: colors.warning },
  presence_validate_overdue: { icon: AlertTriangle, color: colors.warning },
  presence_validate_final: { icon: AlertTriangle, color: colors.error },
  presence_confirmed: { icon: BadgeCheck, color: colors.success },
  badge_unlocked: { icon: Trophy, color: colors.cta },
  pro_approved: { icon: BadgeCheck, color: colors.success },
  pro_rejected: { icon: BadgeCheck, color: colors.error },
  qr_create_reminder: { icon: QrCode, color: colors.cta },
  alert_match: { icon: Bell, color: colors.cta },
  new_message: { icon: MessageCircle, color: colors.textPrimary },
  peer_review_closing: { icon: Users, color: colors.warning },
  seat_request: { icon: Car, color: colors.cta },
  seat_request_accepted: { icon: CarFront, color: colors.success },
  seat_request_declined: { icon: Car, color: colors.error },
  seat_request_expired: { icon: CarTaxiFront, color: colors.textMuted },
  driver_left: { icon: Car, color: colors.warning },
  contact_request: { icon: Mail, color: colors.cta },
  contact_request_accepted: { icon: MailCheck, color: colors.success },
});

const getDefaultIcon = (colors: AppColors): IconMeta => ({ icon: Bell, color: colors.textSecondary });

function renderActivityUpdatedBody(
  fallback: string,
  changes: Record<string, boolean>,
  t: (k: string, opts?: Record<string, unknown>) => string,
): string {
  const fields = Object.keys(changes).filter((k) => changes[k]);
  if (fields.length === 0) return fallback;
  const labels = fields
    .map((f) => t(`activityUpdated.fields.${f}`))
    .filter((label) => label && !label.startsWith('activityUpdated.'));
  if (labels.length === 0) return fallback;
  return t('activityUpdated.summary', { fields: labels.join(', ') });
}

// Flat notifications list — embedded in the messaging hub's "Notifications" tab
// (Scott 2026-08-12 navbar refonte). Actionable requests keep their rich UI in
// the "Demandes" tab; this is the full chronological log.
export function NotificationsView() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const notificationIcons = useMemo(() => getNotificationIcons(colors), [colors]);
  const defaultIcon = useMemo(() => getDefaultIcon(colors), [colors]);
  const { t, i18n } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();

  const { data: notifications, isLoading } = useQuery({
    queryKey: ['notifications'],
    queryFn: () => notificationService.getAll(),
  });

  const handlePress = async (notification: Notification) => {
    if (!notification.read_at) {
      try {
        await notificationService.markAsRead(notification.id);
        await queryClient.invalidateQueries({ queryKey: ['notifications'] });
        await queryClient.invalidateQueries({ queryKey: ['notifications-count'] });
      } catch { /* non-fatal — row stays unread, retap retries */ }
    }

    if (notification.type === 'pro_approved' || notification.type === 'pro_rejected') {
      await queryClient.invalidateQueries({ queryKey: ['currentUser'] });
      await queryClient.invalidateQueries({ queryKey: ['pro-profile-mine'] });
    }

    if ((notification.type === 'rate_participants' || notification.type === 'peer_review_closing') && notification.data?.activity_id) {
      router.push(`/(auth)/peer-review/${notification.data.activity_id}`);
    } else if (notification.type === 'contact_request' || notification.type === 'seat_request') {
      router.push('/(auth)/(tabs)/messagerie?tab=requests');
    } else if (notification.type === 'contact_request_accepted') {
      router.push('/(auth)/(tabs)/messagerie');
    } else if (notification.type === 'seat_request_accepted' && notification.data?.conversation_id) {
      router.push(`/(auth)/conversation/${notification.data.conversation_id}`);
    } else if (notification.data?.conversation_id) {
      router.push(`/(auth)/conversation/${notification.data.conversation_id}`);
    } else if (notification.type === 'pro_rejected') {
      router.push('/(auth)/pro/edit');
    } else if (notification.data?.offering_id) {
      router.push(`/(auth)/pro/offering/${notification.data.offering_id}`);
    } else if (notification.data?.pro_id) {
      router.push(`/(auth)/pro/${notification.data.pro_id}`);
    } else if (notification.data?.activity_id) {
      router.push(`/(auth)/activity/${notification.data.activity_id}`);
    }
  };

  const handleMarkAllRead = async () => {
    try {
      await notificationService.markAllAsRead();
      await queryClient.invalidateQueries({ queryKey: ['notifications'] });
      await queryClient.invalidateQueries({ queryKey: ['notifications-count'] });
    } catch (err) {
      Burnt.toast({ title: getFriendlyError(err, 'generic') });
    }
  };

  const hasUnread = notifications?.some((n) => !n.read_at);

  return (
    <View style={styles.container}>
      <PushDeniedBanner />

      {hasUnread && (
        <View style={styles.actionsRow}>
          <Pressable onPress={handleMarkAllRead} hitSlop={8}>
            <Text style={styles.markAllText}>{t('notifications.markAllRead')}</Text>
          </Pressable>
        </View>
      )}

      {isLoading ? (
        <View style={styles.center}>
          <ActivityIndicator color={colors.textSecondary} />
        </View>
      ) : (notifications ?? []).length === 0 ? (
        <View style={styles.center}>
          <Text style={styles.emptyText}>{t('notifications.emptyUpdates')}</Text>
        </View>
      ) : (
        <FlatList
          data={notifications ?? []}
          keyExtractor={(item) => item.id}
          ItemSeparatorComponent={() => <View style={styles.separator} />}
          renderItem={({ item }) => {
            const meta = notificationIcons[item.type] ?? defaultIcon;
            const IconComp = meta.icon;
            const body = item.type === 'activity_updated' && item.data?.changes
              ? renderActivityUpdatedBody(item.body, item.data.changes as Record<string, boolean>, t)
              : item.body;
            const isUnread = !item.read_at;
            return (
              <Pressable style={[styles.row, isUnread && styles.rowUnread]} onPress={() => handlePress(item)}>
                <View style={styles.iconWrap}>
                  <IconComp size={18} color={meta.color} strokeWidth={2.2} />
                </View>
                <View style={styles.rowContent}>
                  <View style={styles.rowHeader}>
                    <Text style={[styles.rowTitle, isUnread && styles.rowTitleUnread]} numberOfLines={1}>{item.title}</Text>
                    <Text style={styles.rowTime}>{dayjs(item.created_at).locale(i18n.language).fromNow(true)}</Text>
                    {isUnread && <View style={styles.unreadDot} />}
                  </View>
                  <Text style={styles.rowBody} numberOfLines={1}>{body}</Text>
                </View>
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
  container: { flex: 1, backgroundColor: colors.background },
  actionsRow: { flexDirection: 'row', justifyContent: 'flex-end', paddingHorizontal: spacing.md, paddingVertical: spacing.sm },
  markAllText: { color: colors.cta, fontSize: fontSizes.xs, fontWeight: '600' },
  separator: { height: 1, backgroundColor: colors.borderMuted, marginLeft: spacing.md + 24 + spacing.sm },
  row: { flexDirection: 'row', alignItems: 'center', paddingVertical: spacing.sm, paddingLeft: spacing.md, paddingRight: spacing.md, minHeight: 56 },
  rowUnread: { backgroundColor: colors.cta + '12' },
  unreadDot: { width: 8, height: 8, borderRadius: 4, backgroundColor: colors.cta, alignSelf: 'center' },
  iconWrap: { width: 24, height: 24, alignItems: 'center', justifyContent: 'center', marginRight: spacing.sm },
  rowContent: { flex: 1, minWidth: 0 },
  rowHeader: { flexDirection: 'row', alignItems: 'baseline', gap: spacing.sm },
  rowTitle: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '500' },
  rowTitleUnread: { fontWeight: '700' },
  rowTime: { color: colors.textSecondary, fontSize: fontSizes.xs },
  rowBody: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: 2 },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: spacing.xl },
  emptyText: { color: colors.textSecondary, fontSize: fontSizes.md },
  list: { paddingBottom: spacing.md },
});
