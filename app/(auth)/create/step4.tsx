import { View, Text, Pressable, ScrollView, StyleSheet, Alert, Share } from 'react-native';
import { useState } from 'react';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQueryClient } from '@tanstack/react-query';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import * as Burnt from 'burnt';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { useCreateStore } from '@/store/create-store';
import { LogoSpinner } from '@/components/logo-spinner';
import { activityService } from '@/services/activity-service';
import { getFriendlyError } from '@/utils/friendly-error';
import { haptic } from '@/lib/haptics';

export default function CreateStep4() {
  const { t, i18n } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const { form, resetForm } = useCreateStore();
  const [isLoading, setIsLoading] = useState(false);

  const handlePublish = async () => {
    if (!form.location_meeting || !form.starts_at) return;

    setIsLoading(true);
    try {
      const activityId = await activityService.create({
        sport_id: form.sport_id,
        title: form.title,
        description: form.description || undefined,
        level: form.level,
        max_participants: form.max_participants,
        location_start: form.location_start ?? undefined,
        location_meeting: form.location_meeting!,
        location_end: form.location_end ?? undefined,
        location_objective: form.location_objective ?? undefined,
        objective_name: form.objective_name || undefined,
        starts_at: form.starts_at,
        duration_hours: form.duration_hours,
        duration_minutes: form.duration_minutes,
        visibility: form.visibility,
        requires_presence: form.requires_presence ?? true,
      });

      await queryClient.invalidateQueries({ queryKey: ['activities'] });
      haptic.success();
      const isPrivate = form.visibility === 'private_link' || form.visibility === 'private_link_approval';
      const title = form.title;
      resetForm();
      Burnt.toast({ title: t('toast.activityCreated'), preset: 'done' });

      if (isPrivate) {
        const token = await activityService.getInviteToken(activityId);
        if (token) {
          try {
            await Share.share({ message: `${title} — junto://invite/${token}` });
          } catch {
            // User cancelled share
          }
        }
      }

      router.replace('/(auth)/(tabs)/carte');
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'createActivity'));
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <Text style={styles.stepLabel}>{t('create.step', { current: 4, total: 4 })}</Text>
      <Text style={styles.title}>{t('create.step4Title')}</Text>

      <View style={styles.recap}>
        <RecapRow label={t('create.title')} value={form.title} />
        <RecapRow label={t('create.level')} value={form.level} />
        <RecapRow label={t('create.maxParticipants')} value={`${form.max_participants}`} />
        <RecapRow
          label={t('create.dateTime')}
          value={form.starts_at ? dayjs(form.starts_at).locale(i18n.language).format('ddd D MMM · HH:mm') : '-'}
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
          label={t('create.startPoint')}
          value={form.location_start ? '✓' : '-'}
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
  );
}

function RecapRow({ label, value }: { label: string; value: string }) {
  return (
    <View style={recapStyles.row}>
      <Text style={recapStyles.label}>{label}</Text>
      <Text style={recapStyles.value}>{value}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.lg, paddingBottom: spacing.xl + 32 },
  stepLabel: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '500', marginBottom: spacing.xs },
  title: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold', marginBottom: spacing.lg },
  recap: { backgroundColor: colors.surface, borderRadius: radius.md, padding: spacing.md, gap: spacing.sm },
  descSection: { marginTop: spacing.sm },
  recapLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, marginBottom: spacing.xs },
  recapDesc: { color: colors.textPrimary, fontSize: fontSizes.sm },
  publishButton: { backgroundColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.xl },
  buttonDisabled: { opacity: 0.4 },
  publishText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
});

const recapStyles = StyleSheet.create({
  row: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  label: { color: colors.textSecondary, fontSize: fontSizes.sm },
  value: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: 'bold' },
});
