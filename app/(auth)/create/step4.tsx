import { View, Text, Pressable, ScrollView, StyleSheet, Alert } from 'react-native';
import { useState } from 'react';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQueryClient } from '@tanstack/react-query';
import dayjs from 'dayjs';
import * as Burnt from 'burnt';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { useCreateStore } from '@/store/create-store';
import { activityService } from '@/services/activity-service';

export default function CreateStep4() {
  const { t } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const { form, resetForm } = useCreateStore();
  const [isLoading, setIsLoading] = useState(false);

  const handlePublish = async () => {
    if (!form.location_start || !form.starts_at) return;

    setIsLoading(true);
    try {
      await activityService.create({
        sport_id: form.sport_id,
        title: form.title,
        description: form.description || undefined,
        level: form.level,
        max_participants: form.max_participants,
        location_start: form.location_start,
        location_meeting: form.location_meeting ?? undefined,
        starts_at: form.starts_at,
        duration_hours: form.duration_hours,
        duration_minutes: form.duration_minutes,
        visibility: form.visibility,
      });

      await queryClient.invalidateQueries({ queryKey: ['activities'] });
      resetForm();
      Burnt.toast({ title: t('toast.activityCreated'), preset: 'done' });
      router.replace('/(auth)/(tabs)/carte');
    } catch (err) {
      Alert.alert(t('auth.error'), err instanceof Error ? err.message : t('auth.unknownError'));
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
          value={form.starts_at ? dayjs(form.starts_at).format('ddd D MMM · HH:mm') : '-'}
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
        <Text style={styles.publishText}>
          {isLoading ? '...' : t('create.publish')}
        </Text>
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
  stepLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, marginBottom: spacing.xs },
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
