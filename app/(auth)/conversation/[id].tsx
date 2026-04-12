import { useState, useEffect, useRef } from 'react';
import { View, Text, TextInput, Pressable, FlatList, Modal, StyleSheet, Alert, KeyboardAvoidingView, Platform } from 'react-native';
import { useLocalSearchParams } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import * as Burnt from 'burnt';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { messageService, type PrivateMessage } from '@/services/message-service';
import { supabase } from '@/services/supabase';

export default function ConversationScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const [message, setMessage] = useState('');
  const [isSending, setIsSending] = useState(false);
  const [selectedMessage, setSelectedMessage] = useState<PrivateMessage | null>(null);
  const [editContent, setEditContent] = useState('');
  const [isEditMode, setIsEditMode] = useState(false);
  const flatListRef = useRef<FlatList<PrivateMessage>>(null);
  const insets = useSafeAreaInsets();

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
      const errMsg = err instanceof Error ? err.message : t('auth.unknownError');
      if (errMsg.includes('Operation not permitted')) {
        Burnt.toast({ title: t('messagerie.rateLimited') });
      } else {
        Alert.alert(t('auth.error'), errMsg);
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
    } catch {
      Alert.alert(t('auth.error'), t('auth.unknownError'));
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
    <KeyboardAvoidingView style={styles.container} behavior={Platform.OS === 'ios' ? 'padding' : undefined} keyboardVerticalOffset={90}>
      {isLoading ? (
        <View style={styles.center}>
          <Text style={styles.loadingText}>...</Text>
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
          renderItem={({ item }) => (
            <Pressable
              style={[styles.bubble, isOwnMessage(item) ? styles.bubbleOwn : styles.bubbleOther]}
              onLongPress={() => handleLongPress(item)}
            >
              <Text style={styles.bubbleText}>{item.content}</Text>
              <View style={styles.bubbleFooter}>
                <Text style={styles.bubbleTime}>{dayjs(item.created_at).format('HH:mm')}</Text>
                {item.edited_at && <Text style={styles.editedTag}>{t('messagerie.edited')}</Text>}
              </View>
            </Pressable>
          )}
          contentContainerStyle={styles.messageList}
          onContentSizeChange={() => flatListRef.current?.scrollToEnd({ animated: false })}
        />
      )}

      <View style={[styles.inputRow, { paddingBottom: Math.max(insets.bottom, spacing.md) }]}>
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

const styles = StyleSheet.create({
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
  sendDisabled: { opacity: 0.4 },
  sendText: { color: colors.textPrimary, fontSize: 18, fontWeight: 'bold' },
  menuBackdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.5)', justifyContent: 'flex-end' },
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
