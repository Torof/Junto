import { useState, useEffect, useRef, useMemo, useLayoutEffect } from 'react';
import { View, Text, TextInput, Pressable, FlatList, Modal, StyleSheet, Alert, Platform, Share, ScrollView } from 'react-native';
import { useLocalSearchParams, useRouter, useNavigation } from 'expo-router';
import { ExternalLink, MapPin, Route as RouteIcon, X as XIcon, Download, Plus, Check, CornerUpLeft, MoreHorizontal, Send, Users } from 'lucide-react-native';
import { UserAvatar } from '@/components/user-avatar';
import { userService } from '@/services/user-service';
import { conversationService } from '@/services/conversation-service';
import { haptic } from '@/lib/haptics';
import Animated, { useSharedValue, useAnimatedStyle, withSpring, runOnJS } from 'react-native-reanimated';
import { GestureDetector, Gesture } from 'react-native-gesture-handler';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import * as Burnt from 'burnt';
import * as DocumentPicker from 'expo-document-picker';
import * as Sharing from 'expo-sharing';
import { File, Paths } from 'expo-file-system';
import { getContentUriAsync } from 'expo-file-system/legacy';
import { useColors } from '@/hooks/use-theme';
import { useKeyboardDockPadding } from '@/hooks/use-keyboard-dock-padding';
import { useCreateGpxTrace } from '@/hooks/use-gpx-traces';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { messageService, type PrivateMessage } from '@/services/message-service';
import { transportService } from '@/services/transport-service';
import type { GeoJsonLineString } from '@/services/activity-service';
import { useMessageStore } from '@/store/message-store';
import { supabase } from '@/services/supabase';
import { getFriendlyError } from '@/utils/friendly-error';
import { parseGpxToGeoJson, GpxParseError } from '@/utils/parse-gpx';
import { geoJsonLineStringToGpx } from '@/utils/geojson-to-gpx';
import { useCreateStore } from '@/store/create-store';
import { LogoSpinner } from '@/components/logo-spinner';
import { JuntoMapView } from '@/components/map-view';
import { ActivityUnavailable } from '@/components/activity-unavailable';
import { PickActivitySheet } from '@/components/pick-activity-sheet';
import { groupService } from '@/services/group-service';
import { GroupManageSheet } from '@/components/group-manage-sheet';
import { channelService } from '@/services/channel-service';
import { useSports } from '@/hooks/use-sports';
import { MessageCircleOff, Hash, Lock, Pencil, LogOut as LogOutIcon, UserMinus } from 'lucide-react-native';

