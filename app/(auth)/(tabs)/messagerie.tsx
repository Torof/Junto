import { View, Text, FlatList, Pressable, StyleSheet, ActivityIndicator } from 'react-native';
import { useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import relativeTime from 'dayjs/plugin/relativeTime';
import 'dayjs/locale/fr';
import * as Burnt from 'burnt';
import { Check, X } from 'lucide-react-native';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { conversationService, type Conversation, type PendingRequest } from '@/services/conversation-service';
import { UserAvatar } from '@/components/user-avatar';
import { ReliabilityRing } from '@/components/reliability-ring';
import { useMessageStore } from '@/store/message-store';
import { supabase } from '@/services/supabase';
import { useState } from 'react';

dayjs.extend(relativeTime);

export default function MessagerieScreen() {
  const { t, i18n } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const [loadingRequestId, setLoadingRequestId] = useState<string | null>(null);

  const { isConversationUnread } = useMessageStore();

  const { data: currentUserId } = useQuery({
    queryKey: ['currentUser-id'],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id,
  });

  const { data: conversations, isLoading } = useQuery({
    queryKey: ['conversations'],
    queryFn: () => conversationService.getAll(),
  });

  const { data: pendingRequests } = useQuery({
    queryKey: ['pending-requests'],
    queryFn: () => conversationService.getPendingReceived(),
  });

  const handleAccept = async (requestId: string) => {
    setLoadingRequestId(requestId);
    try {
      await conversationService.acceptRequest(requestId);
      await queryClient.invalidateQueries({ queryKey: ['pending-requests'] });
      await queryClient.invalidateQueries({ queryKey: ['conversations'] });
      Burnt.toast({ title: t('messagerie.requestAccepted'), preset: 'done' });
    } catch {
      Burnt.toast({ title: t('auth.unknownError') });
    } finally {
      setLoadingRequestId(null);
    }
  };

  const handleDecline = async (requestId: string) => {
    setLoadingRequestId(requestId);
    try {
      await conversationService.declineRequest(requestId);
      await queryClient.invalidateQueries({ queryKey: ['pending-requests'] });
    } catch {
      Burnt.toast({ title: t('auth.unknownError') });
    } finally {
      setLoadingRequestId(null);
    }
  };

  if (isLoading) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color={colors.cta} />
      </View>
    );
  }

  const hasPending = (pendingRequests ?? []).length > 0;
  const hasConversations = (conversations ?? []).length > 0;

  if (!hasPending && !hasConversations) {
    return (
      <View style={styles.center}>
        <Text style={styles.emptyText}>{t('messagerie.empty')}</Text>
      </View>
    );
  }

  const sourceLabel = (source: string | null) => {
    if (source === 'discovery') return t('messagerie.viaDiscovery');
    if (source === 'transport') return t('messagerie.viaTransport');
    return t('messagerie.viaProfile');
  };

  return (
    <FlatList
      data={conversations ?? []}
      keyExtractor={(item) => item.id}
      ListHeaderComponent={hasPending ? (
        <View style={styles.requestsSection}>
          <Text style={styles.sectionTitle}>{t('messagerie.requests')}</Text>
          {(pendingRequests ?? []).map((req) => (
            <Pressable
              key={req.id}
              style={styles.requestCard}
              onPress={() => router.push(`/(auth)/profile/${req.request_sender_id}`)}
            >
              <UserAvatar name={req.sender_name} avatarUrl={req.sender_avatar} size={44} />
              <View style={styles.requestInfo}>
                <Text style={styles.requestName} numberOfLines={1}>{req.sender_name}</Text>
                <Text style={styles.requestSource}>{sourceLabel(req.initiated_from)}</Text>
                {req.request_message && (
                  <Text style={styles.requestMessage} numberOfLines={2}>{req.request_message}</Text>
                )}
              </View>
              <View style={styles.requestActions}>
                <Pressable
                  style={[styles.acceptBtn, loadingRequestId === req.id && styles.btnDisabled]}
                  onPress={(e) => { e.stopPropagation(); handleAccept(req.id); }}
                  disabled={loadingRequestId === req.id}
                >
                  <Check size={18} color={colors.textPrimary} strokeWidth={3} />
                </Pressable>
                <Pressable
                  style={[styles.declineBtn, loadingRequestId === req.id && styles.btnDisabled]}
                  onPress={(e) => { e.stopPropagation(); handleDecline(req.id); }}
                  disabled={loadingRequestId === req.id}
                >
                  <X size={18} color={colors.textPrimary} strokeWidth={3} />
                </Pressable>
              </View>
            </Pressable>
          ))}
        </View>
      ) : null}
      renderItem={({ item }) => {
        const isUnread = isConversationUnread(item.id, item.last_message_at, item.last_message_sender_id, currentUserId);
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
  emptyText: { color: colors.textSecondary, fontSize: fontSizes.md },
  sectionTitle: {
    color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: 'bold',
    letterSpacing: 0.8, textTransform: 'uppercase', marginBottom: spacing.sm,
  },
  requestsSection: { marginBottom: spacing.lg },
  requestCard: {
    flexDirection: 'row', alignItems: 'center',
    backgroundColor: colors.surface, borderRadius: radius.md,
    padding: spacing.sm, marginBottom: spacing.xs, gap: spacing.sm,
  },
  requestInfo: { flex: 1, gap: 2 },
  requestName: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },
  requestSource: { color: colors.textSecondary, fontSize: fontSizes.xs - 1 },
  requestMessage: { color: colors.textSecondary, fontSize: fontSizes.xs, fontStyle: 'italic', marginTop: 2 },
  requestActions: { flexDirection: 'row', gap: spacing.xs },
  acceptBtn: {
    width: 36, height: 36, borderRadius: 18,
    backgroundColor: colors.success, alignItems: 'center', justifyContent: 'center',
  },
  declineBtn: {
    width: 36, height: 36, borderRadius: 18,
    backgroundColor: colors.error, alignItems: 'center', justifyContent: 'center',
  },
  btnDisabled: { opacity: 0.4 },
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
