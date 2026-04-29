import { View, Text, Pressable, ScrollView, StyleSheet, Alert, Modal, TextInput } from 'react-native';
import { useLocalSearchParams, useNavigation, useRouter } from 'expo-router';
import { MoreHorizontal } from 'lucide-react-native';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import * as Burnt from 'burnt';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { userService } from '@/services/user-service';
import { ProfileSkeleton } from '@/components/profile-skeleton';
import { badgeService } from '@/services/badge-service';
import { participationService } from '@/services/participation-service';
import { conversationService } from '@/services/conversation-service';
import { getFriendlyError } from '@/utils/friendly-error';
import { useLayoutEffect, useState, useMemo } from 'react';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { ProfileHero } from '@/components/profile-hero';
import { BadgeDisplay } from '@/components/badge-display';
import { ReportModal } from '@/components/report-modal';
import { supabase } from '@/services/supabase';

export default function PublicProfileScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { id, participation: participationId, activityTitle } = useLocalSearchParams<{ id: string; participation?: string; activityTitle?: string }>();
  const { t, i18n } = useTranslation();
  const router = useRouter();
  const navigation = useNavigation();
  const insets = useSafeAreaInsets();
  const [showReport, setShowReport] = useState(false);
  const [showMenu, setShowMenu] = useState(false);
  const [showRequestModal, setShowRequestModal] = useState(false);
  const [requestMessage, setRequestMessage] = useState('');
  const [requestSending, setRequestSending] = useState(false);
  const [requestHandled, setRequestHandled] = useState(false);
  const [requestLoading, setRequestLoading] = useState(false);
  const queryClient = useQueryClient();

  const { data: currentUser } = useQuery({
    queryKey: ['currentUser-id'],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id,
  });

  const isOwnProfile = currentUser === id;

  const { data: profile, isLoading } = useQuery({
    queryKey: ['public-profile', id],
    queryFn: () => userService.getPublicProfile(id ?? ''),
    enabled: !!id,
  });

  const { data: stats } = useQuery({
    queryKey: ['user-stats', id],
    queryFn: () => userService.getPublicStats(id ?? ''),
    enabled: !!id,
  });

  const { data: isBlocked } = useQuery({
    queryKey: ['is-blocked', id],
    queryFn: () => userService.isBlocked(id ?? ''),
    enabled: !!id && !isOwnProfile,
  });

  const { data: reputation } = useQuery({
    queryKey: ['reputation', id],
    queryFn: () => badgeService.getUserReputation(id ?? ''),
    enabled: !!id,
  });

  const { data: trophies } = useQuery({
    queryKey: ['trophies', id],
    queryFn: () => badgeService.getUserTrophies(id ?? ''),
    enabled: !!id,
  });

  const { data: sportLevels } = useQuery({
    queryKey: ['sport-levels', id],
    queryFn: () => badgeService.getUserSportLevels(id ?? ''),
    enabled: !!id,
  });

  const { data: conversationState } = useQuery({
    queryKey: ['conversation-state', id],
    queryFn: () => conversationService.getConversationStateWith(id ?? ''),
    enabled: !!id && !isOwnProfile,
  });

  const existingConversationId = conversationState?.status === 'active' ? conversationState.id : null;
  const requestAlreadySent = conversationState?.status === 'pending_request' || conversationState?.status === 'declined';

  useLayoutEffect(() => {
    navigation.setOptions({
      headerTitle: () => (
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8, paddingLeft: spacing.md }}>
          <Text style={{ color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold' }}>
            {profile?.display_name ?? '...'}
          </Text>
        </View>
      ),
      headerTitleAlign: 'left' as const,
      headerRight: () =>
        isOwnProfile ? null : (
          <Pressable onPress={() => setShowMenu(true)} hitSlop={12} style={{ paddingHorizontal: spacing.md }}>
            <MoreHorizontal size={24} color={colors.textPrimary} strokeWidth={2.2} />
          </Pressable>
        ),
    });
  }, [navigation, isOwnProfile, profile?.display_name, colors]);

  const handleBlock = () => {
    Alert.alert(t('publicProfile.blockConfirmTitle'), t('publicProfile.blockConfirmMessage'), [
      { text: t('activity.no'), style: 'cancel' },
      {
        text: t('activity.yes'),
        style: 'destructive',
        onPress: async () => {
          await userService.blockUser(id ?? '');
          await queryClient.invalidateQueries({ queryKey: ['is-blocked', id] });
          Burnt.toast({ title: t('publicProfile.blocked') });
        },
      },
    ]);
  };

  const handleParticipation = async (action: 'accept' | 'refuse') => {
    if (!participationId) return;
    setRequestLoading(true);
    try {
      if (action === 'accept') {
        await participationService.accept(participationId);
        Burnt.toast({ title: t('toast.participantAccepted'), preset: 'done' });
      } else {
        await participationService.refuse(participationId);
        Burnt.toast({ title: t('toast.participantRefused') });
      }
      await queryClient.invalidateQueries({ queryKey: ['participants-pending'] });
      await queryClient.invalidateQueries({ queryKey: ['participants'] });
      setRequestHandled(true);
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
    } finally {
      setRequestLoading(false);
    }
  };

  const handleUnblock = async () => {
    await userService.unblockUser(id ?? '');
    await queryClient.invalidateQueries({ queryKey: ['is-blocked', id] });
    Burnt.toast({ title: t('publicProfile.unblocked') });
  };

  if (isLoading || !profile) {
    return <ProfileSkeleton />;
  }

  return (
    <View style={{ flex: 1 }}>
    <ScrollView style={styles.container} contentContainerStyle={[styles.content, participationId && !requestHandled && { paddingBottom: 120 }]}>
      <ProfileHero
        displayName={profile.display_name}
        avatarUrl={profile.avatar_url}
        reliabilityPct={stats?.reliability_score ?? null}
        reliabilityTier={stats?.reliability_tier ?? null}
        stats={stats ?? null}
        joinedAt={profile.created_at ?? null}
      />

      <BadgeDisplay
        reputation={reputation ?? []}
        trophies={trophies ?? []}
        sportLevels={sportLevels ?? []}
        completedCount={stats?.completed_activities}
        createdCount={stats?.created_activities}
        showLocked={false}
      />

      {/* Primary action — send message (on other people's profile) */}
      {!isOwnProfile && (
        <View style={styles.actions}>
          {existingConversationId ? (
            <Pressable style={styles.messageButton} onPress={() => router.push(`/(auth)/conversation/${existingConversationId}`)}>
              <Text style={styles.messageText}>{t('publicProfile.sendMessage')}</Text>
            </Pressable>
          ) : requestAlreadySent ? (
            <View style={[styles.messageButton, { opacity: 0.4 }]}>
              <Text style={styles.messageText}>{t('publicProfile.requestPending')}</Text>
            </View>
          ) : (
            <Pressable style={styles.messageButton} onPress={() => {
              setRequestMessage(t('publicProfile.defaultRequestMessage', { name: profile?.display_name ?? '' }));
              setShowRequestModal(true);
            }}>
              <Text style={styles.messageText}>{t('publicProfile.requestContact')}</Text>
            </Pressable>
          )}
        </View>
      )}

      {/* Overflow menu: block / report */}
      <Modal visible={showMenu} animationType="fade" transparent>
        <Pressable style={styles.menuBackdrop} onPress={() => setShowMenu(false)}>
          <Pressable style={styles.menuSheet} onPress={() => {}}>
            {isBlocked ? (
              <Pressable style={styles.menuItem} onPress={() => { setShowMenu(false); void handleUnblock(); }}>
                <Text style={styles.menuItemText}>{t('publicProfile.unblock')}</Text>
              </Pressable>
            ) : (
              <Pressable style={styles.menuItem} onPress={() => { setShowMenu(false); handleBlock(); }}>
                <Text style={[styles.menuItemText, { color: colors.error }]}>{t('publicProfile.block')}</Text>
              </Pressable>
            )}
            <View style={styles.menuDivider} />
            <Pressable style={styles.menuItem} onPress={() => { setShowMenu(false); setShowReport(true); }}>
              <Text style={[styles.menuItemText, { color: colors.error }]}>{t('report.reportUser')}</Text>
            </Pressable>
          </Pressable>
        </Pressable>
      </Modal>

      <ReportModal
        visible={showReport}
        targetType="user"
        targetId={id ?? ''}
        onClose={() => setShowReport(false)}
      />
    </ScrollView>

    {/* Floating accept/refuse bar when coming from a pending request */}
    {/* Contact request modal */}
    <Modal visible={showRequestModal} animationType="slide" transparent>
      <Pressable style={styles.modalBackdrop} onPress={() => setShowRequestModal(false)}>
        <Pressable style={styles.modalSheet} onPress={() => {}}>
          <View style={styles.modalHandle} />
          <Text style={styles.modalTitle}>{t('publicProfile.requestModalTitle')}</Text>
          <TextInput
            style={styles.requestInput}
            value={requestMessage}
            onChangeText={setRequestMessage}
            multiline
            maxLength={500}
            placeholder={t('publicProfile.requestPlaceholder')}
            placeholderTextColor={colors.textSecondary}
          />
          <Pressable
            style={[styles.modalSendButton, requestSending && { opacity: 0.4 }]}
            onPress={async () => {
              if (!requestMessage.trim()) return;
              setRequestSending(true);
              try {
                await conversationService.sendContactRequest(id ?? '', requestMessage.trim(), 'profile');
                await queryClient.invalidateQueries({ queryKey: ['conversation-state', id] });
                setShowRequestModal(false);
                Burnt.toast({ title: t('publicProfile.requestSent'), preset: 'done' });
              } catch (err) {
                Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
              } finally {
                setRequestSending(false);
              }
            }}
            disabled={requestSending || !requestMessage.trim()}
          >
            <Text style={styles.modalSendText}>{t('publicProfile.sendRequest')}</Text>
          </Pressable>
        </Pressable>
      </Pressable>
    </Modal>

    {participationId && !requestHandled && (
      <View style={[styles.requestCard, { bottom: insets.bottom + spacing.md }]}>
        <Text style={styles.requestContext} numberOfLines={2}>
          {t('participants.requestFor', { title: activityTitle ? decodeURIComponent(activityTitle) : '...' })}
        </Text>
        <View style={styles.requestButtons}>
          <Pressable
            style={[styles.requestAccept, requestLoading && styles.requestDisabled]}
            onPress={() => handleParticipation('accept')}
            disabled={requestLoading}
          >
            <Text style={styles.requestAcceptText}>{t('participants.accept')}</Text>
          </Pressable>
          <Pressable
            style={[styles.requestRefuse, requestLoading && styles.requestDisabled]}
            onPress={() => handleParticipation('refuse')}
            disabled={requestLoading}
          >
            <Text style={styles.requestRefuseText}>{t('participants.refuse')}</Text>
          </Pressable>
        </View>
      </View>
    )}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.lg, paddingBottom: spacing.xl + 32 },
  center: { flex: 1, backgroundColor: colors.background, alignItems: 'center', justifyContent: 'center' },
  actions: { marginTop: spacing.lg, gap: spacing.sm },
  messageButton: {
    backgroundColor: colors.cta, borderRadius: radius.full,
    paddingVertical: spacing.md, alignItems: 'center',
  },
  messageText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: 'bold' },
  menuBackdrop: { flex: 1, alignItems: 'flex-end', paddingTop: 56, paddingRight: spacing.md },
  menuSheet: {
    backgroundColor: colors.surface, borderRadius: radius.lg,
    minWidth: 220, paddingVertical: spacing.xs,
    elevation: 6, shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.3, shadowRadius: 4,
  },
  menuItem: { paddingHorizontal: spacing.md, paddingVertical: spacing.sm },
  menuItemText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '500' },
  menuDivider: { height: 1, backgroundColor: colors.background, marginVertical: 2 },
  modalBackdrop: { flex: 1, backgroundColor: colors.overlay, justifyContent: 'flex-end' },
  modalSheet: {
    backgroundColor: colors.background, borderTopLeftRadius: radius.lg, borderTopRightRadius: radius.lg,
    padding: spacing.lg, paddingBottom: spacing.xl + 16,
  },
  modalHandle: { width: 40, height: 4, borderRadius: 2, backgroundColor: colors.textSecondary, alignSelf: 'center', marginBottom: spacing.lg, opacity: 0.4 },
  modalTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold', marginBottom: spacing.md },
  requestInput: {
    backgroundColor: colors.surface, borderRadius: radius.md,
    padding: spacing.md, color: colors.textPrimary, fontSize: fontSizes.sm,
    minHeight: 100, textAlignVertical: 'top', marginBottom: spacing.md,
  },
  modalSendButton: {
    backgroundColor: colors.cta, borderRadius: radius.full,
    paddingVertical: spacing.md, alignItems: 'center',
  },
  modalSendText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
  requestCard: {
    position: 'absolute', left: spacing.lg, right: spacing.lg,
    backgroundColor: colors.surface, borderRadius: radius.lg,
    padding: spacing.md, gap: spacing.sm,
    elevation: 8, shadowColor: '#000', shadowOffset: { width: 0, height: 4 }, shadowOpacity: 0.3, shadowRadius: 8,
  },
  requestContext: {
    color: colors.textSecondary, fontSize: fontSizes.xs, textAlign: 'center',
  },
  requestButtons: { flexDirection: 'row', gap: spacing.sm },
  requestAccept: {
    flex: 1, backgroundColor: colors.success, borderRadius: radius.full,
    paddingVertical: spacing.sm, alignItems: 'center',
  },
  requestAcceptText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: 'bold' },
  requestRefuse: {
    flex: 1, backgroundColor: colors.error, borderRadius: radius.full,
    paddingVertical: spacing.sm, alignItems: 'center',
  },
  requestRefuseText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: 'bold' },
  requestDisabled: { opacity: 0.4 },
});