export default function ConversationScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { id } = useLocalSearchParams<{ id: string }>();
  const { t } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const [message, setMessage] = useState('');
  const [isSending, setIsSending] = useState(false);
  const [selectedMessage, setSelectedMessage] = useState<PrivateMessage | null>(null);
  const [editContent, setEditContent] = useState('');
  const [isEditMode, setIsEditMode] = useState(false);
  // The message being edited — kept separate from selectedMessage, which the
  // long-press sheet clears when edit mode opens.
  const [editingMessage, setEditingMessage] = useState<PrivateMessage | null>(null);
  const [isSavingEdit, setIsSavingEdit] = useState(false);
  const flatListRef = useRef<FlatList<PrivateMessage>>(null);
  const insets = useSafeAreaInsets();
  const dockPadding = useKeyboardDockPadding(insets.bottom + spacing.sm);
  const { markConversationRead } = useMessageStore();
  const [tracePreview, setTracePreview] = useState<{ name: string; coords: [number, number][]; geo: GeoJsonLineString } | null>(null);
  const createGpxTrace = useCreateGpxTrace();
  const [isAttaching, setIsAttaching] = useState(false);
  const [attachMenuOpen, setAttachMenuOpen] = useState(false);
  const [pickActivityOpen, setPickActivityOpen] = useState(false);
  const [showGroupManage, setShowGroupManage] = useState(false);
  const [replyingTo, setReplyingTo] = useState<PrivateMessage | null>(null);
  const [showHeaderMenu, setShowHeaderMenu] = useState(false);
  const navigation = useNavigation();

  // Mark conversation as read when opened — local store (legacy surfaces) +
  // server last_read_at (drives the unified hub / tab badge is_unread, 00368).
  useEffect(() => {
    if (!id) return;
    markConversationRead(id);
    conversationService.markRead(id)
      .then(() => {
        void queryClient.invalidateQueries({ queryKey: ['conversations'] });
        void queryClient.invalidateQueries({ queryKey: ['conversations-badge'] });
      })
      .catch(() => {});
  }, [id, markConversationRead, queryClient]);

  const { data: currentUser } = useQuery({
    queryKey: ['currentUser-id'],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id,
  });

  // Other party of this DM — used by the header (avatar + name, tap
  // to profile) so the conversation has context instead of an empty
  // top bar.
  // Conversation context for the header. `exists` distinguishes an
  // inaccessible/deleted thread (→ unavailable screen) from a thread whose
  // other party deleted their account (profile null, but still readable).
  const { data: convMeta, isLoading: convLoading } = useQuery({
    queryKey: ['conversation-other-user', id, currentUser ?? null],
    queryFn: async () => {
      if (!id || !currentUser) return null;
      // Curated read (00351) — the conversations table has no direct client
      // SELECT anymore; the RPC returns the peer of MY conversation only.
      const { data } = await supabase.rpc('get_conversation_peer', {
        p_conversation_id: id,
      });
      const row = (data ?? [])[0];
      if (!row) return { exists: false, profile: null };
      const profile = row.display_name != null
        ? { id: row.other_id, display_name: row.display_name, avatar_url: row.avatar_url }
        : null;
      return { exists: true, profile };
    },
    enabled: !!id && !!currentUser,
    staleTime: 60_000,
  });
  const otherUser = convMeta?.profile ?? null;

  // Group thread (Brique 4d) — only probed once convMeta resolves to "not a DM"
  // (get_conversation_peer returns nothing for group/activity conversations).
  const { data: groupInfo, isError: groupError } = useQuery({
    queryKey: ['group-info', id],
    queryFn: () => groupService.getInfo(id!),
    enabled: !!id && convMeta?.exists === false,
    staleTime: 60_000,
  });
  const isGroup = !!groupInfo;
  // Per-sender identity for group bubbles (DM threads use the single peer).
  const groupMemberById = useMemo(
    () => new Map((groupInfo?.members ?? []).map((m) => [m.id, m])),
    [groupInfo],
  );

  // Channel thread — probed like the group thread once it's not a DM.
  const { data: channelInfo } = useQuery({
    queryKey: ['channel-info', id],
    queryFn: () => channelService.get(id!),
    enabled: !!id && convMeta?.exists === false,
    staleTime: 30_000,
  });
  const isChannel = !!channelInfo;
  const { data: sportsList } = useSports();
  const sportIdByKey = useMemo(() => new Map((sportsList ?? []).map((s) => [s.key, s.id])), [sportsList]);
  const channelIsMember = channelInfo?.is_member === true;
  const channelIsCreator = channelInfo?.is_creator === true;
  const channelClosed = channelInfo?.is_closed === true;
  const [showChannelManage, setShowChannelManage] = useState(false);
  const [channelRename, setChannelRename] = useState('');

  const invalidateChannel = async () => {
    await queryClient.invalidateQueries({ queryKey: ['channel-info', id] });
    await queryClient.invalidateQueries({ queryKey: ['messages', id] });
    await queryClient.invalidateQueries({ queryKey: ['conversations'] });
    await queryClient.invalidateQueries({ queryKey: ['channels'] });
  };
  const handleJoinChannel = async () => {
    try { await channelService.join(id!); await invalidateChannel(); }
    catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
  };
  const handleLeaveChannel = async () => {
    try {
      await channelService.leave(id!);
      setShowChannelManage(false);
      await queryClient.invalidateQueries({ queryKey: ['conversations'] });
      await queryClient.invalidateQueries({ queryKey: ['channels'] });
      router.back();
    } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
  };
  const handleRenameChannel = async () => {
    const n = channelRename.trim();
    if (!n) return;
    try {
      await channelService.rename(id!, n);
      setChannelRename('');
      await invalidateChannel();
      Burnt.toast({ title: t('channels.renamed', { defaultValue: 'Canal renommé' }), preset: 'done' });
    } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
  };
  const handleCloseChannel = async () => {
    try {
      await channelService.close(id!);
      setShowChannelManage(false);
      await invalidateChannel();
      Burnt.toast({ title: t('channels.closedDone', { defaultValue: 'Canal fermé' }) });
    } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
  };
  const handleRemoveMember = async (userId: string) => {
    try {
      await channelService.removeMember(id!, userId);
      await queryClient.invalidateQueries({ queryKey: ['channel-members', id] });
      await queryClient.invalidateQueries({ queryKey: ['channel-info', id] });
      await queryClient.invalidateQueries({ queryKey: ['messages', id] });
    } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
  };
  const { data: channelMembers } = useQuery({
    queryKey: ['channel-members', id],
    queryFn: () => channelService.members(id!),
    enabled: !!id && isChannel && channelIsCreator && showChannelManage,
    staleTime: 15_000,
  });

  useLayoutEffect(() => {
    navigation.setOptions({
      headerTitle: () => (
        isChannel && channelInfo ? (
          <Pressable style={styles.headerRow} onPress={() => setShowChannelManage(true)} hitSlop={6}>
            <View style={styles.headerGroupIcon}>
              <Hash size={16} color={colors.textPrimary} strokeWidth={2.2} />
            </View>
            <View style={{ minWidth: 0 }}>
              <Text style={styles.headerName} numberOfLines={1}>{channelInfo.name}</Text>
              <Text style={styles.headerGroupSub}>
                {t('group.memberCount', { defaultValue: '{{count}} membres', count: channelInfo.member_count })}
                {channelInfo.is_closed ? ` · ${t('channels.closed', { defaultValue: 'fermé' })}` : ''}
              </Text>
            </View>
          </Pressable>
        ) : isGroup && groupInfo ? (
          <Pressable style={styles.headerRow} onPress={() => setShowGroupManage(true)} hitSlop={6}>
            <View style={styles.headerGroupIcon}>
              {groupInfo.icon
                ? <Text style={{ fontSize: 16 }}>{groupInfo.icon}</Text>
                : <Users size={16} color={colors.textPrimary} strokeWidth={2.2} />}
            </View>
            <View style={{ minWidth: 0 }}>
              <Text style={styles.headerName} numberOfLines={1}>{groupInfo.name}</Text>
              <Text style={styles.headerGroupSub}>{t('group.memberCount', { defaultValue: '{{count}} membres', count: groupInfo.members.length })}</Text>
            </View>
          </Pressable>
        ) : otherUser?.id ? (
          <Pressable
            style={styles.headerRow}
            onPress={() => router.push(`/(auth)/profile/${otherUser.id}`)}
            hitSlop={6}
          >
            <UserAvatar name={otherUser.display_name ?? '?'} avatarUrl={otherUser.avatar_url} size={28} />
            <Text style={styles.headerName} numberOfLines={1}>
              {otherUser.display_name ?? '?'}
            </Text>
          </Pressable>
        ) : null
      ),
      headerRight: () => (
        (otherUser || isGroup) ? (
          <Pressable
            onPress={() => setShowHeaderMenu(true)}
            hitSlop={10}
            style={{ paddingHorizontal: spacing.sm }}
          >
            <MoreHorizontal size={22} color={colors.textPrimary} strokeWidth={2.2} />
          </Pressable>
        ) : null
      ),
    });
  }, [navigation, otherUser, isGroup, groupInfo, isChannel, channelInfo, router, styles, colors, t]);

  const handleBlockUser = () => {
    const otherId = otherUser?.id;
    if (!otherId) return;
    setShowHeaderMenu(false);
    Alert.alert(
      t('publicProfile.blockConfirmTitle'),
      t('publicProfile.blockConfirmMessage'),
      [
        { text: t('activity.no'), style: 'cancel' },
        {
          text: t('activity.yes'),
          style: 'destructive',
          onPress: async () => {
            try {
              await userService.blockUser(otherId);
              await queryClient.invalidateQueries({ queryKey: ['conversations'] });
              await queryClient.invalidateQueries({ queryKey: ['is-blocked', otherId] });
              Burnt.toast({ title: t('publicProfile.blocked') });
              router.back();
            } catch (err) {
              Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
            }
          },
        },
      ],
    );
  };

  const handleHideConversation = () => {
    if (!id) return;
    setShowHeaderMenu(false);
    Alert.alert(
      t('messagerie.hideTitle'),
      t('messagerie.hideMessage', { name: otherUser?.display_name ?? '' }),
      [
        { text: t('activity.no'), style: 'cancel' },
        {
          text: t('messagerie.hideConfirm'),
          style: 'destructive',
          onPress: async () => {
            try {
              await conversationService.hideConversation(id);
              await queryClient.invalidateQueries({ queryKey: ['conversations'] });
              router.back();
            } catch (err) {
              Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
            }
          },
        },
      ],
    );
  };

  const { data: messages, isLoading } = useQuery({
    queryKey: ['messages', id],
    queryFn: () => messageService.getMessages(id ?? ''),
    enabled: !!id,
    // Realtime INSERT subscription below is the primary update path —
    // this is only a safety net for missed events (prod audit D: the
    // 10s poll multiplied into thousands of queries/hour at scale).
    refetchInterval: 60000,
  });

  // Realtime subscription
  useEffect(() => {
    if (!id) return;

    // Unified store (00359): thread liveness is a curated broadcast 'change'
    // on the membership-gated conversation topic (private_messages is retired).
    const channel = supabase
      .channel(`conversation:${id}`, { config: { private: true } })
      .on('broadcast', { event: 'change' }, () => {
        queryClient.invalidateQueries({ queryKey: ['messages', id] });
        queryClient.invalidateQueries({ queryKey: ['conversations'] });
      })
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [id, queryClient]);

  // Seat-request inline actions — when a message is the seed for a
  // pending seat request and the viewer is the driver, we render
  // accept/decline buttons under the bubble so the driver can act
  // without leaving the chat. Status drives whether to show the
  // buttons (still pending) or a transition badge.
  const seatRequestIdsKey = useMemo(() => {
    const ids = (messages ?? [])
      .map((m) => m.metadata?.seat_request_id)
      .filter((v): v is string => typeof v === 'string');
    return Array.from(new Set(ids)).sort().join(',');
  }, [messages]);

  const { data: seatRequestStatuses = [] } = useQuery({
    queryKey: ['conversation-seat-requests', seatRequestIdsKey],
    queryFn: async () => {
      if (!seatRequestIdsKey) return [];
      const ids = seatRequestIdsKey.split(',');
      const { data } = await supabase
        .from('seat_requests')
        .select('id, status')
        .in('id', ids);
      return data ?? [];
    },
    enabled: !!seatRequestIdsKey,
  });

  const seatRequestStatusById = useMemo(() => {
    const map = new Map<string, string>();
    seatRequestStatuses.forEach((r) => map.set(r.id, r.status));
    return map;
  }, [seatRequestStatuses]);

  const [seatActionId, setSeatActionId] = useState<string | null>(null);

  const handleSeatAccept = async (requestId: string) => {
    setSeatActionId(requestId);
    try {
      await transportService.acceptSeatRequest(requestId);
      // Stay in the chat — the accept RPC seeds a "🚗 Place réservée"
      // message that the realtime subscription will surface here.
      // Invalidate everything that the accept could have touched.
      // Some keys (messagerie list, conversations) are local; the rest
      // belong to the activity tab — invalidating them by prefix
      // refreshes any mounted GroupCard / MyOutingCard regardless of
      // activityId. Belt-and-suspenders for cases where the realtime
      // broadcast is lost in flight.
      await queryClient.invalidateQueries({ queryKey: ['messages', id] });
      await queryClient.invalidateQueries({ queryKey: ['conversation-seat-requests', seatRequestIdsKey] });
      await queryClient.invalidateQueries({ queryKey: ['seat-requests-received'] });
      await queryClient.invalidateQueries({ queryKey: ['conversations'] });
      await queryClient.invalidateQueries({ queryKey: ['seat-requests-accepted'] });
      await queryClient.invalidateQueries({ queryKey: ['seat-requests'] });
      await queryClient.invalidateQueries({ queryKey: ['transport'] });
      await queryClient.invalidateQueries({ queryKey: ['transport-summary'] });
      await queryClient.invalidateQueries({ queryKey: ['participation'] });
      Burnt.toast({ title: t('transport.seatAccepted', { defaultValue: 'Place confirmée' }), preset: 'done' });
    } catch {
      Burnt.toast({ title: t('auth.unknownError') });
    } finally {
      setSeatActionId(null);
    }
  };

  const handleSeatDecline = async (requestId: string) => {
    setSeatActionId(requestId);
    try {
      await transportService.declineSeatRequest(requestId);
      await queryClient.invalidateQueries({ queryKey: ['conversation-seat-requests', seatRequestIdsKey] });
      await queryClient.invalidateQueries({ queryKey: ['seat-requests-received'] });
      // Same belt-and-suspenders as accept — decline doesn't touch
      // transport but refreshing the seat-requests query removes the
      // pending row from the requester's "En attente" pill.
      await queryClient.invalidateQueries({ queryKey: ['seat-requests'] });
    } catch {
      Burnt.toast({ title: t('auth.unknownError') });
    } finally {
      setSeatActionId(null);
    }
  };

  const handleDownloadTrace = async () => {
    if (!tracePreview) return;
    try {
      const gpxXml = geoJsonLineStringToGpx(tracePreview.geo, tracePreview.name);
      const safeName = tracePreview.name.replace(/[^a-zA-Z0-9._-]/g, '_').replace(/\.gpx$/i, '') + '.gpx';

      const tmp = new File(Paths.cache, safeName);
      tmp.create({ overwrite: true });
      tmp.write(gpxXml);

      // expo-sharing surfaces an Android save-to-Downloads option directly.
      // iOS still routes through the share sheet — pick "Save to Files".
      if (await Sharing.isAvailableAsync()) {
        await Sharing.shareAsync(tmp.uri, {
          mimeType: 'application/gpx+xml',
          dialogTitle: tracePreview.name,
          UTI: 'com.topografix.gpx',
        });
      } else {
        // Fallback for environments without share extensions.
        const url = Platform.OS === 'android' ? await getContentUriAsync(tmp.uri) : tmp.uri;
        await Share.share({ url, title: tracePreview.name });
      }
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
    }
  };

  const handleSaveToLibrary = () => {
    if (!tracePreview) return;
    const name = tracePreview.name.replace(/\.gpx$/i, '').trim() || 'Trace';
    createGpxTrace.mutate(
      { name, geojson: tracePreview.geo },
      {
        onSuccess: () => Burnt.toast({ title: t('messagerie.traceSaved', { defaultValue: 'Trace enregistrée' }), preset: 'done' }),
        onError: (e) => Alert.alert(getFriendlyError(e)),
      },
    );
  };

  const handleUseInActivity = () => {
    if (!tracePreview) return;
    useCreateStore.getState().resetForm();
    useCreateStore.getState().updateForm({ trace_geojson: tracePreview.geo });
    setTracePreview(null);
    router.push('/(auth)/create/step1');
  };

  const handleLeaveGroup = () => {
    setShowHeaderMenu(false);
    Alert.alert(
      t('group.leaveConfirmTitle', { defaultValue: 'Quitter le groupe ?' }),
      t('group.leaveConfirmMsg', { defaultValue: 'Tu ne verras plus les messages de ce groupe.' }),
      [
        { text: t('activity.no'), style: 'cancel' },
        {
          text: t('group.leave', { defaultValue: 'Quitter' }),
          style: 'destructive',
          onPress: async () => {
            try {
              await groupService.leave(id!);
              await queryClient.invalidateQueries({ queryKey: ['conversations'] });
              router.back();
            } catch (e) {
              Burnt.toast({ title: getFriendlyError(e, 'generic') });
            }
          },
        },
      ],
    );
  };

  const handleShareActivity = async (activityId: string) => {
    if (!id) return;
    try {
      await messageService.shareActivity(id, activityId);
      await queryClient.invalidateQueries({ queryKey: ['messages', id] });
      Burnt.toast({ title: t('messagerie.outingShared', { defaultValue: 'Sortie partagée' }), preset: 'done' });
    } catch (err) {
      Burnt.toast({ title: getFriendlyError(err, 'generic') });
    }
  };

  const handleAttachTrace = () => {
    Alert.alert(
      t('messagerie.tracePrivacyTitle'),
      t('messagerie.tracePrivacyMessage'),
      [
        { text: t('messagerie.cancel'), style: 'cancel' },
        { text: t('messagerie.tracePrivacyContinue'), onPress: pickAndSendTrace },
      ],
    );
  };

  const pickAndSendTrace = async () => {
    if (!id) return;
    try {
      const result = await DocumentPicker.getDocumentAsync({ type: '*/*', copyToCacheDirectory: true });
      if (result.canceled) return;
      const file = result.assets[0];
      if (!file) return;
      if (file.size != null && file.size > 5 * 1024 * 1024) {
        Alert.alert(t('messagerie.traceTooLarge'));
        return;
      }
      setIsAttaching(true);
      const xml = await new File(file.uri).text();
      const geojson = parseGpxToGeoJson(xml);
      await messageService.shareTrace(id, geojson, file.name ?? 'trace.gpx');
      await queryClient.invalidateQueries({ queryKey: ['messages', id] });
      Burnt.toast({ title: t('messagerie.traceSent'), preset: 'done' });
    } catch (err) {
      if (err instanceof GpxParseError) {
        Alert.alert(t('messagerie.traceParseError'), err.message);
      } else {
        Alert.alert(t('auth.error'), getFriendlyError(err, 'sendMessage'));
      }
    } finally {
      setIsAttaching(false);
    }
  };

  const handleSend = async () => {
    if (!message.trim() || isSending || !id) return;

    setIsSending(true);
    try {
      await messageService.send(id, message.trim(), replyingTo?.id ?? null);
      setMessage('');
      setReplyingTo(null);
      await queryClient.invalidateQueries({ queryKey: ['messages', id] });
      await queryClient.invalidateQueries({ queryKey: ['conversations'] });
      setTimeout(() => flatListRef.current?.scrollToEnd({ animated: true }), 200);
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'sendMessage'));
    } finally {
      setIsSending(false);
    }
  };

  // Long-press opens the action sheet for any message — Reply is
  // available on both own + received bubbles; Edit / Delete only on
  // own bubbles. The sheet renders conditionals based on ownership.
  const handleLongPress = (msg: PrivateMessage) => {
    setSelectedMessage(msg);
  };

  const handleReplyTo = () => {
    if (!selectedMessage) return;
    setReplyingTo(selectedMessage);
    setSelectedMessage(null);
  };

  const handleEdit = () => {
    if (!selectedMessage) return;
    setEditingMessage(selectedMessage);
    setEditContent(selectedMessage.content);
    setIsEditMode(true);
    setSelectedMessage(null);
  };

  const handleSaveEdit = async () => {
    if (isSavingEdit || !editingMessage || !editContent.trim()) return;
    setIsSavingEdit(true);
    try {
      await messageService.edit(editingMessage.id, editContent.trim());
      await queryClient.invalidateQueries({ queryKey: ['messages', id] });
      Burnt.toast({ title: t('messagerie.messageEdited'), preset: 'done' });
      setIsEditMode(false);
      setEditContent('');
      setEditingMessage(null);
    } catch (err) {
      // Keep the edit bar open on failure so the user can retry.
      Alert.alert(t('auth.error'), getFriendlyError(err, 'sendMessage'));
    } finally {
      setIsSavingEdit(false);
    }
  };

  const handleDelete = () => {
    if (!selectedMessage) return;
    const msgId = selectedMessage.id;
    setSelectedMessage(null);
    Alert.alert(t('messagerie.deleteConfirm'), '', [
      { text: t('activity.no'), style: 'cancel' },
      {
        text: t('activity.yes'),
        style: 'destructive',
        onPress: async () => {
          try {
            await messageService.deleteMessage(msgId);
            await queryClient.invalidateQueries({ queryKey: ['messages', id] });
            Burnt.toast({ title: t('messagerie.messageDeleted') });
          } catch (err) {
            Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
          }
        },
      },
    ]);
  };

  const isOwnMessage = (msg: PrivateMessage) => msg.sender_id === currentUser;

  // Conversation gone or inaccessible (deleted, or you're no longer a
  // participant) → graceful screen instead of an empty thread the user could
  // type into. A deleted-account other party keeps exists=true, so the thread
  // stays readable.
  // Group probe is still resolving: convMeta says "not a DM" but get_group_info
  // hasn't returned yet (data undefined, no error). Show the spinner rather than
  // flashing the unavailable screen for a real group (audit M5).
  const groupProbePending = convMeta?.exists === false && groupInfo === undefined && !groupError;
  if (convLoading || groupProbePending) {
    return <View style={styles.center}><LogoSpinner /></View>;
  }
  if (convMeta && !convMeta.exists && !isGroup) {
    return (
      <ActivityUnavailable
        fallbackHref="/(auth)/(tabs)/messagerie"
        icon={MessageCircleOff}
        title={t('messagerie.unavailableTitle')}
        body={t('messagerie.unavailableBody')}
        ctaLabel={t('messagerie.unavailableCta')}
      />
    );
  }

  return (
    // No KeyboardAvoidingView — the dock's bottom padding animates with
    // the exact IME inset via useKeyboardDockPadding (reanimated).
    <View style={styles.container}>
      <Animated.View style={[styles.containerInner, dockPadding]}>
      {isLoading ? (
        <View style={styles.center}>
          <LogoSpinner />
        </View>
      ) : !messages || messages.length === 0 ? (
        <View style={styles.center}>
          <Text style={styles.emptyText}>{t('messagerie.noMessages')}</Text>
        </View>
      ) : (
        <FlatList
          ref={flatListRef}
          style={styles.messageListContainer}
          data={messages}
          keyExtractor={(item) => item.id}
          renderItem={({ item, index }) => {
            const seatReqId = item.metadata?.type === 'seat_request_pending' ? item.metadata.seat_request_id ?? null : null;
            const seatReqStatus = seatReqId ? (seatRequestStatusById.get(seatReqId) ?? 'pending') : null;
            // Messenger grammar (same model as the activity wall,
            // 2026-07-10): consecutive messages from one sender form a
            // group — corners tighten inside it, avatar and time only on
            // the last bubble. A day boundary breaks the group.
            const prev = messages[index - 1];
            const next = messages[index + 1];
            const isFirstOfDay = !prev || !dayjs(item.created_at).isSame(dayjs(prev.created_at), 'day');
            const isFirstInGroup = isFirstOfDay || !prev || prev.sender_id !== item.sender_id;
            const isLastInGroup =
              !next ||
              next.sender_id !== item.sender_id ||
              !dayjs(item.created_at).isSame(dayjs(next.created_at), 'day');
            // Group: resolve the bubble's author from members; DM: the peer.
            const own = isOwnMessage(item);
            const senderMember = isGroup && !own ? groupMemberById.get(item.sender_id ?? '') : undefined;
            const bubbleName = isGroup ? (senderMember?.display_name ?? '?') : (otherUser?.display_name ?? null);
            const bubbleAvatar = isGroup ? (senderMember?.avatar_url ?? null) : (otherUser?.avatar_url ?? null);
            const replyToName = item.reply_to && item.reply_to.sender_id !== currentUser
              ? (isGroup ? (groupMemberById.get(item.reply_to.sender_id ?? '')?.display_name ?? '?') : (otherUser?.display_name ?? '?'))
              : null;
            return (
              <MessageBubble
                item={item}
                isOwn={own}
                isFirstInGroup={isFirstInGroup}
                isLastInGroup={isLastInGroup}
                showAuthor={isGroup && !own && isFirstInGroup}
                replyToName={replyToName}
                currentUser={currentUser ?? null}
                otherUserName={bubbleName}
                otherUserAvatarUrl={bubbleAvatar}
                seatReqId={seatReqId}
                seatReqStatus={seatReqStatus}
                seatActionId={seatActionId}
                onLongPress={handleLongPress}
                onReply={setReplyingTo}
                onTracePreview={setTracePreview}
                onActivityNav={(activityId) => router.push(`/(auth)/activity/${activityId}`)}
                onSeatAccept={handleSeatAccept}
                onSeatDecline={handleSeatDecline}
                styles={styles}
                colors={colors}
                t={t}
              />
            );
          }}
          contentContainerStyle={styles.messageList}
          onContentSizeChange={() => flatListRef.current?.scrollToEnd({ animated: false })}
        />
      )}

      {/* Bottom dock — wraps the replying-to preview (when active)
          and the input row. Explicit `alignSelf: 'stretch'` so the
          column always takes full width regardless of any flex
          ancestor's alignItems setting. Without the wrapper the
          preview was occasionally collapsing to the input's content
          width. */}
      <View style={styles.bottomDock}>
        {replyingTo && (
          <View style={styles.replyPreview}>
            <View style={styles.replyPreviewBar} />
            <View style={styles.replyPreviewBody}>
              <Text style={styles.replyPreviewLabel} numberOfLines={1}>
                {replyingTo.sender_id === currentUser
                  ? t('messagerie.replyToSelf', { defaultValue: 'Réponse à toi-même' })
                  : t('messagerie.replyTo', {
                      name: otherUser?.display_name ?? '',
                      defaultValue: `Réponse à ${otherUser?.display_name ?? ''}`,
                    })}
              </Text>
              <Text style={styles.replyPreviewContent} numberOfLines={1}>
                {replyingTo.content}
              </Text>
            </View>
            <Pressable onPress={() => setReplyingTo(null)} hitSlop={8} style={styles.replyPreviewClose}>
              <XIcon size={16} color={colors.textSecondary} strokeWidth={2.4} />
            </Pressable>
          </View>
        )}

        {isChannel && !channelIsMember ? (
          <Pressable style={styles.channelJoinBar} onPress={handleJoinChannel}>
            <Text style={styles.channelJoinText}>{t('channels.joinToPost', { defaultValue: 'Rejoindre pour participer' })}</Text>
          </Pressable>
        ) : isChannel && channelClosed ? (
          <View style={styles.channelClosedBar}>
            <Lock size={14} color={colors.textSecondary} strokeWidth={2.2} />
            <Text style={styles.channelClosedText}>{t('channels.closedReadOnly', { defaultValue: 'Canal fermé — lecture seule' })}</Text>
          </View>
        ) : (
          <View style={styles.inputRow}>
            <Pressable
              style={[styles.attachButton, isAttaching && styles.sendDisabled]}
              onPress={() => setAttachMenuOpen(true)}
              disabled={isAttaching}
              hitSlop={6}
            >
              <Plus size={22} color={colors.textSecondary} strokeWidth={2.2} />
            </Pressable>
            <TextInput
              style={styles.input}
              value={message}
              onChangeText={setMessage}
              placeholder={t('messagerie.placeholder')}
              placeholderTextColor={colors.textSecondary}
              maxLength={2000}
              multiline
            />
            <Pressable
              style={[styles.sendButton, (!message.trim() || isSending) && styles.sendDisabled]}
              onPress={handleSend}
              disabled={!message.trim() || isSending}
            >
              <Send size={16} color="#FFFFFF" strokeWidth={2.4} />
            </Pressable>
          </View>
        )}
      </View>

      {/* Attach menu (Brique 4c) — share an outing or a GPX trace. */}
      <Modal visible={attachMenuOpen} animationType="slide" transparent onRequestClose={() => setAttachMenuOpen(false)}>
        <Pressable style={styles.menuBackdrop} onPress={() => setAttachMenuOpen(false)}>
          <Pressable style={styles.menuSheet} onPress={() => {}}>
            <View style={styles.menuHandle} />
            <Pressable style={styles.menuRow} onPress={() => { setAttachMenuOpen(false); setPickActivityOpen(true); }}>
              <MapPin size={20} color={colors.textPrimary} strokeWidth={2.2} />
              <Text style={styles.menuLabel}>{t('messagerie.shareOutingTitle', { defaultValue: 'Partager une sortie' })}</Text>
            </Pressable>
            <Pressable style={styles.menuRow} onPress={() => { setAttachMenuOpen(false); handleAttachTrace(); }}>
              <RouteIcon size={20} color={colors.textPrimary} strokeWidth={2.2} />
              <Text style={styles.menuLabel}>{t('messagerie.shareTraceTitle', { defaultValue: 'Partager une trace GPX' })}</Text>
            </Pressable>
            {/* Create an outing from the chat. Channels: prefill the sport + post
                the card back into the channel on publish. DM/group: prefill the
                peer(s) as invitees (4e-2). */}
            <Pressable style={styles.menuRow} onPress={() => {
              setAttachMenuOpen(false);
              useCreateStore.getState().resetForm();
              if (isChannel && channelInfo) {
                const sid = sportIdByKey.get(channelInfo.sport_key);
                if (sid) useCreateStore.getState().updateForm({ sport_id: sid });
                useCreateStore.getState().setShareTo(id!);
              } else {
                const invitees = isGroup && groupInfo
                  ? groupInfo.members.map((m) => m.id).filter((mid) => mid !== currentUser)
                  : (convMeta?.profile?.id ? [convMeta.profile.id] : []);
                if (invitees.length) useCreateStore.getState().updateForm({ invitees });
              }
              router.push('/(auth)/create/step1');
            }}>
              <Plus size={20} color={colors.textPrimary} strokeWidth={2.2} />
              <Text style={styles.menuLabel}>
                {isChannel
                  ? t('messagerie.proposeOutingFromChannel', { defaultValue: 'Proposer une sortie' })
                  : t('messagerie.createOutingFromChat', { defaultValue: 'Créer une sortie' })}
              </Text>
            </Pressable>
          </Pressable>
        </Pressable>
      </Modal>

      <PickActivitySheet
        visible={pickActivityOpen}
        onClose={() => setPickActivityOpen(false)}
        onPick={handleShareActivity}
      />

      {id && isGroup && groupInfo && (
        <GroupManageSheet
          visible={showGroupManage}
          conversationId={id}
          group={groupInfo}
          onClose={() => setShowGroupManage(false)}
        />
      )}

      {isChannel && channelInfo && (
        <Modal visible={showChannelManage} transparent animationType="slide" onRequestClose={() => setShowChannelManage(false)}>
          <Pressable style={styles.menuBackdrop} onPress={() => setShowChannelManage(false)}>
            <Pressable style={styles.channelSheet} onPress={(e) => e.stopPropagation()}>
              <Text style={styles.channelSheetTitle}>{channelInfo.name}</Text>
              <Text style={styles.channelSheetSub}>
                {t(`sports.${channelInfo.sport_key}`, { defaultValue: channelInfo.sport_key })} · {channelInfo.base_label} · {channelInfo.radius_km} km · {t('group.memberCount', { defaultValue: '{{count}} membres', count: channelInfo.member_count })}
              </Text>
              {channelInfo.description ? <Text style={styles.channelSheetDesc}>{channelInfo.description}</Text> : null}

              {channelIsCreator && !channelClosed && (
                <>
                  <TextInput
                    style={styles.channelRenameInput}
                    value={channelRename}
                    onChangeText={setChannelRename}
                    placeholder={t('channels.renamePlaceholder', { defaultValue: 'Renommer le canal…' })}
                    placeholderTextColor={colors.textSecondary}
                    maxLength={60}
                  />
                  <Pressable style={styles.channelRowBtn} onPress={handleRenameChannel} disabled={!channelRename.trim()}>
                    <Pencil size={18} color={colors.textPrimary} strokeWidth={2.2} />
                    <Text style={styles.channelRowBtnText}>{t('channels.rename', { defaultValue: 'Renommer' })}</Text>
                  </Pressable>
                  <Pressable style={styles.channelRowBtn} onPress={handleCloseChannel}>
                    <Lock size={18} color={colors.error} strokeWidth={2.2} />
                    <Text style={[styles.channelRowBtnText, { color: colors.error }]}>{t('channels.closeChannel', { defaultValue: 'Fermer le canal' })}</Text>
                  </Pressable>

                  {(channelMembers ?? []).length > 0 && (
                    <>
                      <Text style={styles.channelMembersLabel}>{t('channels.members', { defaultValue: 'Membres' })}</Text>
                      <ScrollView style={styles.channelMembersList}>
                        {(channelMembers ?? []).map((m) => (
                          <View key={m.user_id} style={styles.channelMemberRow}>
                            <UserAvatar name={m.display_name} avatarUrl={m.avatar_url} size={32} />
                            <Text style={styles.channelMemberName} numberOfLines={1}>{m.display_name}</Text>
                            {m.is_creator ? (
                              <Text style={styles.channelMemberTag}>{t('channels.creatorTag', { defaultValue: 'Animateur' })}</Text>
                            ) : (
                              <Pressable onPress={() => handleRemoveMember(m.user_id)} hitSlop={8}>
                                <UserMinus size={18} color={colors.error} strokeWidth={2.2} />
                              </Pressable>
                            )}
                          </View>
                        ))}
                      </ScrollView>
                    </>
                  )}
                </>
              )}
              {channelIsMember && !channelIsCreator && (
                <Pressable style={styles.channelRowBtn} onPress={handleLeaveChannel}>
                  <LogOutIcon size={18} color={colors.error} strokeWidth={2.2} />
                  <Text style={[styles.channelRowBtnText, { color: colors.error }]}>{t('channels.leave', { defaultValue: 'Quitter le canal' })}</Text>
                </Pressable>
              )}
            </Pressable>
          </Pressable>
        </Modal>
      )}

      {/* Trace preview modal */}
      <Modal visible={tracePreview !== null} animationType="slide" onRequestClose={() => setTracePreview(null)}>
        <View style={styles.tracePreviewContainer}>
          {tracePreview && (() => {
            const lngs = tracePreview.coords.map((c) => c[0]);
            const lats = tracePreview.coords.map((c) => c[1]);
            const center: [number, number] = [
              (Math.min(...lngs) + Math.max(...lngs)) / 2,
              (Math.min(...lats) + Math.max(...lats)) / 2,
            ];
            const spread = Math.max(Math.max(...lngs) - Math.min(...lngs), Math.max(...lats) - Math.min(...lats));
            const zoom = spread > 0.5 ? 8 : spread > 0.1 ? 10 : spread > 0.01 ? 12 : 14;
            return (
              <>
                <JuntoMapView center={center} zoom={zoom} routeLine={tracePreview.coords} />
                <View style={styles.tracePreviewHeader}>
                  <Pressable
                    style={styles.tracePreviewClose}
                    onPress={() => setTracePreview(null)}
                    hitSlop={8}
                  >
                    <XIcon size={20} color={colors.textPrimary} strokeWidth={2.4} />
                  </Pressable>
                  <View style={styles.tracePreviewTitleWrap}>
                    <Text style={styles.tracePreviewTitle} numberOfLines={1}>{tracePreview.name}</Text>
                  </View>
                </View>
                <View style={[styles.tracePreviewActions, { paddingBottom: Math.max(insets.bottom, spacing.md) }]}>
                  <View style={styles.traceActionRow}>
                    <Pressable style={styles.traceActionButton} onPress={handleDownloadTrace}>
                      <Download size={16} color={colors.textPrimary} strokeWidth={2.4} />
                      <Text style={styles.traceActionText}>{t('messagerie.traceDownload')}</Text>
                    </Pressable>
                    <Pressable style={[styles.traceActionButton, createGpxTrace.isPending && { opacity: 0.5 }]} onPress={handleSaveToLibrary} disabled={createGpxTrace.isPending}>
                      <RouteIcon size={16} color={colors.textPrimary} strokeWidth={2.4} />
                      <Text style={styles.traceActionText}>{t('messagerie.traceSaveToLibrary', { defaultValue: 'Ma bibliothèque' })}</Text>
                    </Pressable>
                  </View>
                  <Pressable style={[styles.traceActionButton, styles.traceActionButtonPrimary]} onPress={handleUseInActivity}>
                    <Plus size={16} color={colors.textPrimary} strokeWidth={2.4} />
                    <Text style={styles.traceActionText}>{t('messagerie.traceUseInActivity')}</Text>
                  </Pressable>
                </View>
              </>
            );
          })()}
        </View>
      </Modal>
      {/* Header menu — Block / Delete (hide) the conversation. */}
      <Modal visible={showHeaderMenu} animationType="slide" transparent onRequestClose={() => setShowHeaderMenu(false)}>
        <Pressable style={styles.menuBackdrop} onPress={() => setShowHeaderMenu(false)}>
          <Pressable style={styles.menuSheet} onPress={() => {}}>
            <View style={styles.menuHandle} />
            <Pressable style={styles.menuItem} onPress={handleHideConversation}>
              <Text style={styles.menuTextDanger}>
                {t('messagerie.hideConversation', { defaultValue: 'Supprimer la conversation' })}
              </Text>
            </Pressable>
            {isGroup ? (
              <Pressable style={styles.menuItem} onPress={handleLeaveGroup}>
                <Text style={styles.menuTextDanger}>{t('group.leave', { defaultValue: 'Quitter le groupe' })}</Text>
              </Pressable>
            ) : (
              <Pressable style={styles.menuItem} onPress={handleBlockUser}>
                <Text style={styles.menuTextDanger}>
                  {t('messagerie.blockUser', { defaultValue: 'Bloquer le passionné' })}
                </Text>
              </Pressable>
            )}
          </Pressable>
        </Pressable>
      </Modal>

      {/* Message action sheet — Reply is always offered; Edit / Delete
          only when the long-pressed message belongs to the caller. */}
      <Modal visible={selectedMessage !== null && !isEditMode} animationType="slide" transparent>
        <Pressable style={styles.menuBackdrop} onPress={() => setSelectedMessage(null)}>
          <Pressable style={styles.menuSheet} onPress={() => {}}>
            <View style={styles.menuHandle} />
            <Pressable style={styles.menuItem} onPress={handleReplyTo}>
              <Text style={styles.menuText}>{t('messagerie.reply', { defaultValue: 'Répondre' })}</Text>
            </Pressable>
            {selectedMessage && selectedMessage.sender_id === currentUser && (
              <>
                <Pressable style={styles.menuItem} onPress={handleEdit}>
                  <Text style={styles.menuText}>{t('messagerie.editMessage')}</Text>
                </Pressable>
                <Pressable style={styles.menuItem} onPress={handleDelete}>
                  <Text style={styles.menuTextDanger}>{t('messagerie.deleteMessage')}</Text>
                </Pressable>
              </>
            )}
          </Pressable>
        </Pressable>
      </Modal>

      {/* Edit mode */}
      {isEditMode && (
        <View style={[styles.editBar, { paddingBottom: Math.max(insets.bottom, spacing.md) }]}>
          <TextInput
            style={styles.editInput}
            value={editContent}
            onChangeText={setEditContent}
            autoFocus
            multiline
            maxLength={2000}
          />
          <Pressable style={[styles.sendButton, isSavingEdit && { opacity: 0.4 }]} onPress={handleSaveEdit} disabled={isSavingEdit}>
            <Text style={styles.sendText}>✓</Text>
          </Pressable>
          <Pressable onPress={() => { setIsEditMode(false); setEditingMessage(null); setEditContent(''); }}>
            <Text style={styles.cancelText}>✕</Text>
          </Pressable>
        </View>
      )}
      </Animated.View>
    </View>
  );
}

