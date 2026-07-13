import { useMemo } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet } from 'react-native';
import { useRouter, Redirect } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import { Flag, BadgeCheck, ChevronRight, Search, type LucideIcon } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { reportService } from '@/services/report-service';
import { proService } from '@/services/pro-service';
import { useIsAdmin } from '@/hooks/use-is-admin';

// Admin hub — entry point to every admin tool. New tools get a row here.
export default function AdminHubScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();

  const { isAdmin, isLoading: adminLoading } = useIsAdmin();
  const { data: reports } = useQuery({ queryKey: ['admin-reports'], queryFn: () => reportService.getAll(), enabled: isAdmin });
  const { data: pendingPros } = useQuery({ queryKey: ['admin-pending-pros'], queryFn: () => proService.getPendingApplications(), enabled: isAdmin });

  const pendingReports = (reports ?? []).filter((r) => r.status === 'pending').length;
  const pendingProsCount = (pendingPros ?? []).length;

  const Row = ({ icon: Icon, label, sublabel, count, onPress, last }: {
    icon: LucideIcon; label: string; sublabel: string; count: number; onPress: () => void; last?: boolean;
  }) => (
    <Pressable style={[styles.row, last && styles.rowLast]} onPress={onPress}>
      <View style={styles.iconWrap}><Icon size={20} color={colors.cta} strokeWidth={2.2} /></View>
      <View style={{ flex: 1, minWidth: 0 }}>
        <Text style={styles.rowLabel}>{label}</Text>
        <Text style={styles.rowSub} numberOfLines={1}>{sublabel}</Text>
      </View>
      {count > 0 && <View style={styles.badge}><Text style={styles.badgeText}>{count}</Text></View>}
      <ChevronRight size={18} color={colors.textSecondary} strokeWidth={2.2} />
    </Pressable>
  );

  if (adminLoading) return null;
  if (!isAdmin) return <Redirect href="/(auth)/(tabs)/carte" />;

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <View style={styles.card}>
        <Row
          icon={Flag}
          label={t('admin.reports', { defaultValue: 'Signalements' })}
          sublabel={t('admin.reportsSub', { defaultValue: 'Modérer les contenus signalés' })}
          count={pendingReports}
          onPress={() => router.push('/(auth)/admin/moderation')}
        />
        <Row
          icon={BadgeCheck}
          label={t('admin.proRequests', { defaultValue: 'Demandes pro' })}
          sublabel={t('admin.proRequestsSub', { defaultValue: 'Vérifier et valider les pages pro' })}
          count={pendingProsCount}
          onPress={() => router.push('/(auth)/admin/moderation?tab=pros')}
        />
        <Row
          icon={Search}
          label={t('admin.lookupTitle', { defaultValue: 'Recherche & modération' })}
          sublabel={t('admin.lookupSub', { defaultValue: 'Qui est / qui possède · suspendre' })}
          count={0}
          onPress={() => router.push('/(auth)/admin/lookup')}
          last
        />
      </View>
    </ScrollView>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.md },
  card: {
    borderWidth: 1.5,
    borderColor: colors.borderMuted,
    borderRadius: radius.lg,
    backgroundColor: colors.surface,
    paddingHorizontal: spacing.sm,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    paddingVertical: spacing.sm + 4,
    paddingHorizontal: spacing.xs,
    borderBottomWidth: 1,
    borderBottomColor: colors.line,
  },
  rowLast: { borderBottomWidth: 0 },
  iconWrap: { width: 28, alignItems: 'center' },
  rowLabel: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  rowSub: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: 1 },
  badge: {
    minWidth: 22, height: 22, borderRadius: 11, backgroundColor: colors.cta,
    alignItems: 'center', justifyContent: 'center', paddingHorizontal: 6,
  },
  badgeText: { color: '#FFFFFF', fontSize: fontSizes.xs, fontWeight: '800' },
});
