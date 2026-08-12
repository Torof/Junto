import { View, Text, Pressable, ScrollView, StyleSheet, Alert, Share } from 'react-native';
import { useState, useMemo } from 'react';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQueryClient } from '@tanstack/react-query';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import * as Burnt from 'burnt';
import { UserPlus, ChevronRight } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { formatLevelRange } from '@/constants/sport-levels';
import { useCreateStore } from '@/store/create-store';
import { messageService } from '@/services/message-service';
import { LogoSpinner } from '@/components/logo-spinner';
import { InvitePartnersSheet } from '@/components/invite-partners-sheet';
import { activityService } from '@/services/activity-service';
import { invitationService } from '@/services/invitation-service';
import { getFriendlyError } from '@/utils/friendly-error';
import { haptic } from '@/lib/haptics';

export default function CreateStep4() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t, i18n } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const { form, resetForm, updateForm, shareToConversationId, setShareTo } = useCreateStore();
  const [isLoading, setIsLoading] = useState(false);
  const [pickerOpen, setPickerOpen] = useState(false);

  const handlePublish = async () => {
    if (!form.location_meeting || !form.starts_at) return;

    if (form.starts_at <= new Date()) {
      Alert.alert(t('auth.error'), t('create.startsAtPast'));
      return;
    }

    setIsLoading(true);
    try {
      const activityId = await activityService.create({
        sport_id: form.sport_id,
        title: form.title,
        description: form.description || undefined,
        level: form.level,
        level_max: form.level_max,
        distance_km: form.distance_km,
        elevation_gain_m: form.elevation_gain_m,
        max_participants: form.max_participants,
        location_meeting: form.location_meeting!,
        location_end: form.location_end ?? undefined,
        location_objective: form.location_objective ?? undefined,
        objective_name: form.objective_name || undefined,
        meeting_name: form.meeting_name || undefined,
        trace_geojson: form.trace_geojson ?? undefined,
        starts_at: form.starts_at,
        duration_hours: form.duration_hours,
        duration_minutes: form.duration_minutes,
        visibility: form.visibility,
        requires_presence: form.requires_presence ?? true,
      });

      await queryClient.invalidateQueries({ queryKey: ['activities'] });

      // Best-effort invitations (Brique 4e-2) — the activity already exists; a
      // send failure must not fail creation (mirrors the private-link share).
      if (form.invitees.length > 0) {
        try { await invitationService.sendInvitations(activityId, form.invitees); } catch { /* ignore — activity exists */ }
      }

      haptic.success();
      const isPrivate = form.visibility === 'private_link' || form.visibility === 'private_link_approval';
      const title = form.title;
      const shareTo = shareToConversationId; // capture before reset
      resetForm();
      setShareTo(null);
      Burnt.toast({ title: t('toast.activityCreated'), preset: 'done' });

      // Proposed from a channel → post the outing card into that conversation
      // (best-effort; the activity already exists) and land there.
      if (shareTo) {
        try { await messageService.shareActivity(shareTo, activityId); } catch { /* activity exists */ }
        await queryClient.invalidateQueries({ queryKey: ['messages', shareTo] });
        await queryClient.invalidateQueries({ queryKey: ['conversations'] });
        router.dismissAll();
        router.navigate(`/(auth)/conversation/${shareTo}` as never);
        return;
      }

      if (isPrivate) {
        // Best-effort: the activity is already created. A token-fetch or share
        // failure (transient network, cancelled share) must NOT jump to the
        // outer catch — that showed a false "creation failed" and skipped the
        // navigation, stranding the user on a blanked step4 (audit 2026-07-13).
        try {
          const token = await activityService.getInviteToken(activityId);
          if (token) {
            // https link (not the raw junto:// scheme — messengers don't make
            // custom schemes tappable); the web /invite page relays into the app.
            const webHost = process.env.EXPO_PUBLIC_JUNTO_WEB_HOST ?? 'getjunto.app';
            await Share.share({ message: `${title} — https://${webHost}/invite/${token}` });
          }
        } catch {
          // token fetch failed or user cancelled share — ignore, activity exists
        }
      }

      // The 4 create steps are presented as a modal stack (see auth
      // _layout). router.replace from inside that stack to a non-modal
      // tab route was leaving the navigator half-dismissed → white
      // screen. Dismiss the modal stack first, then switch to the map
      // tab where the new activity appears.
      router.dismissAll();
      router.navigate('/(auth)/(tabs)/carte');
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'createActivity'));
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <>
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <Text style={styles.stepLabel}>{t('create.step', { current: 4, total: 4 })}</Text>
      <Text style={styles.title}>{t('create.step4Title')}</Text>

      <View style={styles.recap}>
        <RecapRow label={t('create.title')} value={form.title} />
        <RecapRow label={t('create.level')} value={formatLevelRange(form.level, form.level_max)} />
        <RecapRow label={t('create.maxParticipants')} value={form.max_participants === null ? t('create.openActivityValue') : `${form.max_participants}`} />
        <RecapRow
          label={t('create.dateTime')}
          value={form.starts_at ? dayjs(form.starts_at).locale(i18n.language).format('ddd D MMM · H[h]mm') : '-'}
        />
        <RecapRow
          label={t('create.duration')}
          value={`${form.duration_hours}h${form.duration_minutes > 0 ? form.duration_minutes : ''}`}
        />
        <RecapRow
          label={t('create.step3Title')}
          value={t(`create.visibility.${form.visibility}`)}
        />
        <RecapRow
          label={t('create.meetingPoint')}
          value={form.meeting_name || '✓'}
        />
        <RecapRow
          label={t('create.objectiveSet')}
          value={form.location_objective ? (form.objective_name || '✓') : '-'}
        />
        {form.description ? (
          <View style={styles.descSection}>
            <Text style={styles.recapLabel}>{t('activity.description')}</Text>
            <Text style={styles.recapDesc}>{form.description}</Text>
          </View>
        ) : null}
      </View>

      {/* Invite partners (Brique 4e-2) — optional; sent on publish. */}
      <Pressable style={styles.inviteField} onPress={() => setPickerOpen(true)}>
        <UserPlus size={18} color={colors.textPrimary} strokeWidth={2.2} />
        <View style={{ flex: 1, minWidth: 0 }}>
          <Text style={styles.inviteFieldLabel}>{t('create.invitePartners', { defaultValue: 'Inviter des partenaires' })}</Text>
          <Text style={styles.inviteFieldSub} numberOfLines={1}>
            {form.invitees.length > 0
              ? t('create.inviteCount', { defaultValue: '{{count}} sélectionné·es', count: form.invitees.length })
              : t('create.inviteOptional', { defaultValue: 'Optionnel · tes contacts + partenaires récents' })}
          </Text>
        </View>
        <ChevronRight size={18} color={colors.textSecondary} strokeWidth={2.2} />
      </Pressable>

      <Pressable
        style={[styles.publishButton, isLoading && styles.buttonDisabled]}
        onPress={handlePublish}
        disabled={isLoading}
      >
        {isLoading ? (
          <LogoSpinner size={20} />
        ) : (
          <Text style={styles.publishText}>{t('create.publish')}</Text>
        )}
      </Pressable>
    </ScrollView>

    <InvitePartnersSheet
      visible={pickerOpen}
      onConfirm={(ids) => updateForm({ invitees: ids })}
      initialSelected={form.invitees}
      onClose={() => setPickerOpen(false)}
    />
    </>
  );
}