// MessageBubble — extracted so each row can host a Pan gesture for
// swipe-to-reply (WhatsApp/Messenger pattern). Received bubbles
// follow the finger to the right; own bubbles to the left. On
// release past threshold, fires reply with a soft haptic and snaps
// back. Long-press still opens the action sheet via the inner
// Pressable (the Pan only activates after 15px horizontal — taps
// and long-presses go through unimpeded).
type MessageBubbleProps = {
  item: PrivateMessage;
  isOwn: boolean;
  isFirstInGroup: boolean;
  isLastInGroup: boolean;
  showAuthor: boolean;
  replyToName: string | null;
  currentUser: string | null;
  otherUserName: string | null;
  otherUserAvatarUrl: string | null;
  seatReqId: string | null;
  seatReqStatus: string | null;
  seatActionId: string | null;
  onLongPress: (msg: PrivateMessage) => void;
  onReply: (msg: PrivateMessage) => void;
  onTracePreview: (preview: { name: string; coords: [number, number][]; geo: GeoJsonLineString }) => void;
  onActivityNav: (activityId: string) => void;
  onSeatAccept: (id: string) => void;
  onSeatDecline: (id: string) => void;
  styles: ReturnType<typeof createStyles>;
  colors: AppColors;
  t: ReturnType<typeof useTranslation>['t'];
};

