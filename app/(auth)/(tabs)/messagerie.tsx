import { View, Text, FlatList, Pressable, ScrollView, StyleSheet, Alert, RefreshControl } from 'react-native';
import { useRouter, useLocalSearchParams, useFocusEffect } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import relativeTime from 'dayjs/plugin/relativeTime';
import 'dayjs/locale/fr';
import * as Burnt from 'burnt';
import { Check, X, Car, Users, Hash } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { LogoSpinner } from '@/components/logo-spinner';
import { conversationService } from '@/services/conversation-service';
import { notificationService } from '@/services/notification-service';
import { NotificationsView } from '@/components/notifications-view';
import { invitationService } from '@/services/invitation-service';
import { participationService } from '@/services/participation-service';
import { transportService } from '@/services/transport-service';
import { getFriendlyError } from '@/utils/friendly-error';
import { UserAvatar } from '@/components/user-avatar';
import { ReliabilityRing } from '@/components/reliability-ring';
import { useSports } from '@/hooks/use-sports';
import { sportCategoryColor } from '@/utils/sport-category-color';
import { getSportIcon } from '@/constants/sport-icons';
import { supabase } from '@/services/supabase';
import { haptic } from '@/lib/haptics';
import { useState, useMemo, useEffect, useCallback } from 'react';

dayjs.extend(relativeTime);

type Tab = 'messages' | 'requests' | 'notifications';
type Segment = 'all' | 'direct' | 'activity' | 'channel';
const SEGMENTS: { key: Segment; label: string; dflt: string }[] = [
  { key: 'all', label: 'messagerie.segAll', dflt: 'Tout' },
  { key: 'direct', label: 'messagerie.segDirect', dflt: 'Directs' },
  { key: 'activity', label: 'messagerie.segActivity', dflt: 'Sorties' },
  { key: 'channel', label: 'messagerie.segChannel', dflt: 'Canaux' },
];

