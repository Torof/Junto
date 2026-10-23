import { useMemo } from 'react';
import { View, FlatList, Pressable, StyleSheet, RefreshControl } from 'react-native';
import { AppText } from '@/components/app-text';
import { Stack, useRouter } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import relativeTime from 'dayjs/plugin/relativeTime';
import { MessagesSquare } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import { conversationService } from '@/services/conversation-service';
import { UserAvatar } from '@/components/user-avatar';
import { ReliabilityRing } from '@/components/reliability-ring';
import { LogoSpinner } from '@/components/logo-spinner';
import { isClientConversation } from '@/utils/client-conversation';

dayjs.extend(relativeTime);

// The pro's working view of their client conversations (Scott 2026-10-16):
// the SAME conversations as the main inbox — a DM opened by a confirmed
// booking (initiated_from = 'booking', 00451) — just filtered. Nothing is
// moved out of the messagerie; this screen answers « où sont mes messages
// clients » from the Espace pro without adding a category to the inbox.

export default function ProMessagesScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t, i18n } = useTranslation();
  const router = useRouter();

  const { data: conversations, isLoading, refetch, isRefetching } = useQuery({
    queryKey: ['conversations'],
    queryFn: () => conversationService.getAll(),
  });
  const clients = useMemo(() => (conversations ?? []).filter(isClientConversation), [conversations]);

  return (
    <View style={styles.container}>
      <Stack.Screen options={{ title: t('booking.clientMessagesTitle', { defaultValue: 'Messages clients' }) }} />
      {isLoading ? (
        <View style={styles.center}><LogoSpinner size={36} /></View>
      ) : clients.length === 0 ? (
        <View style={styles.center}>
          <MessagesSquare size={28} color={colors.textMuted} strokeWidth={2} />
          <AppText style={styles.emptyText}>
            {t('booking.clientMessagesEmpty', { defaultValue: 'Aucune conversation client pour l’instant. Elles s’ouvrent quand tu confirmes une réservation.' })}
          </AppText>
        </View>
      ) : (
        <FlatList
          data={clients}
          keyExtractor={(c) => c.id}
          contentContainerStyle={styles.list}
          refreshControl={<RefreshControl refreshing={isRefetching && !isLoading} onRefresh={() => refetch()} tintColor={colors.cta} colors={[colors.cta]} />}
          ItemSeparatorComponent={() => <View style={{ height: spacing.sm }} />}
          renderItem={({ item }) => {
            const name = item.other_user_name ?? '?';
            const time = item.last_message_at ? dayjs(item.last_message_at).locale(i18n.language).fromNow(true) : null;
            // The accept_booking seed message carries metadata.type
            // 'booking_accepted' (00416), not part of the client union yet.
            const meta = item.last_message_metadata as { type?: string } | null;
            const preview = meta?.type === 'booking_accepted'
              ? t('booking.previewAccepted', { defaultValue: 'Réservation confirmée' })
              : item.last_message_content;
            return (
              <Pressable
                style={({ pressed }) => [styles.row, item.is_unread && styles.rowUnread, pressed && styles.pressed]}
                onPress={() => router.push(`/(auth)/conversation/${item.id}`)}
              >
                <Pressable onPress={() => item.other_user_id && router.push(`/(auth)/profile/${item.other_user_id}`)} hitSlop={4}>
                  <ReliabilityRing tier={item.other_user_reliability_tier} size={44} strokeWidth={2.5} showLabel={false}>
                    <UserAvatar name={name} avatarUrl={item.other_user_avatar} size={44} />
                  </ReliabilityRing>
                </Pressable>
                <View style={{ flex: 1, minWidth: 0 }}>
                  <View style={styles.rowHeader}>
                    <AppText style={[styles.name, item.is_unread && styles.nameUnread]} numberOfLines={1}>{name}</AppText>
                    {time ? <AppText style={styles.time}>{time}</AppText> : null}
                    {item.is_unread ? <View style={styles.unreadDot} /> : null}
                  </View>
                  {preview ? (
                    <AppText style={[styles.preview, item.is_unread && styles.previewUnread]} numberOfLines={1}>{preview}</AppText>
                  ) : null}
                </View>
              </Pressable>
            );
          }}
        />
      )}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: spacing.xl, gap: spacing.sm },
  emptyText: { color: colors.textSecondary, fontSize: fontSizes.sm, textAlign: 'center', lineHeight: 20 },
  list: { padding: spacing.md },
  row: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 4,
    backgroundColor: colors.surface, borderRadius: radius.card, padding: spacing.sm + 4, ...shadows.card,
  },
  rowUnread: { backgroundColor: colors.cta + '0F' },
  pressed: { opacity: 0.9 },
  rowHeader: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  name: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.md - 1, fontWeight: '600' },
  nameUnread: { fontWeight: '800' },
  time: { color: colors.textMuted, fontSize: fontSizes.xs },
  unreadDot: { width: 8, height: 8, borderRadius: 4, backgroundColor: colors.cta },
  preview: { color: colors.textSecondary, fontSize: fontSizes.sm, marginTop: 2 },
  previewUnread: { color: colors.textPrimary, fontWeight: '600' },
});