function MessageBubble({
  item,
  isOwn,
  isFirstInGroup,
  isLastInGroup,
  showAuthor,
  replyToName,
  currentUser,
  otherUserName,
  otherUserAvatarUrl,
  seatReqId,
  seatReqStatus,
  seatActionId,
  onLongPress,
  onReply,
  onTracePreview,
  onActivityNav,
  onSeatAccept,
  onSeatDecline,
  styles,
  colors,
  t,
}: MessageBubbleProps) {
  const translateX = useSharedValue(0);
  const triggered = useSharedValue(false);
  // Direction: own messages slide LEFT (toward incoming), received
  // messages slide RIGHT — matches WhatsApp's reply gesture grammar.
  const direction = isOwn ? -1 : 1;

  const fireReply = () => {
    haptic.light();
    onReply(item);
  };

  const pan = Gesture.Pan()
    .activeOffsetX(isOwn ? [-15, 9999] : [-9999, 15])
    .failOffsetY([-15, 15])
    .onUpdate((e) => {
      const raw = e.translationX * direction;
      const clamped = Math.max(0, Math.min(raw, 80));
      translateX.value = clamped * direction;
      if (clamped > 60 && !triggered.value) {
        triggered.value = true;
        runOnJS(fireReply)();
      }
    })
    .onEnd(() => {
      translateX.value = withSpring(0);
      triggered.value = false;
    });

  const animatedStyle = useAnimatedStyle(() => ({
    transform: [{ translateX: translateX.value }],
  }));

  const isTrace = item.metadata?.type === 'shared_trace' && item.metadata.trace_geojson;
  // In a 2-party thread, "I received this" ⇔ I'm not the sender (receiver_id
  // died with the unified messages store, 00358).
  const isDriver = !!seatReqId && item.sender_id !== currentUser;
  const isActing = !!seatReqId && seatActionId === seatReqId;

  return (
    <View
      style={[
        styles.messageRow,
        isOwn ? styles.messageRight : styles.messageLeft,
        isFirstInGroup ? styles.firstInGroup : styles.midInGroup,
      ]}
    >
      {/* 1:1 Messenger grammar: the other party's avatar sits OUTSIDE the
          bubble, bottom-aligned on the last bubble of their group; own
          messages carry no avatar (the header owns your identity). */}
      {!isOwn && (
        <View style={styles.avatarSlot}>
          {isLastInGroup && (
            <UserAvatar name={otherUserName ?? '?'} avatarUrl={otherUserAvatarUrl} size={28} />
          )}
        </View>
      )}
      <GestureDetector gesture={pan}>
        <Animated.View style={[animatedStyle, styles.bubbleCol]}>
        <Pressable
          style={[
            styles.bubble,
            isOwn ? styles.bubbleOwn : styles.bubbleOther,
            isOwn
              ? { borderTopRightRadius: isFirstInGroup ? 18 : 5, borderBottomRightRadius: isLastInGroup ? 18 : 5 }
              : { borderTopLeftRadius: isFirstInGroup ? 18 : 5, borderBottomLeftRadius: isLastInGroup ? 18 : 5 },
          ]}
          onLongPress={() => onLongPress(item)}
        >
          {showAuthor && (
            <Text style={styles.bubbleAuthor} numberOfLines={1}>{otherUserName ?? '?'}</Text>
          )}
          {item.reply_to && (
            <View style={[styles.bubbleReplyQuote, isOwn && styles.bubbleReplyQuoteOwn]}>
              <View style={[styles.bubbleReplyBar, isOwn && styles.bubbleReplyBarOwn]} />
              <View style={{ flex: 1 }}>
                <Text style={[styles.bubbleReplyAuthor, isOwn && styles.bubbleReplyAuthorOwn]} numberOfLines={1}>
                  {item.reply_to.sender_id === currentUser
                    ? t('messagerie.you', { defaultValue: 'Toi' })
                    : replyToName ?? '?'}
                </Text>
                <Text style={[styles.bubbleReplyContent, isOwn && styles.bubbleReplyContentOwn]} numberOfLines={2}>
                  {item.reply_to.deleted_at
                    ? t('messagerie.replyDeleted', { defaultValue: 'Message supprimé' })
                    : item.reply_to.content}
                </Text>
              </View>
            </View>
          )}
          <Text style={[styles.bubbleText, isOwn && styles.bubbleTextOwn]}>{item.content}</Text>
          {isTrace && (
            <Pressable
              style={styles.activityLink}
              onPress={() => {
                const geo = item.metadata!.trace_geojson!;
                const coords = geo.coordinates.map((c) => [c[0]!, c[1]!] as [number, number]);
                onTracePreview({ name: item.metadata!.name ?? 'trace.gpx', coords, geo });
              }}
              hitSlop={4}
            >
              <RouteIcon size={12} color={isOwn ? '#FFFFFF' : colors.cta} strokeWidth={2.4} />
              <Text style={[styles.activityLinkText, !isOwn && styles.activityLinkTextOther]}>
                {t('messagerie.viewTrace')}
              </Text>
            </Pressable>
          )}
          {item.metadata?.activity_id && !isTrace && (
            <Pressable
              style={styles.activityLink}
              onPress={() => onActivityNav(item.metadata!.activity_id!)}
              hitSlop={4}
            >
              <ExternalLink size={12} color={isOwn ? '#FFFFFF' : colors.cta} strokeWidth={2.4} />
              <Text style={[styles.activityLinkText, !isOwn && styles.activityLinkTextOther]}>
                {t('messagerie.viewActivity')}
              </Text>
            </Pressable>
          )}
          {seatReqId && seatReqStatus === 'pending' && isDriver && (
            <View style={styles.seatActionRow}>
              <Pressable
                style={[styles.seatAcceptBtn, isActing && styles.seatActionDisabled]}
                onPress={() => onSeatAccept(seatReqId)}
                disabled={isActing}
                hitSlop={8}
              >
                <Check size={14} color={colors.textPrimary} strokeWidth={3} />
                <Text style={styles.seatAcceptText}>
                  {t('messagerie.seatAccept', { defaultValue: 'Accepter' })}
                </Text>
              </Pressable>
              <Pressable
                style={[styles.seatDeclineBtn, isActing && styles.seatActionDisabled]}
                onPress={() => onSeatDecline(seatReqId)}
                disabled={isActing}
                hitSlop={8}
              >
                <Text style={styles.seatDeclineText}>
                  {t('messagerie.seatDecline', { defaultValue: 'Refuser' })}
                </Text>
              </Pressable>
            </View>
          )}
          {seatReqId && seatReqStatus && seatReqStatus !== 'pending' && (
            <View style={[styles.seatStatusBadge, isOwn && styles.seatStatusBadgeOwn]}>
              <Text style={[styles.seatStatusText, isOwn && styles.onAccentMuted]}>
                {t(`messagerie.seatStatus.${seatReqStatus}`, {
                  defaultValue:
                    seatReqStatus === 'accepted' ? 'Place confirmée'
                    : seatReqStatus === 'declined' ? 'Demande refusée'
                    : seatReqStatus === 'cancelled' ? 'Demande annulée'
                    : seatReqStatus === 'expired' ? 'Demande expirée'
                    : seatReqStatus,
                })}
              </Text>
            </View>
          )}
          {(isLastInGroup || item.edited_at) && (
            <View style={styles.bubbleFooter}>
              {item.edited_at && (
                <Text style={[styles.editedTag, isOwn && styles.onAccentMuted]}>{t('messagerie.edited')}</Text>
              )}
              {isLastInGroup && (
                <Text style={[styles.bubbleTime, isOwn && styles.onAccentMuted]}>
                  {dayjs(item.created_at).format('H[h]mm')}
                </Text>
              )}
            </View>
          )}
        </Pressable>
        </Animated.View>
      </GestureDetector>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  // Inner wrapper carries the bottom safe-area padding (matches the
  // activity-wall chat tab's wrapper). Lets the KAV stay clean and
  // ensures the dock sits above the system nav bar.
  containerInner: { flex: 1 },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  loadingText: { color: colors.textSecondary, fontSize: fontSizes.lg },
  emptyText: { color: colors.textSecondary, fontSize: fontSizes.md },
  // FlatList wrapper takes remaining vertical space so the bottom
  // dock (reply preview + input) anchors at the bottom of the
  // visible area. Without flex:1 the list sizes to its content and
  // the dock floats up — which also collapsed the dock's width
  // because nothing was forcing the column to span the screen.
  messageListContainer: { flex: 1 },
  messageList: { padding: spacing.md, paddingBottom: spacing.sm },
  // Messenger grammar — same model as the activity wall (2026-07-10):
  // 18-radius bubbles with group-aware corners (applied inline), solid
  // accent for mine with white text, surface tone for the other party.
  messageRow: { flexDirection: 'row' },
  messageLeft: { justifyContent: 'flex-start' },
  messageRight: { justifyContent: 'flex-end' },
  firstInGroup: { marginTop: spacing.sm + 4 },
  midInGroup: { marginTop: 2 },
  avatarSlot: { width: 34, justifyContent: 'flex-end' },
  bubbleCol: { maxWidth: '78%' },
  bubble: {
    borderRadius: 18,
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.sm + 5,
  },
  bubbleOwn: { backgroundColor: colors.cta, alignSelf: 'flex-end' },
  bubbleOther: { backgroundColor: colors.surface, alignSelf: 'flex-start' },
  onAccentMuted: { color: 'rgba(255,255,255,0.75)' },
  activityLink: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
    marginTop: 6,
    paddingHorizontal: spacing.sm,
    paddingVertical: 5,
    borderRadius: radius.sm,
    backgroundColor: 'rgba(0,0,0,0.18)',
    alignSelf: 'flex-start',
  },
  activityLinkText: {
    color: '#FFFFFF',
    fontSize: fontSizes.xs,
    fontWeight: '700',
    letterSpacing: 0.3,
  },
  activityLinkTextOther: {
    color: colors.cta,
  },
  bubbleText: { color: colors.textPrimary, fontSize: fontSizes.sm + 1, lineHeight: 21 },
  bubbleTextOwn: { color: '#FFFFFF' },
  bubbleAuthor: { color: colors.cta, fontSize: fontSizes.xs, fontWeight: '700', marginBottom: 2 },
  // Seat-request inline action row — sits inside the seed bubble so
  // the driver can accept / decline without leaving the chat. Buttons
  // are pill-shaped, full-width, with action-coloured backgrounds.
  seatActionRow: {
    flexDirection: 'row',
    gap: 8,
    marginTop: 6,
  },
  seatAcceptBtn: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 4,
    paddingVertical: 12,
    borderRadius: radius.sm,
    backgroundColor: colors.success,
  },
  seatAcceptText: {
    color: colors.textPrimary,
    fontSize: fontSizes.xs + 1,
    fontWeight: '700',
  },
  seatDeclineBtn: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 12,
    borderRadius: radius.sm,
    borderWidth: 1,
    borderColor: colors.lineStrong,
    backgroundColor: 'transparent',
  },
  seatDeclineText: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs + 1,
    fontWeight: '600',
  },
  seatActionDisabled: {
    opacity: 0.4,
  },
  seatStatusBadge: {
    alignSelf: 'flex-start',
    marginTop: 6,
    paddingVertical: 3,
    paddingHorizontal: 8,
    borderRadius: 999,
    backgroundColor: colors.line,
  },
  seatStatusText: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '600',
  },
  seatStatusBadgeOwn: {
    backgroundColor: 'rgba(255,255,255,0.22)',
  },
  bubbleFooter: { flexDirection: 'row', justifyContent: 'flex-end', gap: spacing.xs, marginTop: 2 },
  bubbleTime: { color: colors.textSecondary, fontSize: fontSizes.xs - 2 },
  editedTag: { color: colors.textSecondary, fontSize: fontSizes.xs - 2, fontStyle: 'italic' },
  // Header content — avatar + display name, tap to profile.
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  headerName: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    fontWeight: '700',
    letterSpacing: -0.05,
    maxWidth: 200,
  },
  headerGroupIcon: {
    width: 28, height: 28, borderRadius: radius.sm,
    backgroundColor: colors.surfaceAlt, alignItems: 'center', justifyContent: 'center',
  },
  headerGroupSub: { color: colors.textSecondary, fontSize: fontSizes.xs - 1 },

  // Bottom dock — single full-width column wrapping the reply
  // preview (when active) and the input row. Guarantees both rows
  // span the screen even if a flex ancestor uses non-stretch
  // alignment (the wrapper makes our intent explicit).
  bottomDock: {
    alignSelf: 'stretch',
    width: '100%',
  },
  // Quoted-reply preview above the input bar — small bar with the
  // original sender + a snippet of the original content, plus a
  // cancel ✕. Shown while the user is composing a reply.
  replyPreview: {
    alignSelf: 'stretch',
    width: '100%',
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    borderTopWidth: 1,
    borderTopColor: colors.surface,
    backgroundColor: colors.surfaceAlt,
  },
  replyPreviewBar: {
    width: 3,
    alignSelf: 'stretch',
    backgroundColor: colors.cta,
    borderRadius: 2,
  },
  replyPreviewBody: {
    flex: 1,
    gap: 1,
  },
  replyPreviewLabel: {
    color: colors.cta,
    fontSize: fontSizes.xs,
    fontWeight: '700',
  },
  replyPreviewContent: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs + 1,
  },
  replyPreviewClose: {
    width: 28,
    height: 28,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
  },

  // Quoted-reply block inside a message bubble — sits at the top of
  // the bubble showing the snippet of the original. Variants for own
  // (white bubble → dark text) vs other (blue bubble → light text).
  // minWidth pushes the parent bubble wider so a short reply ("ok")
  // doesn't squash the quote into a few pixels — the bubble's
  // maxWidth: '80%' still caps the upper bound.
  bubbleReplyQuote: {
    minWidth: 200,
    flexDirection: 'row',
    gap: 8,
    paddingVertical: 4,
    paddingHorizontal: 6,
    marginBottom: 6,
    borderRadius: radius.sm,
    backgroundColor: 'rgba(0,0,0,0.18)',
  },
  bubbleReplyQuoteOwn: {
    backgroundColor: 'rgba(255,255,255,0.18)',
  },
  bubbleReplyBar: {
    width: 3,
    alignSelf: 'stretch',
    backgroundColor: colors.cta,
    borderRadius: 2,
  },
  bubbleReplyBarOwn: {
    backgroundColor: '#FFFFFF',
  },
  bubbleReplyAuthor: {
    color: colors.cta,
    fontSize: fontSizes.xs,
    fontWeight: '700',
  },
  bubbleReplyAuthorOwn: {
    color: '#FFFFFF',
  },
  bubbleReplyContent: {
    color: colors.textPrimary,
    fontSize: fontSizes.xs + 1,
  },
  bubbleReplyContentOwn: {
    color: 'rgba(255,255,255,0.9)',
  },

  inputRow: {
    alignSelf: 'stretch',
    width: '100%',
    flexDirection: 'row', alignItems: 'flex-end',
    padding: spacing.md, gap: spacing.xs,
    borderTopWidth: 1, borderTopColor: colors.surface,
  },
  channelJoinBar: {
    alignSelf: 'stretch', margin: spacing.md, backgroundColor: colors.cta,
    borderRadius: radius.md, paddingVertical: spacing.sm + 3, alignItems: 'center',
  },
  channelJoinText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '800' },
  channelClosedBar: {
    alignSelf: 'stretch', flexDirection: 'row', alignItems: 'center', justifyContent: 'center',
    gap: spacing.xs, padding: spacing.md, borderTopWidth: 1, borderTopColor: colors.surface,
  },
  channelClosedText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '700' },
  channelSheet: {
    backgroundColor: colors.background, borderTopLeftRadius: radius.xl, borderTopRightRadius: radius.xl,
    padding: spacing.lg, paddingBottom: spacing.xl, gap: spacing.sm,
  },
  channelSheetTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800' },
  channelSheetSub: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600' },
  channelSheetDesc: { color: colors.textPrimary, fontSize: fontSizes.md, lineHeight: 21, marginTop: spacing.xs },
  channelRenameInput: {
    backgroundColor: colors.surface, borderWidth: 1, borderColor: colors.borderMuted, borderRadius: radius.md,
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm + 2, color: colors.textPrimary, fontSize: fontSizes.md,
    marginTop: spacing.sm,
  },
  channelRowBtn: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, paddingVertical: spacing.sm + 2 },
  channelRowBtnText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  channelMembersLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '700', textTransform: 'uppercase', letterSpacing: 0.5, marginTop: spacing.sm },
  channelMembersList: { maxHeight: 240 },
  channelMemberRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, paddingVertical: spacing.xs + 2 },
  channelMemberName: { flex: 1, minWidth: 0, color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '600' },
  channelMemberTag: { color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '700' },
  input: {
    flex: 1, backgroundColor: colors.surface, color: colors.textPrimary,
    borderRadius: 22, paddingHorizontal: spacing.md + 2, paddingVertical: spacing.sm + 2,
    fontSize: fontSizes.sm + 1, maxHeight: 110,
  },
  sendButton: {
    width: 40, height: 40, borderRadius: 20,
    backgroundColor: colors.cta, alignItems: 'center', justifyContent: 'center',
    shadowColor: colors.cta,
    shadowOpacity: 0.35,
    shadowRadius: 8,
    shadowOffset: { width: 0, height: 3 },
    elevation: 3,
  },
  attachButton: {
    width: 44, height: 44, borderRadius: 22,
    backgroundColor: colors.surface, alignItems: 'center', justifyContent: 'center',
  },
  sendDisabled: { opacity: 0.4 },
  tracePreviewContainer: { flex: 1, backgroundColor: colors.background },
  tracePreviewHeader: {
    position: 'absolute', top: 35, left: 20, right: 20,
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm,
    zIndex: 10,
  },
  tracePreviewClose: {
    width: 40, height: 40, borderRadius: 20,
    backgroundColor: colors.background,
    alignItems: 'center', justifyContent: 'center',
  },
  tracePreviewTitleWrap: {
    flex: 1,
    backgroundColor: colors.background + 'E6',
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
    borderRadius: radius.md,
  },
  tracePreviewTitle: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  tracePreviewActions: {
    position: 'absolute', bottom: 0, left: 0, right: 0,
    flexDirection: 'column', gap: spacing.sm,
    paddingHorizontal: spacing.md, paddingTop: spacing.md,
    backgroundColor: colors.background + 'F2',
  },
  traceActionRow: { flexDirection: 'row', gap: spacing.sm },
  traceActionButton: {
    flex: 1,
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center',
    gap: 6,
    backgroundColor: colors.surface,
    borderRadius: radius.full,
    paddingVertical: spacing.md,
  },
  traceActionButtonPrimary: { backgroundColor: colors.cta },
  traceActionText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700' },
  sendText: { color: '#FFFFFF', fontSize: 18, fontWeight: 'bold' },
  menuBackdrop: { flex: 1, backgroundColor: colors.overlay, justifyContent: 'flex-end' },
  menuSheet: { backgroundColor: colors.background, borderTopLeftRadius: radius.lg, borderTopRightRadius: radius.lg, padding: spacing.lg, paddingBottom: spacing.xl + 16 },
  menuHandle: { width: 40, height: 4, borderRadius: 2, backgroundColor: colors.textSecondary, alignSelf: 'center', marginBottom: spacing.lg, opacity: 0.4 },
  menuItem: { paddingVertical: spacing.md },
  menuRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.md, paddingVertical: spacing.md },
  menuLabel: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '600' },
  menuText: { color: colors.textPrimary, fontSize: fontSizes.md },
  menuTextDanger: { color: colors.error, fontSize: fontSizes.md },
  editBar: {
    flexDirection: 'row', alignItems: 'flex-end',
    padding: spacing.md, gap: spacing.xs,
    borderTopWidth: 1, borderTopColor: colors.cta,
    backgroundColor: colors.surface,
  },
  editInput: {
    flex: 1, backgroundColor: colors.background, color: colors.textPrimary,
    borderRadius: radius.md, paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
    fontSize: fontSizes.sm, maxHeight: 100,
  },
  cancelText: { color: colors.textSecondary, fontSize: 18, paddingHorizontal: spacing.sm, paddingVertical: spacing.sm },
});
