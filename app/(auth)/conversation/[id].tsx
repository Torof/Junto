import { useState, useEffect, useRef, useMemo } from 'react';
import { View, Text, TextInput, Pressable, FlatList, Modal, StyleSheet, Alert, KeyboardAvoidingView, Platform } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { ExternalLink, Paperclip, Route as RouteIcon, X as XIcon } from 'lucide-react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import * as Burnt from 'burnt';
import * as DocumentPicker from 'expo-document-picker';
import { File } from 'expo-file-system';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { messageService, type PrivateMessage } from '@/services/message-service';
import { useMessageStore } from '@/store/message-store';
import { supabase } from '@/services/supabase';
import { getFriendlyError } from '@/utils/friendly-error';
import { parseGpxToGeoJson, GpxParseError } from '@/utils/parse-gpx';
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
  const [tracePreview, setTracePreview] = useState<{ name: string; coords: [number, number][] } | null>(null);
  const [isAttaching, setIsAttaching] = useState(false);

  // Mark conversation as read when opened
  useEffect(() => {
    if (id) markConversationRead(id);
  }, [id, markConversationRead]);

  const { data: currentUser } = useQuery({
    queryKey: ['currentUser-id'],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id,
  });

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
        const errMsg = err instanceof Error ? err.message : '';
        if (errMsg.includes('Operation not permitted')) {
          Burnt.toast({ title: t('messagerie.rateLimited') });
        } else {
          Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
        }
      }
    } finally {
      setIsAttaching(false);
    }
  };

  const handleSend = async () => {
    if (!message.trim() || isSending || !id) return;

    setIsSending(true);
    try {
      await messageService.send(id, message.trim());
      setMessage('');
      await queryClient.invalidateQueries({ queryKey: ['messages', id] });
      await queryClient.invalidateQueries({ queryKey: ['conversations'] });
      setTimeout(() => flatListRef.current?.scrollToEnd({ animated: true }), 200);
    } catch (err) {
      const errMsg = err instanceof Error ? err.message : '';
      if (errMsg.includes('Operation not permitted')) {
        Burnt.toast({ title: t('messagerie.rateLimited') });
      } else {
        Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
      }
    } finally {
      setIsSending(false);
    }
  };

  const handleLongPress = (msg: PrivateMessage) => {
    if (msg.sender_id !== currentUser) return;
    setSelectedMessage(msg);
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
    <KeyboardAvoidingView style={styles.container} behavior={Platform.OS === 'ios' ? 'padding' : 'height'}>
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
            return (
              <Pressable
                style={[styles.bubble, isOwnMessage(item) ? styles.bubbleOwn : styles.bubbleOther]}
                onLongPress={() => handleLongPress(item)}
              >
                <Text style={styles.bubbleText}>{item.content}</Text>
                {isTrace && (
                  <Pressable
                    style={styles.activityLink}
                    onPress={() => {
                      const geo = item.metadata!.trace_geojson!;
                      const coords = geo.coordinates.map((c) => [c[0]!, c[1]!] as [number, number]);
                      setTracePreview({ name: item.metadata!.name ?? 'trace.gpx', coords });
                    }}
                    hitSlop={4}
                  >
                    <RouteIcon size={12} color={isOwnMessage(item) ? colors.textPrimary : colors.cta} strokeWidth={2.4} />
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
                    <ExternalLink size={12} color={isOwnMessage(item) ? colors.textPrimary : colors.cta} strokeWidth={2.4} />
                    <Text style={[styles.activityLinkText, !isOwnMessage(item) && styles.activityLinkTextOther]}>
                      {t('messagerie.viewActivity')}
                    </Text>
                  </Pressable>
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

      <View style={[styles.inputRow, { paddingBottom: Math.max(insets.bottom, spacing.md) }]}>
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
              </>
            );
          })()}
        </View>
      </Modal>
      {/* Message action sheet */}
      <Modal visible={selectedMessage !== null && !isEditMode} animationType="slide" transparent>
        <Pressable style={styles.menuBackdrop} onPress={() => setSelectedMessage(null)}>
          <Pressable style={styles.menuSheet} onPress={() => {}}>
            <View style={styles.menuHandle} />
            <Pressable style={styles.menuItem} onPress={handleEdit}>
              <Text style={styles.menuText}>{t('messagerie.editMessage')}</Text>
            </Pressable>
            <Pressable style={styles.menuItem} onPress={handleDelete}>
              <Text style={styles.menuTextDanger}>{t('messagerie.deleteMessage')}</Text>
            </Pressable>
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
    maxWidth: '80%', borderRadius: radius.md,
    padding: spacing.sm, paddingHorizontal: spacing.md,
    marginBottom: spacing.sm,
  },
  bubbleOwn: { backgroundColor: colors.cta, alignSelf: 'flex-end' },
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
    color: colors.textPrimary,
    fontSize: fontSizes.xs,
    fontWeight: '700',
    letterSpacing: 0.3,
  },
  activityLinkTextOther: {
    color: colors.cta,
  },
  bubbleText: { color: colors.textPrimary, fontSize: fontSizes.sm },
  bubbleFooter: { flexDirection: 'row', justifyContent: 'flex-end', gap: spacing.xs, marginTop: 2 },
  bubbleTime: { color: colors.textSecondary, fontSize: fontSizes.xs - 2 },
  editedTag: { color: colors.textSecondary, fontSize: fontSizes.xs - 2, fontStyle: 'italic' },
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
