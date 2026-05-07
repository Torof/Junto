import { useState, useEffect, useRef, useMemo, useLayoutEffect } from 'react';
import { View, Text, TextInput, Pressable, FlatList, Modal, StyleSheet, Alert, KeyboardAvoidingView, Platform, Share } from 'react-native';
import { useLocalSearchParams, useRouter, useNavigation } from 'expo-router';
import { ExternalLink, Paperclip, Route as RouteIcon, X as XIcon, Download, Plus, Check, CornerUpLeft } from 'lucide-react-native';
import { UserAvatar } from '@/components/user-avatar';
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
  const flatListRef = useRef<FlatList<PrivateMessage>>(null);
  const insets = useSafeAreaInsets();
  const { markConversationRead } = useMessageStore();
  const [tracePreview, setTracePreview] = useState<{ name: string; coords: [number, number][]; geo: GeoJsonLineString } | null>(null);
  const [isAttaching, setIsAttaching] = useState(false);
  const [replyingTo, setReplyingTo] = useState<PrivateMessage | null>(null);
  const navigation = useNavigation();

  // Mark conversation as read when opened
  useEffect(() => {
    if (id) markConversationRead(id);
  }, [id, markConversationRead]);

  const { data: currentUser } = useQuery({
    queryKey: ['currentUser-id'],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id,
  });

  // Other party of this DM — used by the header (avatar + name, tap
  // to profile) so the conversation has context instead of an empty
  // top bar.
  const { data: otherUser } = useQuery({
    queryKey: ['conversation-other-user', id, currentUser ?? null],
    queryFn: async () => {
      if (!id || !currentUser) return null;
      const { data: conv } = await supabase
        .from('conversations')
        .select('user_1, user_2')
        .eq('id', id)
        .maybeSingle();
      if (!conv) return null;
      const otherId = conv.user_1 === currentUser ? conv.user_2 : conv.user_1;
      const { data: profile } = await supabase
        .from('public_profiles')
        .select('id, display_name, avatar_url')
        .eq('id', otherId)
        .maybeSingle();
      return profile;
    },
    enabled: !!id && !!currentUser,
    staleTime: 60_000,
  });

  useLayoutEffect(() => {
    navigation.setOptions({
      headerTitle: () => (
        otherUser ? (
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
    });
  }, [navigation, otherUser, router, styles]);

  const { data: messages, isLoading } = useQuery({
    queryKey: ['messages', id],
    queryFn: () => messageService.getMessages(id ?? ''),
    enabled: !!id,
    refetchInterval: 10000,
  });

  // Realtime subscription
  useEffect(() => {
    if (!id) return;

    const channel = supabase
      .channel(`dm:${id}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'private_messages',
          filter: `conversation_id=eq.${id}`,
        },
        () => {
          queryClient.invalidateQueries({ queryKey: ['messages', id] });
          queryClient.invalidateQueries({ queryKey: ['conversations'] });
        },
      )
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
      await queryClient.invalidateQueries({ queryKey: ['messages', id] });
      await queryClient.invalidateQueries({ queryKey: ['conversation-seat-requests', seatRequestIdsKey] });
      await queryClient.invalidateQueries({ queryKey: ['seat-requests-received'] });
      await queryClient.invalidateQueries({ queryKey: ['conversations'] });
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
      Alert.alert(t('auth.error'), err instanceof Error ? err.message : 'Unknown error');
    }
  };

  const handleUseInActivity = () => {
    if (!tracePreview) return;
    useCreateStore.getState().resetForm();
    useCreateStore.getState().updateForm({ trace_geojson: tracePreview.geo });
    setTracePreview(null);
    router.push('/(auth)/create/step1');
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
    setEditContent(selectedMessage.content);
    setIsEditMode(true);
    setSelectedMessage(null);
  };

  const handleSaveEdit = async () => {
    if (!selectedMessage && !editContent.trim()) return;
    try {
      await messageService.edit(selectedMessage!.id, editContent.trim());
      await queryClient.invalidateQueries({ queryKey: ['messages', id] });
      Burnt.toast({ title: t('messagerie.messageEdited'), preset: 'done' });
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'sendMessage'));
    }
    setIsEditMode(false);
    setEditContent('');
    setSelectedMessage(null);
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
          await messageService.deleteMessage(msgId);
          await queryClient.invalidateQueries({ queryKey: ['messages', id] });
          Burnt.toast({ title: t('messagerie.messageDeleted') });
        },
      },
    ]);
  };

  const isOwnMessage = (msg: PrivateMessage) => msg.sender_id === currentUser;

  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      keyboardVerticalOffset={Platform.OS === 'ios' ? insets.top : 0}
    >
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
          data={messages}
          keyExtractor={(item) => item.id}
          renderItem={({ item }) => {
            const isTrace = item.metadata?.type === 'shared_trace' && item.metadata.trace_geojson;
            const seatReqId = item.metadata?.type === 'seat_request_pending' ? item.metadata.seat_request_id : null;
            const seatReqStatus = seatReqId ? (seatRequestStatusById.get(seatReqId) ?? 'pending') : null;
            // Driver = receiver of the seed (the requester sent it).
            const isDriver = !!seatReqId && item.receiver_id === currentUser;
            const isActing = !!seatReqId && seatActionId === seatReqId;
            return (
              <Pressable
                style={[styles.bubble, isOwnMessage(item) ? styles.bubbleOwn : styles.bubbleOther]}
                onLongPress={() => handleLongPress(item)}
              >
                {item.reply_to && (
                  <View style={[styles.bubbleReplyQuote, isOwnMessage(item) && styles.bubbleReplyQuoteOwn]}>
                    <View style={[styles.bubbleReplyBar, isOwnMessage(item) && styles.bubbleReplyBarOwn]} />
                    <View style={{ flex: 1 }}>
                      <Text style={[styles.bubbleReplyAuthor, isOwnMessage(item) && styles.bubbleReplyAuthorOwn]} numberOfLines={1}>
                        {item.reply_to.sender_id === currentUser
                          ? t('messagerie.you', { defaultValue: 'Toi' })
                          : otherUser?.display_name ?? '?'}
                      </Text>
                      <Text style={[styles.bubbleReplyContent, isOwnMessage(item) && styles.bubbleReplyContentOwn]} numberOfLines={2}>
                        {item.reply_to.deleted_at
                          ? t('messagerie.replyDeleted', { defaultValue: 'Message supprimé' })
                          : item.reply_to.content}
                      </Text>
                    </View>
                  </View>
                )}
                <Text style={[styles.bubbleText, isOwnMessage(item) && styles.bubbleTextOwn]}>{item.content}</Text>
                {isTrace && (
                  <Pressable
                    style={styles.activityLink}
                    onPress={() => {
                      const geo = item.metadata!.trace_geojson!;
                      const coords = geo.coordinates.map((c) => [c[0]!, c[1]!] as [number, number]);
                      setTracePreview({ name: item.metadata!.name ?? 'trace.gpx', coords, geo });
                    }}
                    hitSlop={4}
                  >
                    <RouteIcon size={12} color={isOwnMessage(item) ? colors.pinBorder : colors.cta} strokeWidth={2.4} />
                    <Text style={[styles.activityLinkText, !isOwnMessage(item) && styles.activityLinkTextOther]}>
                      {t('messagerie.viewTrace')}
                    </Text>
                  </Pressable>
                )}
                {item.metadata?.activity_id && !isTrace && (
                  <Pressable
                    style={styles.activityLink}
                    onPress={() => router.push(`/(auth)/activity/${item.metadata!.activity_id}`)}
                    hitSlop={4}
                  >
                    <ExternalLink size={12} color={isOwnMessage(item) ? colors.pinBorder : colors.cta} strokeWidth={2.4} />
                    <Text style={[styles.activityLinkText, !isOwnMessage(item) && styles.activityLinkTextOther]}>
                      {t('messagerie.viewActivity')}
                    </Text>
                  </Pressable>
                )}
                {/* Seat-request inline actions (driver-side) — accept /
                    decline straight from the chat surface so the
                    discussion can lead to a decision in place. */}
                {seatReqId && seatReqStatus === 'pending' && isDriver && (
                  <View style={styles.seatActionRow}>
                    <Pressable
                      style={[styles.seatAcceptBtn, isActing && styles.seatActionDisabled]}
                      onPress={() => handleSeatAccept(seatReqId)}
                      disabled={isActing}
                      hitSlop={4}
                    >
                      <Check size={14} color={colors.textPrimary} strokeWidth={3} />
                      <Text style={styles.seatAcceptText}>
                        {t('messagerie.seatAccept', { defaultValue: 'Accepter' })}
                      </Text>
                    </Pressable>
                    <Pressable
                      style={[styles.seatDeclineBtn, isActing && styles.seatActionDisabled]}
                      onPress={() => handleSeatDecline(seatReqId)}
                      disabled={isActing}
                      hitSlop={4}
                    >
                      <Text style={styles.seatDeclineText}>
                        {t('messagerie.seatDecline', { defaultValue: 'Refuser' })}
                      </Text>
                    </Pressable>
                  </View>
                )}
                {seatReqId && seatReqStatus && seatReqStatus !== 'pending' && (
                  <View style={styles.seatStatusBadge}>
                    <Text style={styles.seatStatusText}>
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
                <View style={styles.bubbleFooter}>
                  <Text style={styles.bubbleTime}>{dayjs(item.created_at).format('H[h]mm')}</Text>
                  {item.edited_at && <Text style={styles.editedTag}>{t('messagerie.edited')}</Text>}
                </View>
              </Pressable>
            );
          }}
          contentContainerStyle={styles.messageList}
          onContentSizeChange={() => flatListRef.current?.scrollToEnd({ animated: false })}
        />
      )}

      {/* Replying-to preview — small bar above the input showing the
          quoted message and a cancel ✕. Sender name resolves from the
          long-pressed message: own self if the user is replying to
          their own message, otherSelf's name otherwise. */}
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

      <View style={[styles.inputRow, { paddingBottom: insets.bottom + spacing.sm }]}>
        <Pressable
          style={[styles.attachButton, isAttaching && styles.sendDisabled]}
          onPress={handleAttachTrace}
          disabled={isAttaching}
          hitSlop={6}
        >
          <Paperclip size={20} color={colors.textSecondary} strokeWidth={2.2} />
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
          <Text style={styles.sendText}>↑</Text>
        </Pressable>
      </View>

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
                  <Pressable style={styles.traceActionButton} onPress={handleDownloadTrace}>
                    <Download size={16} color={colors.textPrimary} strokeWidth={2.4} />
                    <Text style={styles.traceActionText}>{t('messagerie.traceDownload')}</Text>
                  </Pressable>
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
          <Pressable style={styles.sendButton} onPress={handleSaveEdit}>
            <Text style={styles.sendText}>✓</Text>
          </Pressable>
          <Pressable onPress={() => { setIsEditMode(false); setSelectedMessage(null); }}>
            <Text style={styles.cancelText}>✕</Text>
          </Pressable>
        </View>
      )}
    </KeyboardAvoidingView>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  loadingText: { color: colors.textSecondary, fontSize: fontSizes.lg },
  emptyText: { color: colors.textSecondary, fontSize: fontSizes.md },
  messageList: { padding: spacing.md, paddingBottom: spacing.sm },
  bubble: {
    maxWidth: '80%',
    // Pillier-style soft corners — closer to WhatsApp / iMessage than
    // the previous medium radius. Symmetric (no tail) for now;
    // asymmetric tails can come later if we want to lean further into
    // the chat-app look.
    borderRadius: 20,
    padding: spacing.sm, paddingHorizontal: spacing.md,
    marginBottom: spacing.sm,
  },
  // Self-bubble is near-white (pinBackground = #F5F5F0 in dark / pure
  // white in light) to match the logo's blue-and-white identity. The
  // received-bubble keeps the surface tone (Junto blue in dark, soft
  // gray in light).
  bubbleOwn: { backgroundColor: colors.pinBackground, alignSelf: 'flex-end' },
  bubbleOther: { backgroundColor: colors.surface, alignSelf: 'flex-start' },
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
    color: colors.pinBorder,
    fontSize: fontSizes.xs,
    fontWeight: '700',
    letterSpacing: 0.3,
  },
  activityLinkTextOther: {
    color: colors.cta,
  },
  bubbleText: { color: colors.textPrimary, fontSize: fontSizes.sm },
  // Dark-always text for own bubbles since the new background is
  // near-white in both themes (textPrimary would disappear in dark
  // mode where it's an off-white).
  bubbleTextOwn: { color: colors.pinBorder },
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
    paddingVertical: 6,
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
    paddingVertical: 6,
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

  // Quoted-reply preview above the input bar — small bar with the
  // original sender + a snippet of the original content, plus a
  // cancel ✕. Shown while the user is composing a reply.
  replyPreview: {
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
  bubbleReplyQuote: {
    flexDirection: 'row',
    gap: 8,
    paddingVertical: 4,
    paddingHorizontal: 6,
    marginBottom: 6,
    borderRadius: radius.sm,
    backgroundColor: 'rgba(0,0,0,0.18)',
  },
  bubbleReplyQuoteOwn: {
    backgroundColor: 'rgba(0,0,0,0.06)',
  },
  bubbleReplyBar: {
    width: 3,
    alignSelf: 'stretch',
    backgroundColor: colors.cta,
    borderRadius: 2,
  },
  bubbleReplyBarOwn: {
    backgroundColor: colors.cta,
  },
  bubbleReplyAuthor: {
    color: colors.cta,
    fontSize: fontSizes.xs,
    fontWeight: '700',
  },
  bubbleReplyAuthorOwn: {
    color: colors.cta,
  },
  bubbleReplyContent: {
    color: colors.textPrimary,
    fontSize: fontSizes.xs + 1,
  },
  bubbleReplyContentOwn: {
    color: colors.pinBorder,
  },

  inputRow: {
    flexDirection: 'row', alignItems: 'flex-end',
    padding: spacing.md, gap: spacing.xs,
    borderTopWidth: 1, borderTopColor: colors.surface,
  },
  input: {
    flex: 1, backgroundColor: colors.surface, color: colors.textPrimary,
    borderRadius: radius.md, paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
    fontSize: fontSizes.sm, maxHeight: 100,
  },
  sendButton: {
    width: 36, height: 36, borderRadius: 18,
    backgroundColor: colors.cta, alignItems: 'center', justifyContent: 'center',
  },
  attachButton: {
    width: 36, height: 36, borderRadius: 18,
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
    flexDirection: 'row', gap: spacing.sm,
    paddingHorizontal: spacing.md, paddingTop: spacing.md,
    backgroundColor: colors.background + 'F2',
  },
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
  sendText: { color: colors.textPrimary, fontSize: 18, fontWeight: 'bold' },
  menuBackdrop: { flex: 1, backgroundColor: colors.overlay, justifyContent: 'flex-end' },
  menuSheet: { backgroundColor: colors.background, borderTopLeftRadius: radius.lg, borderTopRightRadius: radius.lg, padding: spacing.lg, paddingBottom: spacing.xl + 16 },
  menuHandle: { width: 40, height: 4, borderRadius: 2, backgroundColor: colors.textSecondary, alignSelf: 'center', marginBottom: spacing.lg, opacity: 0.4 },
  menuItem: { paddingVertical: spacing.md },
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
