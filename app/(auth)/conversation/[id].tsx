import { useState, useEffect, useRef } from 'react';
import { View, Text, TextInput, Pressable, FlatList, StyleSheet, Alert, KeyboardAvoidingView, Platform } from 'react-native';
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
            <View style={[styles.bubble, isOwnMessage(item) ? styles.bubbleOwn : styles.bubbleOther]}>
              <Text style={styles.bubbleText}>{item.content}</Text>
              <View style={styles.bubbleFooter}>
                <Text style={styles.bubbleTime}>{dayjs(item.created_at).format('HH:mm')}</Text>
                {item.edited_at && <Text style={styles.editedTag}>{t('messagerie.edited')}</Text>}
              </View>
            </View>
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
});
