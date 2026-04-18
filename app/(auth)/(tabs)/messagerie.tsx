import { View, Text, FlatList, Pressable, ScrollView, StyleSheet, Alert } from 'react-native';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import relativeTime from 'dayjs/plugin/relativeTime';
import 'dayjs/locale/fr';
import * as Burnt from 'burnt';
import { Check, X, Car } from 'lucide-react-native';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { LogoSpinner } from '@/components/logo-spinner';
import { conversationService, type Conversation, type PendingRequest } from '@/services/conversation-service';
import { transportService } from '@/services/transport-service';
import { UserAvatar } from '@/components/user-avatar';
import { useMessageStore } from '@/store/message-store';
import { supabase } from '@/services/supabase';
import { useState } from 'react';

dayjs.extend(relativeTime);

type Tab = 'messages' | 'requests';

export default function MessagerieScreen() {
  const { t, i18n } = useTranslation();
  const router = useRouter();
  const { tab } = useLocalSearchParams<{ tab?: string }>();
  const queryClient = useQueryClient();
  const [activeTab, setActiveTab] = useState<Tab>(tab === 'requests' ? 'requests' : 'messages');
  const [loadingRequestId, setLoadingRequestId] = useState<string | null>(null);
  const [expandedMessageId, setExpandedMessageId] = useState<string | null>(null);
  const [hidingConversationId, setHidingConversationId] = useState<string | null>(null);

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

  const { data: seatRequests } = useQuery({
    queryKey: ['seat-requests-received'],
    queryFn: async () => {
      const userId = (await supabase.auth.getUser()).data.user?.id;
      if (!userId) return [];
      const { data } = await supabase
        .from('seat_requests' as 'participations')
        .select('id, activity_id, requester_id, driver_id, status, created_at')
        .eq('driver_id' as 'user_id', userId)
        .eq('status' as 'user_id', 'pending')
        .order('created_at', { ascending: false }) as unknown as { data: { id: string; activity_id: string; requester_id: string; status: string; created_at: string }[] | null };
      if (!data || data.length === 0) return [];
      const requesterIds = data.map((r) => r.requester_id);
      const { data: profiles } = await supabase.from('public_profiles').select('id, display_name, avatar_url').in('id', requesterIds);
      const profileMap = new Map((profiles ?? []).map((p) => [p.id, p]));
      return data.map((r) => ({ ...r, requester_name: profileMap.get(r.requester_id)?.display_name ?? '?', requester_avatar: profileMap.get(r.requester_id)?.avatar_url ?? null }));
    },
  });

  const handleAccept = async (requestId: string) => {
    setLoadingRequestId(requestId);
    try {
      await conversationService.acceptRequest(requestId);
      await queryClient.invalidateQueries({ queryKey: ['pending-requests'] });
      await queryClient.invalidateQueries({ queryKey: ['conversations'] });
      Burnt.toast({ title: t('messagerie.requestAccepted'), preset: 'done' });
      router.push(`/(auth)/conversation/${requestId}`);
    } catch {
      Burnt.toast({ title: t('auth.unknownError') });
    } finally {
      setLoadingRequestId(null);
    }
  };

  const handleAcceptSeat = async (requestId: string) => {
    setLoadingRequestId(requestId);
    try {
      await transportService.acceptSeatRequest(requestId);
      await queryClient.invalidateQueries({ queryKey: ['seat-requests-received'] });
      await queryClient.invalidateQueries({ queryKey: ['transport'] });
      await queryClient.invalidateQueries({ queryKey: ['conversations'] });
      await queryClient.invalidateQueries({ queryKey: ['conversations-badge'] });
      Burnt.toast({ title: t('transport.seatAccepted'), preset: 'done' });
    } catch {
      Burnt.toast({ title: t('auth.unknownError') });
    } finally {
      setLoadingRequestId(null);
    }
  };

  const handleDeclineSeat = async (requestId: string) => {
    setLoadingRequestId(requestId);
    try {
      await transportService.declineSeatRequest(requestId);
      await queryClient.invalidateQueries({ queryKey: ['seat-requests-received'] });
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

  const handleHideConversation = (conversationId: string, name: string) => {
    Alert.alert(
      t('messagerie.hideTitle'),
      t('messagerie.hideMessage', { name }),
      [
        { text: t('activity.no'), style: 'cancel' },
        {
          text: t('messagerie.hideConfirm'),
          style: 'destructive',
          onPress: async () => {
            try {
              await conversationService.hideConversation(conversationId);
              await queryClient.invalidateQueries({ queryKey: ['conversations'] });
            } catch {
              Burnt.toast({ title: t('auth.unknownError') });
            }
          },
        },
      ]
    );
  };

  const pendingCount = (pendingRequests ?? []).length + (seatRequests ?? []).length;

  const sourceLabel = (source: string | null) => {
    if (source === 'discovery') return t('messagerie.viaDiscovery');
    if (source === 'transport') return t('messagerie.viaTransport');
    return t('messagerie.viaProfile');
  };

  if (isLoading) {
    return (
      <View style={styles.center}>
        <LogoSpinner size={48} />
      </View>
    );
  }

  return (
    <View style={styles.container}>
      {/* Tab bar */}
      <View style={styles.tabBar}>
        <Pressable
          style={[styles.tab, activeTab === 'messages' && styles.tabActive]}
          onPress={() => setActiveTab('messages')}
        >
          <Text style={[styles.tabText, activeTab === 'messages' && styles.tabTextActive]}>
            {t('messagerie.messagesTab')}
          </Text>
        </Pressable>
        <Pressable
          style={[styles.tab, activeTab === 'requests' && styles.tabActive]}
          onPress={() => setActiveTab('requests')}
        >
          <Text style={[styles.tabText, activeTab === 'requests' && styles.tabTextActive]}>
            {t('messagerie.requestsTab')}
          </Text>
          {pendingCount > 0 && (
            <View style={styles.badge}>
              <Text style={styles.badgeText}>{pendingCount}</Text>
            </View>
          )}
        </Pressable>
      </View>

      {/* Messages tab */}
      {activeTab === 'messages' && (
        (!conversations || conversations.length === 0) ? (
          <View style={styles.center}>
            <Text style={styles.emptyText}>{t('messagerie.empty')}</Text>
          </View>
        ) : (
          <FlatList
            data={conversations}
            keyExtractor={(item) => item.id}
            renderItem={({ item }) => {
              const isUnread = isConversationUnread(item.id, item.last_message_at, item.last_message_sender_id, currentUserId);
              return (
                <Pressable
                  style={styles.card}
                  onPress={() => router.push(`/(auth)/conversation/${item.id}`)}
                  onLongPress={() => handleHideConversation(item.id, item.other_user_name)}
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
          />
        )
      )}

      {/* Requests tab */}
      {activeTab === 'requests' && (
        pendingCount === 0 ? (
          <View style={styles.center}>
            <Text style={styles.emptyText}>{t('messagerie.noRequests')}</Text>
          </View>
        ) : (
          <ScrollView contentContainerStyle={styles.list}>
            {/* Seat requests */}
            {(seatRequests ?? []).map((sr) => (
              <View key={sr.id} style={styles.requestCard}>
                <Car size={28} color={colors.cta} strokeWidth={2} />
                <View style={styles.requestInfo}>
                  <Text style={styles.requestName} numberOfLines={1}>{(sr as { requester_name: string }).requester_name}</Text>
                  <Text style={styles.requestSource}>{t('messagerie.viaTransport')}</Text>
                </View>
                <View style={styles.requestActions}>
                  <Pressable
                    style={[styles.acceptBtn, loadingRequestId === sr.id && styles.btnDisabled]}
                    onPress={() => handleAcceptSeat(sr.id)}
                    disabled={loadingRequestId === sr.id}
                  >
                    <Check size={18} color={colors.textPrimary} strokeWidth={3} />
                  </Pressable>
                  <Pressable
                    style={[styles.declineBtn, loadingRequestId === sr.id && styles.btnDisabled]}
                    onPress={() => handleDeclineSeat(sr.id)}
                    disabled={loadingRequestId === sr.id}
                  >
                    <X size={18} color={colors.textPrimary} strokeWidth={3} />
                  </Pressable>
                </View>
              </View>
            ))}

            {/* Contact requests */}
            {(pendingRequests ?? []).map((req) => (
              <Pressable
                key={req.id}
                style={styles.requestCard}
                onPress={() => router.push(`/(auth)/profile/${req.request_sender_id}`)}
              >
                <UserAvatar name={req.sender_name} avatarUrl={req.sender_avatar} size={48} />
                <View style={styles.requestInfo}>
                  <Text style={styles.requestName} numberOfLines={1}>{req.sender_name}</Text>
                  <Text style={styles.requestSource}>{sourceLabel(req.initiated_from)}</Text>
                  {req.request_message && (
                    <Pressable onPress={(e) => { e.stopPropagation(); setExpandedMessageId(expandedMessageId === req.id ? null : req.id); }}>
                      <Text style={styles.requestMessage} numberOfLines={expandedMessageId === req.id ? undefined : 2}>
                        {req.request_message}
                      </Text>
                    </Pressable>
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
          </ScrollView>
        )
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  list: { padding: spacing.md },
  center: { flex: 1, backgroundColor: colors.background, alignItems: 'center', justifyContent: 'center' },
  emptyText: { color: colors.textSecondary, fontSize: fontSizes.md },
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
  tabActive: {
    backgroundColor: colors.cta,
  },
  tabText: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
    fontWeight: '600',
  },
  tabTextActive: {
    color: colors.textPrimary,
  },
  badge: {
    minWidth: 20, height: 20, borderRadius: 10,
    backgroundColor: colors.error,
    alignItems: 'center', justifyContent: 'center',
    paddingHorizontal: 6,
  },
  badgeText: { color: colors.textPrimary, fontSize: fontSizes.xs - 1, fontWeight: 'bold' },
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
  requestCard: {
    flexDirection: 'row', alignItems: 'center',
    backgroundColor: colors.surface, borderRadius: radius.md,
    padding: spacing.sm, marginBottom: spacing.sm, gap: spacing.sm,
  },
  requestInfo: { flex: 1, gap: 2 },
  requestName: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },
  requestSource: { color: colors.textSecondary, fontSize: fontSizes.xs - 1 },
  requestMessage: { color: colors.textSecondary, fontSize: fontSizes.xs, fontStyle: 'italic', marginTop: 2 },
  requestActions: { flexDirection: 'row', gap: spacing.xs },
  acceptBtn: {
    width: 40, height: 40, borderRadius: 20,
    backgroundColor: colors.success, alignItems: 'center', justifyContent: 'center',
  },
  declineBtn: {
    width: 40, height: 40, borderRadius: 20,
    backgroundColor: colors.error, alignItems: 'center', justifyContent: 'center',
  },
  btnDisabled: { opacity: 0.4 },
});
