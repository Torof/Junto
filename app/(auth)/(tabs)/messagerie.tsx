import { View, Text, FlatList, Pressable, ScrollView, StyleSheet, Alert, RefreshControl } from 'react-native';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import relativeTime from 'dayjs/plugin/relativeTime';
import 'dayjs/locale/fr';
import * as Burnt from 'burnt';
import { Check, X, Car } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { LogoSpinner } from '@/components/logo-spinner';
import { conversationService } from '@/services/conversation-service';
import { participationService } from '@/services/participation-service';
import { transportService } from '@/services/transport-service';
import { getFriendlyError } from '@/utils/friendly-error';
import { UserAvatar } from '@/components/user-avatar';
import { useMessageStore } from '@/store/message-store';
import { supabase } from '@/services/supabase';
import { haptic } from '@/lib/haptics';
import { useState, useMemo, useEffect } from 'react';

dayjs.extend(relativeTime);

type Tab = 'messages' | 'requests';

export default function MessagerieScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t, i18n } = useTranslation();
  const router = useRouter();
  const { tab } = useLocalSearchParams<{ tab?: string }>();
  const queryClient = useQueryClient();
  const [activeTab, setActiveTab] = useState<Tab>(tab === 'requests' ? 'requests' : 'messages');
  const [loadingRequestId, setLoadingRequestId] = useState<string | null>(null);
  const [expandedMessageId, setExpandedMessageId] = useState<string | null>(null);
  const [hidingConversationId, setHidingConversationId] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const { isConversationUnread } = useMessageStore();

  const { data: currentUserId } = useQuery({
    queryKey: ['currentUser-id'],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id,
  });

  const { data: conversations, isLoading } = useQuery({
    queryKey: ['conversations'],
    queryFn: () => conversationService.getAll(),
  });

  // Refresh the conversation list whenever a new private_message arrives for
  // this user — covers seat-accept seeded messages and any other server-side
  // INSERT that bypasses the local invalidation path.
  useEffect(() => {
    if (!currentUserId) return;
    const channel = supabase
      .channel(`messagerie-incoming:${currentUserId}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'private_messages',
          filter: `receiver_id=eq.${currentUserId}`,
        },
        () => {
          queryClient.invalidateQueries({ queryKey: ['conversations'] });
        },
      )
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'seat_requests',
          filter: `driver_id=eq.${currentUserId}`,
        },
        () => {
          queryClient.invalidateQueries({ queryKey: ['seat-requests-received'] });
        },
      )
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
  }, [currentUserId, queryClient]);

  const { data: pendingRequests } = useQuery({
    queryKey: ['pending-requests'],
    queryFn: () => conversationService.getPendingReceived(),
  });

  // Join requests on MY activities (approval / private_link_approval).
  // The activity_participants view is creator-gated server-side, so a
  // bare status filter returns exactly my activities' pending rows —
  // they were invisible everywhere but the buried participants modal
  // (Scott's bug, 2026-07-10: a private-approval request had NO surface).
  const { data: joinRequests } = useQuery({
    queryKey: ['join-requests-received'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('activity_participants' as 'activities_with_coords')
        .select('participation_id, activity_id, user_id, created_at, display_name, avatar_url' as never)
        .eq('status' as never, 'pending')
        .order('created_at' as never, { ascending: false });
      if (error) throw error;
      const rows = (data ?? []) as unknown as { participation_id: string; activity_id: string; user_id: string; created_at: string; display_name: string; avatar_url: string | null }[];
      if (rows.length === 0) return [];
      const activityIds = Array.from(new Set(rows.map((r) => r.activity_id)));
      const { data: activities } = await supabase
        .from('activities')
        .select('id, status, deleted_at, title')
        .in('id', activityIds);
      const live = new Map((activities ?? [])
        .filter((a) => (a.status === 'published' || a.status === 'in_progress') && a.deleted_at === null)
        .map((a) => [a.id, a.title]));
      return rows
        .filter((r) => live.has(r.activity_id))
        .map((r) => ({ ...r, activity_title: live.get(r.activity_id) ?? '' }));
    },
  });

  const { data: seatRequests } = useQuery({
    queryKey: ['seat-requests-received'],
    queryFn: async () => {
      const userId = (await supabase.auth.getUser()).data.user?.id;
      if (!userId) return [];
      const { data } = await supabase
        .from('seat_requests')
        .select('id, activity_id, requester_id, driver_id, status, created_at, pickup_from, message, requested_pickup_at')
        .eq('driver_id', userId)
        .eq('status', 'pending')
        .order('created_at', { ascending: false });
      if (!data || data.length === 0) return [];

      // Defensive: hide pending requests for activities that are no longer
      // active. The server-side trigger flips them to 'expired' on status
      // change, but this guards against any in-flight state. Also fetch
      // each activity's title so the request card can show context
      // (which hike is this request for? — U-3 audit fix).
      const activityIds = Array.from(new Set(data.map((r) => r.activity_id)));
      const { data: activities } = await supabase
        .from('activities')
        .select('id, status, deleted_at, title')
        .in('id', activityIds);
      const activityMap = new Map((activities ?? []).map((a) => [a.id, a]));
      const activeIds = new Set(
        (activities ?? [])
          .filter((a) => (a.status === 'published' || a.status === 'in_progress') && a.deleted_at === null)
          .map((a) => a.id)
      );
      const filtered = data.filter((r) => activeIds.has(r.activity_id));
      if (filtered.length === 0) return [];

      const requesterIds = filtered.map((r) => r.requester_id);
      const { data: profiles } = await supabase.from('public_profiles').select('id, display_name, avatar_url').in('id', requesterIds);
      const profileMap = new Map((profiles ?? []).map((p) => [p.id, p]));
      return filtered.map((r) => ({
        ...r,
        requester_name: profileMap.get(r.requester_id)?.display_name ?? '?',
        requester_avatar: profileMap.get(r.requester_id)?.avatar_url ?? null,
        activity_title: activityMap.get(r.activity_id)?.title ?? null,
      }));
    },
  });

  const handleAccept = async (requestId: string) => {
    haptic.success();
    setLoadingRequestId(requestId);
    try {
      await conversationService.acceptRequest(requestId);
      await queryClient.invalidateQueries({ queryKey: ['pending-requests'] });
      await queryClient.invalidateQueries({ queryKey: ['conversations'] });
      Burnt.toast({ title: t('messagerie.requestAccepted'), preset: 'done' });
      router.push(`/(auth)/conversation/${requestId}`);
    } catch (err) {
      Burnt.toast({ title: getFriendlyError(err, 'generic') });
    } finally {
      setLoadingRequestId(null);
    }
  };

  const handleAcceptJoin = async (participationId: string) => {
    setLoadingRequestId(participationId);
    try {
      await participationService.accept(participationId);
      await queryClient.invalidateQueries({ queryKey: ['join-requests-received'] });
      await queryClient.invalidateQueries({ queryKey: ['participants'] });
      await queryClient.invalidateQueries({ queryKey: ['participants-pending'] });
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
    } finally {
      setLoadingRequestId(null);
    }
  };
  const handleRefuseJoin = async (participationId: string) => {
    setLoadingRequestId(participationId);
    try {
      await participationService.refuse(participationId);
      await queryClient.invalidateQueries({ queryKey: ['join-requests-received'] });
      await queryClient.invalidateQueries({ queryKey: ['participants-pending'] });
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
    } finally {
      setLoadingRequestId(null);
    }
  };

  const handleAcceptSeat = async (requestId: string) => {
    haptic.success();
    setLoadingRequestId(requestId);
    try {
      const conversationId = await transportService.acceptSeatRequest(requestId);
      await queryClient.invalidateQueries({ queryKey: ['seat-requests-received'] });
      await queryClient.invalidateQueries({ queryKey: ['transport'] });
      // Keep a mounted activity-detail / group-card in sync (broad keys cover
      // the relevant activity id we don't have in scope here).
      await queryClient.invalidateQueries({ queryKey: ['seat-requests'] });
      await queryClient.invalidateQueries({ queryKey: ['seat-requests-accepted'] });
      await queryClient.invalidateQueries({ queryKey: ['transport-summary'] });
      await queryClient.invalidateQueries({ queryKey: ['conversations'] });
      await queryClient.invalidateQueries({ queryKey: ['conversations-badge'] });
      Burnt.toast({ title: t('transport.seatAccepted'), preset: 'done' });
      if (conversationId) {
        router.push(`/(auth)/conversation/${conversationId}`);
      }
    } catch (err) {
      Burnt.toast({ title: getFriendlyError(err, 'generic') });
    } finally {
      setLoadingRequestId(null);
    }
  };

  const handleDeclineSeat = async (requestId: string) => {
    setLoadingRequestId(requestId);
    try {
      await transportService.declineSeatRequest(requestId);
      await queryClient.invalidateQueries({ queryKey: ['seat-requests-received'] });
    } catch (err) {
      Burnt.toast({ title: getFriendlyError(err, 'generic') });
    } finally {
      setLoadingRequestId(null);
    }
  };

  const handleDecline = async (requestId: string) => {
    setLoadingRequestId(requestId);
    try {
      await conversationService.declineRequest(requestId);
      await queryClient.invalidateQueries({ queryKey: ['pending-requests'] });
    } catch (err) {
      Burnt.toast({ title: getFriendlyError(err, 'generic') });
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
            } catch (err) {
              Burnt.toast({ title: getFriendlyError(err, 'generic') });
            }
          },
        },
      ]
    );
  };

  const handleRefresh = async () => {
    setRefreshing(true);
    await queryClient.invalidateQueries({ queryKey: ['conversations'] });
    await queryClient.invalidateQueries({ queryKey: ['pending-requests'] });
    await queryClient.invalidateQueries({ queryKey: ['seat-requests-received'] });
    setRefreshing(false);
  };

  const pendingCount = (pendingRequests ?? []).length + (seatRequests ?? []).length + (joinRequests ?? []).length;

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
              const isUnread = isConversationUnread(item.id, item.last_message_at, item.last_message_sender_id, item.last_message_metadata, currentUserId);
              const otherUserId = item.user_1 === currentUserId ? item.user_2 : item.user_1;
              return (
                <Pressable
                  style={[styles.row, isUnread && styles.rowUnread]}
                  onPress={() => router.push(`/(auth)/conversation/${item.id}`)}
                  onLongPress={() => handleHideConversation(item.id, item.other_user_name)}
                >
                  <Pressable
                    onPress={() => router.push(`/(auth)/profile/${otherUserId}`)}
                    hitSlop={4}
                  >
                    <UserAvatar name={item.other_user_name} avatarUrl={item.other_user_avatar} size={44} />
                  </Pressable>
                  <View style={styles.rowContent}>
                    <View style={styles.rowHeader}>
                      <Text style={[styles.name, isUnread && styles.nameUnread]} numberOfLines={1}>{item.other_user_name}</Text>
                      {isUnread && <View style={styles.unreadDot} />}
                      {item.last_message_at && (
                        <Text style={styles.time}>
                          {dayjs(item.last_message_at).locale(i18n.language).fromNow(true)}
                        </Text>
                      )}
                    </View>
                    {item.last_message_content && (
                      <Text style={[styles.preview, isUnread && styles.previewUnread]} numberOfLines={1}>{item.last_message_content}</Text>
                    )}
                  </View>
                </Pressable>
              );
            }}
            contentContainerStyle={styles.list}
            refreshControl={
              <RefreshControl
                refreshing={refreshing}
                onRefresh={handleRefresh}
                tintColor={colors.cta}
                colors={[colors.cta]}
              />
            }
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
            {/* Join requests — same row grammar as the other request kinds. */}
            {(joinRequests ?? []).map((jr) => (
              <Pressable
                key={jr.participation_id}
                style={styles.requestRow}
                onPress={() => router.push(`/(auth)/activity/${jr.activity_id}`)}
              >
                <UserAvatar name={jr.display_name} avatarUrl={jr.avatar_url} size={44} />
                <View style={styles.requestInfo}>
                  <Text style={styles.requestActivityTitle} numberOfLines={1}>{jr.activity_title}</Text>
                  <Text style={styles.requestName} numberOfLines={1}>{jr.display_name}</Text>
                  <Text style={styles.requestSource}>{t('messagerie.joinRequest', { defaultValue: 'Demande à rejoindre la sortie' })}</Text>
                </View>
                <View style={styles.requestActions}>
                  <Pressable
                    style={[styles.acceptBtn, loadingRequestId === jr.participation_id && styles.btnDisabled]}
                    onPress={(e) => { e.stopPropagation(); handleAcceptJoin(jr.participation_id); }}
                    disabled={loadingRequestId === jr.participation_id}
                  >
                    <Check size={18} color="#FFFFFF" strokeWidth={3} />
                  </Pressable>
                  <Pressable
                    style={[styles.declineBtn, loadingRequestId === jr.participation_id && styles.btnDisabled]}
                    onPress={(e) => { e.stopPropagation(); handleRefuseJoin(jr.participation_id); }}
                    disabled={loadingRequestId === jr.participation_id}
                  >
                    <X size={18} color="#FFFFFF" strokeWidth={3} />
                  </Pressable>
                </View>
              </Pressable>
            ))}

            {/* Seat requests */}
            {(seatRequests ?? []).map((sr) => {
              const subtitleParts = [
                sr.pickup_from,
                sr.requested_pickup_at ? dayjs(sr.requested_pickup_at).format('H[h]mm') : null,
              ].filter(Boolean);
              return (
              <Pressable
                key={sr.id}
                style={styles.requestRow}
                onPress={() => router.push(`/(auth)/activity/${sr.activity_id}`)}
              >
                <View style={styles.requestIconCol}>
                  <Car size={24} color={colors.cta} strokeWidth={2.2} />
                </View>
                <View style={styles.requestInfo}>
                  {sr.activity_title && (
                    <Text style={styles.requestActivityTitle} numberOfLines={1}>
                      {sr.activity_title}
                    </Text>
                  )}
                  <Text style={styles.requestName} numberOfLines={1}>
                    {sr.requester_name}{subtitleParts.length > 0 ? ` · ${subtitleParts.join(' · ')}` : ''}
                  </Text>
                  {sr.message ? (
                    <Text style={styles.requestSource} numberOfLines={2}>{sr.message}</Text>
                  ) : (
                    <Text style={styles.requestSource}>{t('messagerie.viaTransport')}</Text>
                  )}
                </View>
                <View style={styles.requestActions}>
                  <Pressable
                    style={[styles.acceptBtn, loadingRequestId === sr.id && styles.btnDisabled]}
                    onPress={(e) => { e.stopPropagation(); handleAcceptSeat(sr.id); }}
                    disabled={loadingRequestId === sr.id}
                  >
                    <Check size={18} color="#FFFFFF" strokeWidth={3} />
                  </Pressable>
                  <Pressable
                    style={[styles.declineBtn, loadingRequestId === sr.id && styles.btnDisabled]}
                    onPress={(e) => { e.stopPropagation(); handleDeclineSeat(sr.id); }}
                    disabled={loadingRequestId === sr.id}
                  >
                    <X size={18} color="#FFFFFF" strokeWidth={3} />
                  </Pressable>
                </View>
              </Pressable>
            );
            })}

            {/* Contact requests */}
            {(pendingRequests ?? []).map((req) => (
              <Pressable
                key={req.id}
                style={styles.requestRow}
                onPress={() => router.push(`/(auth)/profile/${req.request_sender_id}`)}
              >
                <UserAvatar name={req.sender_name} avatarUrl={req.sender_avatar} size={44} />
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
                    <Check size={18} color="#FFFFFF" strokeWidth={3} />
                  </Pressable>
                  <Pressable
                    style={[styles.declineBtn, loadingRequestId === req.id && styles.btnDisabled]}
                    onPress={(e) => { e.stopPropagation(); handleDecline(req.id); }}
                    disabled={loadingRequestId === req.id}
                  >
                    <X size={18} color="#FFFFFF" strokeWidth={3} />
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

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  list: { paddingBottom: spacing.md },
  center: { flex: 1, backgroundColor: colors.background, alignItems: 'center', justifyContent: 'center' },
  emptyText: { color: colors.textSecondary, fontSize: fontSizes.md },

  // Tab bar — underline pattern
  tabBar: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.lg,
    paddingHorizontal: spacing.md,
    paddingTop: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderMuted,
  },
  tab: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    paddingVertical: spacing.sm,
    borderBottomWidth: 2,
    borderBottomColor: 'transparent',
  },
  tabActive: { borderBottomColor: colors.borderStrong },
  tabText: { color: colors.textSecondary, fontSize: fontSizes.md, fontWeight: '500' },
  tabTextActive: { color: colors.textPrimary, fontWeight: '700' },
  badge: {
    minWidth: 16, height: 16, borderRadius: radius.sm,
    backgroundColor: colors.cta,
    alignItems: 'center', justifyContent: 'center',
    paddingHorizontal: 4,
  },
  badgeText: { color: '#FFFFFF', fontSize: 10, fontWeight: '700' },

  // Conversation row — flat list-item with leading unread bar
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: spacing.sm,
    paddingLeft: spacing.md,
    paddingRight: spacing.md,
    gap: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderMuted,
  },
  // Unread — same grammar as the notifications screen: light cta tint + dot.
  rowUnread: { backgroundColor: colors.cta + '12' },
  unreadDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: colors.cta,
    alignSelf: 'center',
  },
  rowContent: { flex: 1, minWidth: 0 },
  rowHeader: {
    flexDirection: 'row',
    alignItems: 'baseline',
    gap: spacing.sm,
  },
  name: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '500' },
  nameUnread: { fontWeight: '700' },
  time: { color: colors.textSecondary, fontSize: fontSizes.xs },
  preview: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: 2 },
  previewUnread: { color: colors.textPrimary },

  // Request row — flat row with avatar/icon + info + accept/decline
  requestRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.md,
    gap: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderMuted,
  },
  requestIconCol: {
    width: 44,
    height: 44,
    alignItems: 'center',
    justifyContent: 'center',
  },
  requestInfo: { flex: 1, minWidth: 0, gap: 2 },
  requestActivityTitle: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700', letterSpacing: -0.05 },
  requestName: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },
  requestSource: { color: colors.textSecondary, fontSize: fontSizes.xs - 1 },
  requestMessage: { color: colors.textSecondary, fontSize: fontSizes.xs, fontStyle: 'italic', marginTop: 2 },
  requestActions: { flexDirection: 'row', gap: spacing.xs + 2 },
  acceptBtn: {
    width: 36, height: 36, borderRadius: radius.sm,
    backgroundColor: colors.success, alignItems: 'center', justifyContent: 'center',
  },
  declineBtn: {
    width: 36, height: 36, borderRadius: radius.sm,
    backgroundColor: colors.error, alignItems: 'center', justifyContent: 'center',
  },
  btnDisabled: { opacity: 0.4 },
});