export default function MessagerieScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t, i18n } = useTranslation();
  const router = useRouter();
  const { tab } = useLocalSearchParams<{ tab?: string }>();
  const queryClient = useQueryClient();
  const [activeTab, setActiveTab] = useState<Tab>(
    tab === 'requests' ? 'requests' : tab === 'notifications' ? 'notifications' : 'messages',
  );
  const [segment, setSegment] = useState<Segment>('all');
  const [loadingRequestId, setLoadingRequestId] = useState<string | null>(null);
  const [expandedMessageId, setExpandedMessageId] = useState<string | null>(null);
  const [hidingConversationId, setHidingConversationId] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  // Sport reference (id → key/category) to render the activity square's
  // universe colour + icon, same source the activity cards use.
  const { data: sports } = useSports();
  const sportMap = useMemo(
    () => new Map((sports ?? []).map((s) => [s.id, s])),
    [sports],
  );

  const { data: currentUserId } = useQuery({
    queryKey: ['currentUser-id'],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id,
  });

  const { data: conversations, isLoading } = useQuery({
    queryKey: ['conversations'],
    queryFn: () => conversationService.getAll(),
  });

  const { data: notifUnread } = useQuery({
    queryKey: ['notifications-count'],
    queryFn: () => notificationService.getUnreadCount(),
  });

  const filteredConversations = useMemo(() => {
    const list = conversations ?? [];
    switch (segment) {
      case 'direct': return list.filter((c) => c.type === 'dm' || c.type === 'group');
      case 'activity': return list.filter((c) => c.type === 'activity');
      case 'channel': return list.filter((c) => c.type === 'channel');
      default: return list;
    }
  }, [conversations, segment]);

  // Incoming-message liveness now rides the user:<id> 'inbox' broadcast,
  // subscribed ONCE in the tabs layout (which invalidates ['conversations']).
  // Here we only keep the seat_requests stream for the driver inbox.
  useEffect(() => {
    if (!currentUserId) return;
    const channel = supabase
      .channel(`messagerie-incoming:${currentUserId}`)
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

  // Tab screens never unmount — without a focus refetch, a join request
  // handled elsewhere (activity page, other device) stays as a ghost row
  // until app restart (same pattern as the profil tab fix).
  useFocusEffect(
    useCallback(() => {
      void queryClient.invalidateQueries({ queryKey: ['join-requests-received'] });
      void queryClient.invalidateQueries({ queryKey: ['pending-requests'] });
      void queryClient.invalidateQueries({ queryKey: ['seat-requests-received'] });
      void queryClient.invalidateQueries({ queryKey: ['invitations-received'] });
    }, [queryClient]),
  );

  const { data: pendingRequests } = useQuery({
    queryKey: ['pending-requests'],
    queryFn: () => conversationService.getPendingReceived(),
  });

  // Invitation reception (Brique 4b) — my `invited` participations, mirror of
  // the join requests. Accept = participant (pre-approved), decline = silent.
  const { data: invitations } = useQuery({
    queryKey: ['invitations-received'],
    queryFn: () => invitationService.getMyInvitations(),
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
      // The row may simply be stale (already handled from the activity
      // page) — refresh so the ghost disappears instead of erroring again.
      await queryClient.invalidateQueries({ queryKey: ['join-requests-received'] });
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
      await queryClient.invalidateQueries({ queryKey: ['join-requests-received'] });
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

  const handleAcceptInvitation = async (activityId: string) => {
    haptic.success();
    setLoadingRequestId(activityId);
    try {
      await invitationService.accept(activityId);
      await queryClient.invalidateQueries({ queryKey: ['invitations-received'] });
      await queryClient.invalidateQueries({ queryKey: ['conversations'] });
      await queryClient.invalidateQueries({ queryKey: ['participants'] });
      Burnt.toast({ title: t('messagerie.invitationAccepted'), preset: 'done' });
      router.push(`/(auth)/activity/${activityId}`);
    } catch (err) {
      Burnt.toast({ title: getFriendlyError(err, 'generic') });
    } finally {
      setLoadingRequestId(null);
    }
  };

  const handleDeclineInvitation = async (activityId: string) => {
    setLoadingRequestId(activityId);
    try {
      await invitationService.decline(activityId);
      await queryClient.invalidateQueries({ queryKey: ['invitations-received'] });
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
    await queryClient.invalidateQueries({ queryKey: ['join-requests-received'] });
    await queryClient.invalidateQueries({ queryKey: ['invitations-received'] });
    setRefreshing(false);
  };

  const pendingCount = (pendingRequests ?? []).length + (seatRequests ?? []).length + (joinRequests ?? []).length + (invitations ?? []).length;

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
        <Pressable
          style={[styles.tab, activeTab === 'notifications' && styles.tabActive]}
          onPress={() => setActiveTab('notifications')}
        >
          <Text style={[styles.tabText, activeTab === 'notifications' && styles.tabTextActive]}>
            {t('messagerie.notificationsTab', { defaultValue: 'Notifications' })}
          </Text>
          {(notifUnread ?? 0) > 0 && (
            <View style={styles.badge}>
              <Text style={styles.badgeText}>{notifUnread! > 99 ? '99+' : notifUnread}</Text>
            </View>
          )}
        </Pressable>
        <View style={{ flex: 1 }} />
        <Pressable onPress={() => router.push('/(auth)/create-group')} hitSlop={8} style={styles.newGroupBtn}>
          <Users size={20} color={colors.textPrimary} strokeWidth={2.2} />
        </Pressable>
      </View>

      {/* Messages tab */}
      {activeTab === 'messages' && (
        (!conversations || conversations.length === 0) ? (
          <View style={styles.center}>
            <Text style={styles.emptyText}>{t('messagerie.empty')}</Text>
          </View>
        ) : (
          <>
          <View style={styles.segments}>
            {SEGMENTS.map((seg) => (
              <Pressable key={seg.key} style={[styles.segment, segment === seg.key && styles.segmentActive]} onPress={() => setSegment(seg.key)}>
                <Text style={[styles.segmentText, segment === seg.key && styles.segmentTextActive]}>{t(seg.label, { defaultValue: seg.dflt })}</Text>
              </Pressable>
            ))}
          </View>
          {filteredConversations.length === 0 ? (
            <View style={styles.center}>
              <Text style={styles.emptyText}>{t('messagerie.emptySegment', { defaultValue: 'Rien dans cette catégorie.' })}</Text>
            </View>
          ) : (
          <FlatList
            data={filteredConversations}
            keyExtractor={(item) => item.id}
            renderItem={({ item }) => {
              const isUnread = item.is_unread;
              const time = item.last_message_at
                ? dayjs(item.last_message_at).locale(i18n.language).fromNow(true)
                : null;
              const meta = item.last_message_metadata;
              const preview =
                meta?.type === 'shared_trace' ? t('messagerie.previewTrace')
                : meta?.type === 'shared_activity' ? t('messagerie.previewActivity')
                : (meta?.type === 'seat_accepted' || meta?.type === 'seat_request_pending') ? t('messagerie.previewSeat')
                : item.last_message_content;

              // Leading visual + title + tap target, by conversation type.
              let leading: React.ReactNode;
              let title: string;
              let onPress: () => void;
              let onLongPress: (() => void) | undefined;

              if (item.type === 'activity') {
                const sport = item.sport_id ? sportMap.get(item.sport_id) : undefined;
                leading = (
                  <View style={[styles.leadingSquare, { backgroundColor: sportCategoryColor(sport?.category, colors.cta) }]}>
                    <Text style={styles.squareEmoji}>{sport ? getSportIcon(sport.key) : '📍'}</Text>
                  </View>
                );
                title = item.activity_title ?? t('messagerie.activityThread');
                onPress = () => router.push(`/(auth)/activity/${item.activity_id}`);
              } else if (item.type === 'group') {
                title = item.name ?? t('messagerie.group');
                leading = (
                  <View style={[styles.leadingSquare, styles.groupSquare]}>
                    {item.icon
                      ? <Text style={styles.squareEmoji}>{item.icon}</Text>
                      : <Users size={22} color={colors.textSecondary} strokeWidth={2.2} />}
                  </View>
                );
                onPress = () => router.push(`/(auth)/conversation/${item.id}`);
                onLongPress = () => handleHideConversation(item.id, title);
              } else if (item.type === 'channel') {
                title = item.name ?? t('messagerie.channel', { defaultValue: 'Canal' });
                leading = (
                  <View style={[styles.leadingSquare, styles.groupSquare]}>
                    <Hash size={22} color={colors.textSecondary} strokeWidth={2.2} />
                  </View>
                );
                onPress = () => router.push(`/(auth)/conversation/${item.id}`);
                onLongPress = () => handleHideConversation(item.id, title);
              } else {
                const name = item.other_user_name ?? '?';
                title = name;
                leading = (
                  <Pressable onPress={() => item.other_user_id && router.push(`/(auth)/profile/${item.other_user_id}`)} hitSlop={4}>
                    <ReliabilityRing tier={item.other_user_reliability_tier} size={40} strokeWidth={2.5} showLabel={false}>
                      <UserAvatar name={name} avatarUrl={item.other_user_avatar} size={40} />
                    </ReliabilityRing>
                  </Pressable>
                );
                onPress = () => router.push(`/(auth)/conversation/${item.id}`);
                onLongPress = () => handleHideConversation(item.id, name);
              }

              return (
                <Pressable
                  style={[styles.row, isUnread && styles.rowUnread]}
                  onPress={onPress}
                  onLongPress={onLongPress}
                >
                  <View style={styles.leadingBox}>{leading}</View>
                  <View style={styles.rowContent}>
                    <View style={styles.rowHeader}>
                      <Text style={[styles.name, isUnread && styles.nameUnread]} numberOfLines={1}>{title}</Text>
                      {isUnread && <View style={styles.unreadDot} />}
                      {time && <Text style={styles.time}>{time}</Text>}
                    </View>
                    {preview && (
                      <Text style={[styles.preview, isUnread && styles.previewUnread]} numberOfLines={1}>{preview}</Text>
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
          )}
          </>
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
            {(joinRequests ?? []).length > 0 && (
              <Text style={styles.sectionHeader}>{t('messagerie.sectionJoin')}</Text>
            )}
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
            {(seatRequests ?? []).length > 0 && (
              <Text style={styles.sectionHeader}>{t('messagerie.sectionSeat')}</Text>
            )}
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
            {(pendingRequests ?? []).length > 0 && (
              <Text style={styles.sectionHeader}>{t('messagerie.sectionContact')}</Text>
            )}
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

            {/* Invitations — mirror of join requests (X invites you). */}
            {(invitations ?? []).length > 0 && (
              <Text style={styles.sectionHeader}>{t('messagerie.sectionInvitations')}</Text>
            )}
            {(invitations ?? []).map((inv) => {
              const sport = inv.sport_id ? sportMap.get(inv.sport_id) : undefined;
              return (
                <Pressable
                  key={inv.activity_id}
                  style={styles.requestRow}
                  onPress={() => router.push(`/(auth)/activity/${inv.activity_id}`)}
                >
                  <UserAvatar name={inv.inviter_name ?? '?'} avatarUrl={inv.inviter_avatar} size={44} />
                  <View style={styles.requestInfo}>
                    <Text style={styles.requestActivityTitle} numberOfLines={1}>
                      {sport ? `${getSportIcon(sport.key)} ` : ''}{inv.activity_title}
                    </Text>
                    <Text style={styles.requestSource} numberOfLines={1}>
                      {t('messagerie.invitedBy', { name: inv.inviter_name ?? '?' })}
                    </Text>
                    {inv.invite_message && (
                      <Text style={styles.requestMessage} numberOfLines={2}>{inv.invite_message}</Text>
                    )}
                  </View>
                  <View style={styles.requestActions}>
                    <Pressable
                      style={[styles.acceptBtn, loadingRequestId === inv.activity_id && styles.btnDisabled]}
                      onPress={(e) => { e.stopPropagation(); handleAcceptInvitation(inv.activity_id); }}
                      disabled={loadingRequestId === inv.activity_id}
                    >
                      <Check size={18} color="#FFFFFF" strokeWidth={3} />
                    </Pressable>
                    <Pressable
                      style={[styles.declineBtn, loadingRequestId === inv.activity_id && styles.btnDisabled]}
                      onPress={(e) => { e.stopPropagation(); handleDeclineInvitation(inv.activity_id); }}
                      disabled={loadingRequestId === inv.activity_id}
                    >
                      <X size={18} color="#FFFFFF" strokeWidth={3} />
                    </Pressable>
                  </View>
                </Pressable>
              );
            })}
          </ScrollView>
        )
      )}

      {activeTab === 'notifications' && <NotificationsView />}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  list: { paddingBottom: spacing.md },
  segments: { flexDirection: 'row', gap: spacing.xs, paddingHorizontal: spacing.md, paddingVertical: spacing.sm, borderBottomWidth: 1, borderBottomColor: colors.borderMuted },
  segment: { paddingHorizontal: spacing.md, paddingVertical: spacing.xs + 3, borderRadius: radius.full, backgroundColor: colors.surfaceAlt },
  segmentActive: { backgroundColor: colors.cta },
  segmentText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '700' },
  segmentTextActive: { color: '#FFFFFF' },
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
  tabActive: { borderBottomColor: colors.cta },
  tabText: { color: colors.textSecondary, fontSize: fontSizes.md, fontWeight: '600' },
  tabTextActive: { color: colors.textPrimary, fontWeight: '700' },
  badge: {
    minWidth: 16, height: 16, borderRadius: radius.sm,
    backgroundColor: colors.cta,
    alignItems: 'center', justifyContent: 'center',
    paddingHorizontal: 4,
  },
  badgeText: { color: '#FFFFFF', fontSize: 10, fontWeight: '700' },
  newGroupBtn: { paddingVertical: spacing.sm, paddingHorizontal: spacing.xs },

  // Conversation row — flat list-item with leading unread bar
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: spacing.sm + 2,
    paddingHorizontal: spacing.sm + 2,
    marginHorizontal: spacing.sm,
    gap: spacing.sm + 2,
    borderRadius: 16,
  },
  // Unread — floats as a soft card so the "new" block reads at a glance.
  rowUnread: { backgroundColor: colors.surface, ...shadows.card },
  unreadDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: colors.cta,
    alignSelf: 'center',
  },
  // Leading visual — fixed box so the DM reliability ring and the
  // activity/group squares all align on the same left rail.
  leadingBox: { width: 52, alignItems: 'center', justifyContent: 'center' },
  leadingSquare: {
    width: 46, height: 46, borderRadius: 15,
    alignItems: 'center', justifyContent: 'center',
  },
  groupSquare: { backgroundColor: colors.surfaceAlt },
  squareEmoji: { fontSize: 22 },
  rowContent: { flex: 1, minWidth: 0 },
  rowHeader: {
    flexDirection: 'row',
    alignItems: 'baseline',
    gap: spacing.sm,
  },
  name: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '600', letterSpacing: -0.2 },
  nameUnread: { fontWeight: '800' },
  time: { color: colors.textMuted, fontSize: fontSizes.xs, fontWeight: '600' },
  preview: { color: colors.textSecondary, fontSize: fontSizes.sm, marginTop: 2 },
  previewUnread: { color: colors.textPrimary },

  // Section header — brutalist uppercase label above each request kind.
  sectionHeader: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '700',
    textTransform: 'uppercase',
    letterSpacing: 0.5,
    paddingHorizontal: spacing.md,
    paddingTop: spacing.md,
    paddingBottom: spacing.xs,
  },
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