function RecapRow({ label, value }: { label: string; value: string }) {
  const colors = useColors();
  const rs = useMemo(() => createRecapStyles(colors), [colors]);
  return (
    <View style={rs.row}>
      <Text style={rs.label}>{label}</Text>
      <Text style={rs.value}>{value}</Text>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.md, paddingBottom: spacing.xl + 32 },
  stepLabel: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '500', marginBottom: spacing.xs },
  title: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold', marginBottom: spacing.lg },
  recap: {
    backgroundColor: 'transparent',
    borderRadius: radius.sm,
    borderWidth: 1, borderColor: colors.borderMuted,
    padding: spacing.md, gap: spacing.sm,
  },
  descSection: { marginTop: spacing.sm },
  recapLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, marginBottom: spacing.xs },
  recapDesc: { color: colors.textPrimary, fontSize: fontSizes.sm },
  inviteField: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.md,
    padding: spacing.md, marginTop: spacing.md,
    borderWidth: 1, borderColor: colors.borderMuted, borderRadius: radius.sm,
  },
  inviteFieldLabel: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  inviteFieldSub: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: 2 },
  publishButton: { backgroundColor: colors.cta, borderRadius: radius.sm, paddingVertical: spacing.sm + 2, alignItems: 'center', marginTop: spacing.xl },
  buttonDisabled: { opacity: 0.4 },
  publishText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '700' },
});

const createRecapStyles = (colors: AppColors) => StyleSheet.create({
  row: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  label: { color: colors.textSecondary, fontSize: fontSizes.sm },
  value: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: 'bold' },
});
