import { useState } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet, Alert } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import * as Burnt from 'burnt';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { participationService } from '@/services/participation-service';
import { reliabilityService } from '@/services/reliability-service';
import { UserAvatar } from '@/components/user-avatar';
import { getFriendlyError } from '@/utils/friendly-error';

export default function ConfirmPresenceScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { t } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const [presentIds, setPresentIds] = useState<Set<string>>(new Set());
  const [isSaving, setIsSaving] = useState(false);

  const { data: participants, isLoading } = useQuery({
    queryKey: ['participants', id],
    queryFn: () => participationService.getForActivity(id ?? ''),
    enabled: !!id,
  });

  const accepted = (participants ?? []).filter((p) => p.status === 'accepted');

  const togglePresent = (userId: string) => {
    setPresentIds((prev) => {
      const next = new Set(prev);
      if (next.has(userId)) next.delete(userId);
      else next.add(userId);
      return next;
    });
  };

  const handleConfirm = async () => {
    if (!id) return;
    setIsSaving(true);
    try {
      await reliabilityService.confirmPresence(id, [...presentIds]);
      await queryClient.invalidateQueries({ queryKey: ['participants', id] });
      Burnt.toast({ title: t('presence.confirmed'), preset: 'done' });
      router.back();
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
    } finally {
      setIsSaving(false);
    }
  };

  if (isLoading) {
    return (
      <View style={styles.center}>
        <Text style={styles.loadingText}>...</Text>
      </View>
    );
  }

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <Text style={styles.title}>{t('presence.title')}</Text>
      <Text style={styles.subtitle}>{t('presence.subtitle')}</Text>

      {accepted.map((p) => (
        <Pressable
          key={p.participation_id}
          style={[styles.card, presentIds.has(p.user_id) && styles.cardSelected]}
          onPress={() => togglePresent(p.user_id)}
        >
          <UserAvatar name={p.display_name} avatarUrl={p.avatar_url} size={40} />
          <Text style={styles.name}>{p.display_name}</Text>
          <Text style={styles.check}>{presentIds.has(p.user_id) ? '✓' : ''}</Text>
        </Pressable>
      ))}

      <Pressable
        style={[styles.confirmButton, isSaving && styles.buttonDisabled]}
        onPress={handleConfirm}
        disabled={isSaving}
      >
        <Text style={styles.confirmText}>{isSaving ? '...' : t('presence.confirm')}</Text>
      </Pressable>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.lg, paddingBottom: spacing.xl + 32 },
  center: { flex: 1, backgroundColor: colors.background, alignItems: 'center', justifyContent: 'center' },
  loadingText: { color: colors.textSecondary, fontSize: fontSizes.lg },
  title: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold', marginBottom: spacing.xs },
  subtitle: { color: colors.textSecondary, fontSize: fontSizes.sm, marginBottom: spacing.xl },
  card: {
    flexDirection: 'row', alignItems: 'center',
    backgroundColor: colors.surface, borderRadius: radius.md,
    padding: spacing.md, marginBottom: spacing.sm, gap: spacing.md,
  },
  cardSelected: { backgroundColor: colors.success + '20', borderWidth: 1, borderColor: colors.success },
  name: { color: colors.textPrimary, fontSize: fontSizes.sm, flex: 1 },
  check: { color: colors.success, fontSize: 20, fontWeight: 'bold', width: 24 },
  confirmButton: { backgroundColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.lg },
  buttonDisabled: { opacity: 0.4 },
  confirmText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
});
