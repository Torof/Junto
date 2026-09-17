import { useMemo } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet } from 'react-native';
import { Stack, useRouter } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { CalendarDays, BellRing, MessagesSquare, Mountain, Link2, ChevronRight } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing } from '@/constants/theme';
import { useAuth } from '@/hooks/use-auth';
import { bookingService } from '@/services/booking-service';
import { proService } from '@/services/pro-service';
import { UserAvatar } from '@/components/user-avatar';

export default function ProSpaceScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const { session } = useAuth();
  const userId = session?.user?.id ?? null;

  const { data: proProfile } = useQuery({
    queryKey: ['pro-profile', userId],
    queryFn: () => proService.getById(userId as string),
    enabled: !!userId,
  });

  // Fenêtre courte pour les compteurs du hub (7 jours + demandes du mois).
  const from = dayjs().format('YYYY-MM-DD');
  const to = dayjs().add(1, 'month').format('YYYY-MM-DD');
  const { data: agenda } = useQuery({
    queryKey: ['pro-agenda', from, to],
    queryFn: () => bookingService.getAgenda(from, to),
  });

  const pendingCount = (agenda ?? []).filter((a) => a.kind === 'booking' && a.status === 'pending').length;
  const week = dayjs().add(7, 'day').format('YYYY-MM-DD');
  const weekBookings = (agenda ?? []).filter(
    (a) => a.kind === 'booking' && a.status === 'accepted' && a.day <= week,
  );
  const weekPeople = weekBookings.reduce((s, b) => s + (b.party_size ?? 0), 0);
  const todayIso = dayjs().format('YYYY-MM-DD');
  const todayCount = weekBookings.filter((b) => b.day === todayIso).length;

  const Row = ({ icon, title, sub, badge, onPress }: {
    icon: React.ReactNode; title: string; sub: string; badge?: number; onPress: () => void;
  }) => (
    <Pressable style={({ pressed }) => [styles.row, pressed && styles.pressed]} onPress={onPress}>
      <View style={styles.ico}>{icon}</View>
      <View style={{ flex: 1, minWidth: 0 }}>
        <Text style={styles.rowTitle}>{title}</Text>
        <Text style={styles.rowSub} numberOfLines={1}>{sub}</Text>
      </View>
      {badge ? <View style={styles.badge}><Text style={styles.badgeText}>{badge}</Text></View> : null}
      <ChevronRight size={18} color={colors.textMuted} strokeWidth={2.2} />
    </Pressable>
  );

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.scroll}>
      <Stack.Screen options={{ title: t('booking.proSpace', { defaultValue: 'Espace pro' }) }} />

      <View style={styles.head}>
        <UserAvatar name={proProfile?.company_name ?? proProfile?.display_name ?? '?'} avatarUrl={null} size={48} />
        <View style={{ flex: 1, minWidth: 0 }}>
          <Text style={styles.headName} numberOfLines={1}>{proProfile?.company_name ?? '…'}</Text>
          <Text style={styles.headSub} numberOfLines={1}>
            {proProfile?.status === 'approved'
              ? t('booking.pagePublic', { defaultValue: 'Page publique active' })
              : t('booking.pagePending', { defaultValue: 'En attente de validation' })}
          </Text>
        </View>
      </View>

      <Row
        icon={<CalendarDays size={20} color={colors.cta} strokeWidth={2.2} />}
        title={t('booking.agendaTitle', { defaultValue: 'Agenda' })}
        sub={t('booking.hubAgendaSub', {
          defaultValue: 'Aujourd’hui : {{today}} · 7 jours : {{count}} résas, {{people}} pers.',
          today: todayCount, count: weekBookings.length, people: weekPeople,
        })}
        onPress={() => router.push('/(auth)/pro/agenda')}
      />
      <Row
        icon={<BellRing size={20} color={colors.cta} strokeWidth={2.2} />}
        title={t('booking.requests', { defaultValue: 'Demandes' })}
        sub={pendingCount > 0
          ? t('booking.hubRequestsSub', { defaultValue: '{{count}} en attente de réponse', count: pendingCount })
          : t('booking.hubRequestsNone', { defaultValue: 'Aucune demande en attente' })}
        badge={pendingCount || undefined}
        onPress={() => router.push('/(auth)/pro/agenda')}
      />
      <Row
        icon={<MessagesSquare size={20} color={colors.cta} strokeWidth={2.2} />}
        title={t('booking.hubMessages', { defaultValue: 'Messages clients' })}
        sub={t('booking.hubMessagesSub', { defaultValue: 'Toutes tes conversations' })}
        onPress={() => router.push('/(auth)/(tabs)/messagerie')}
      />
      <Row
        icon={<Mountain size={20} color={colors.cta} strokeWidth={2.2} />}
        title={t('booking.hubOfferings', { defaultValue: 'Mes offres' })}
        sub={t('booking.hubOfferingsSub', { defaultValue: 'Gérer le catalogue de sorties' })}
        onPress={() => router.push(`/(auth)/pro/${userId}`)}
      />
      <Row
        icon={<Link2 size={20} color={colors.cta} strokeWidth={2.2} />}
        title={t('booking.hubPage', { defaultValue: 'Ma page publique' })}
        sub={t('booking.hubPageSub', { defaultValue: 'Voir ma vitrine comme un client' })}
        onPress={() => router.push(`/(auth)/pro/${userId}`)}
      />

      <Text style={styles.foot}>{t('booking.hubSoon', { defaultValue: 'Bientôt : historique clients & statistiques' })}</Text>
    </ScrollView>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  scroll: { padding: spacing.md, paddingBottom: spacing.xl },
  head: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 4, marginBottom: spacing.md },
  headName: { color: colors.textPrimary, fontSize: fontSizes.md + 1, fontWeight: '800' },
  headSub: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, marginTop: 1 },
  row: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 4,
    backgroundColor: colors.surface, borderRadius: 16, padding: spacing.md, marginBottom: spacing.sm + 2,
  },
  pressed: { opacity: 0.85, transform: [{ scale: 0.99 }] },
  ico: {
    width: 36, height: 36, borderRadius: 10, backgroundColor: colors.cta + '18',
    alignItems: 'center', justifyContent: 'center',
  },
  rowTitle: { color: colors.textPrimary, fontSize: fontSizes.sm + 2, fontWeight: '800' },
  rowSub: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, marginTop: 1 },
  badge: {
    minWidth: 20, height: 20, borderRadius: 10, backgroundColor: colors.cta,
    alignItems: 'center', justifyContent: 'center', paddingHorizontal: 6,
  },
  badgeText: { color: '#FFFFFF', fontSize: fontSizes.xs - 1, fontWeight: '800' },
  foot: { textAlign: 'center', color: colors.textMuted, fontSize: fontSizes.xs, marginTop: spacing.sm },
});
