import { useMemo } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet, Alert, Linking } from 'react-native';
import { Stack, useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import * as Burnt from 'burnt';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { CalendarDays, MessagesSquare, Mountain, Eye, Phone, MessageCircle } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import { useAuth } from '@/hooks/use-auth';
import { bookingService, type AgendaItem, type BookingPeriod } from '@/services/booking-service';
import { proService } from '@/services/pro-service';
import { UserAvatar } from '@/components/user-avatar';
import { PressableScale } from '@/components/pressable-scale';
import { getFriendlyError } from '@/utils/friendly-error';
import { sportCategoryColor } from '@/utils/sport-category-color';

export default function ProSpaceScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const { session } = useAuth();
  const userId = session?.user?.id ?? null;
  const queryClient = useQueryClient();

  const { data: proProfile } = useQuery({
    queryKey: ['pro-profile', userId],
    queryFn: () => proService.getById(userId as string),
    enabled: !!userId,
  });

  // Fenêtre courte pour le dashboard (aujourd'hui + compteurs 7 j + demandes du mois).
  const from = dayjs().format('YYYY-MM-DD');
  const to = dayjs().add(1, 'month').format('YYYY-MM-DD');
  const { data: agenda } = useQuery({
    queryKey: ['pro-agenda', from, to],
    queryFn: () => bookingService.getAgenda(from, to),
  });

  const invalidate = () => queryClient.invalidateQueries({ queryKey: ['pro-agenda'] });

  const todayIso = dayjs().format('YYYY-MM-DD');
  const todayBookings = (agenda ?? [])
    .filter((a) => a.kind === 'booking' && a.status === 'accepted' && a.day === todayIso)
    .sort((a, b) => a.period.localeCompare(b.period));
  const pendings = (agenda ?? []).filter((a) => a.kind === 'booking' && a.status === 'pending');
  const week = dayjs().add(7, 'day').format('YYYY-MM-DD');
  const weekBookings = (agenda ?? []).filter(
    (a) => a.kind === 'booking' && a.status === 'accepted' && a.day <= week,
  );
  const weekPeople = weekBookings.reduce((s, b) => s + (b.party_size ?? 0), 0);
  const firstPending = pendings[0];

  const periodTag = (p: BookingPeriod) =>
    p === 'am' ? t('booking.amShort', { defaultValue: 'MATIN' }) : t('booking.pmShort', { defaultValue: 'A-MIDI' });

  const handleAccept = async (b: AgendaItem) => {
    try {
      await bookingService.accept(b.id);
      Burnt.toast({ title: t('booking.acceptedToast', { defaultValue: 'Réservation confirmée' }), preset: 'done' });
      await invalidate();
    } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
  };
  const handleDecline = (b: AgendaItem) => {
    Alert.alert(
      t('booking.declineConfirmTitle', { defaultValue: 'Refuser cette demande ?' }),
      t('booking.declineConfirmBody', { defaultValue: 'Le client sera prévenu.' }),
      [
        { text: t('activity.no', { defaultValue: 'Non' }), style: 'cancel' },
        {
          text: t('activity.yes', { defaultValue: 'Oui' }),
          style: 'destructive',
          onPress: async () => {
            try {
              await bookingService.decline(b.id);
              await invalidate();
            } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
          },
        },
      ],
    );
  };

  const Tile = ({ icon, title, sub, badge, onPress }: {
    icon: React.ReactNode; title: string; sub: string; badge?: number; onPress: () => void;
  }) => (
    <PressableScale style={styles.tile} onPress={onPress} accessibilityLabel={title}>
      <View style={styles.tileTop}>
        <View style={styles.ico}>{icon}</View>
        {badge ? <View style={styles.badge}><Text style={styles.badgeText}>{badge}</Text></View> : null}
      </View>
      <Text style={styles.tileTitle}>{title}</Text>
      <Text style={styles.tileSub} numberOfLines={1}>{sub}</Text>
    </PressableScale>
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

      <Text style={styles.eyebrow}>
        {t('booking.today', { defaultValue: 'Aujourd’hui' })} · {dayjs().locale('fr').format('ddd D MMM')}
      </Text>
      <View style={styles.card}>
        {todayBookings.length === 0 ? (
          <Text style={styles.emptyLine}>{t('booking.todayNone', { defaultValue: 'Aucune sortie aujourd’hui.' })}</Text>
        ) : todayBookings.map((b, i) => {
          const sc = sportCategoryColor(b.sport_category, colors.cta);
          return (
            <View key={b.id} style={[styles.todayLine, i > 0 && styles.todaySep]}>
              <View style={[styles.slotChip, { backgroundColor: sc + '1F' }]}>
                <Text style={[styles.slotChipText, { color: sc }]}>{periodTag(b.period)}</Text>
              </View>
              <View style={{ flex: 1, minWidth: 0 }}>
                <Text style={styles.todayName} numberOfLines={1}>{b.client_name ?? '—'} · {b.party_size} pers.</Text>
                <Text style={styles.todaySub} numberOfLines={1}>
                  {b.offering_title} · {b.is_manual
                    ? t('booking.manualTag', { defaultValue: 'manuel' })
                    : t('booking.viaJunto', { defaultValue: 'via l’app' })}
                </Text>
              </View>
              {b.is_manual && b.manual_phone ? (
                <PressableScale style={styles.roundBtn} onPress={() => Linking.openURL(`tel:${b.manual_phone}`)} accessibilityLabel={t('booking.call', { defaultValue: 'Appeler' })}>
                  <Phone size={15} color={colors.textSecondary} strokeWidth={2.2} />
                </PressableScale>
              ) : !b.is_manual && b.client_id ? (
                <PressableScale style={styles.roundBtn} onPress={() => router.push(`/(auth)/profile/${b.client_id}`)} accessibilityLabel={t('booking.clientProfile', { defaultValue: 'Profil client' })}>
                  <MessageCircle size={15} color={colors.textSecondary} strokeWidth={2.2} />
                </PressableScale>
              ) : null}
            </View>
          );
        })}
      </View>

      {pendings.length > 0 && firstPending && (
        <>
          <Text style={styles.eyebrow}>
            {t('booking.requests', { defaultValue: 'Demandes' })} · {pendings.length}{' '}
            {pendings.length > 1
              ? t('booking.requestsWaitingPlural', { defaultValue: 'en attente' })
              : t('booking.requestsWaiting', { defaultValue: 'en attente' })}
          </Text>
          <View style={styles.card}>
            <PressableScale
              style={styles.reqHead}
              onPress={() => firstPending.client_id && router.push(`/(auth)/profile/${firstPending.client_id}`)}
              disabled={!firstPending.client_id}
            >
              <UserAvatar name={firstPending.client_name ?? '?'} avatarUrl={null} size={36} />
              <View style={{ flex: 1, minWidth: 0 }}>
                <Text style={styles.reqName} numberOfLines={1}>
                  {firstPending.client_name ?? '—'} · {firstPending.party_size} pers.
                </Text>
                <Text style={[styles.reqMeta, { color: sportCategoryColor(firstPending.sport_category, colors.textSecondary) }]} numberOfLines={1}>
                  {firstPending.offering_title} — {dayjs(firstPending.day).locale('fr').format('ddd D MMM')}, {firstPending.period === 'am' ? t('booking.am', { defaultValue: 'matin' }) : t('booking.pm', { defaultValue: 'après-midi' })}
                </Text>
              </View>
            </PressableScale>
            {firstPending.message ? <Text style={styles.reqMsg} numberOfLines={2}>« {firstPending.message} »</Text> : null}
            <View style={styles.reqActs}>
              <Pressable style={({ pressed }) => [styles.btnGhost, pressed && styles.pressed]} onPress={() => handleDecline(firstPending)}>
                <Text style={styles.btnGhostText}>{t('booking.decline', { defaultValue: 'Refuser' })}</Text>
              </Pressable>
              <Pressable style={({ pressed }) => [styles.btnPrimary, pressed && styles.pressed]} onPress={() => handleAccept(firstPending)}>
                <Text style={styles.btnPrimaryText}>{t('booking.accept', { defaultValue: 'Accepter' })}</Text>
              </Pressable>
            </View>
          </View>
          {pendings.length > 1 && (
            <PressableScale onPress={() => router.push('/(auth)/pro/agenda')}>
              <Text style={styles.seeAll}>
                {t('booking.seeAllRequests', { defaultValue: 'Voir les {{count}} demandes ›', count: pendings.length })}
              </Text>
            </PressableScale>
          )}
        </>
      )}

      <Text style={styles.eyebrow}>{t('booking.manage', { defaultValue: 'Gérer' })}</Text>
      <View style={styles.tiles}>
        <Tile
          icon={<CalendarDays size={18} color={colors.cta} strokeWidth={2.2} />}
          title={t('booking.agendaTitle', { defaultValue: 'Agenda' })}
          sub={t('booking.hubAgendaSub7', {
            defaultValue: '7 j : {{count}} résas · {{people}} pers.',
            count: weekBookings.length, people: weekPeople,
          })}
          badge={pendings.length || undefined}
          onPress={() => router.push('/(auth)/pro/agenda')}
        />
        <Tile
          icon={<Mountain size={18} color={colors.cta} strokeWidth={2.2} />}
          title={t('booking.hubOfferings', { defaultValue: 'Mes offres' })}
          sub={t('booking.hubOfferingsSub', { defaultValue: 'Catalogue de sorties' })}
          onPress={() => router.push(`/(auth)/pro/${userId}`)}
        />
        <Tile
          icon={<MessagesSquare size={18} color={colors.cta} strokeWidth={2.2} />}
          title={t('booking.hubMessages', { defaultValue: 'Messages' })}
          sub={t('booking.hubMessagesSub', { defaultValue: 'Conversations clients' })}
          onPress={() => router.push('/(auth)/(tabs)/messagerie')}
        />
        <Tile
          icon={<Eye size={18} color={colors.cta} strokeWidth={2.2} />}
          title={t('booking.hubPage', { defaultValue: 'Ma page publique' })}
          sub={t('booking.hubPageSub', { defaultValue: 'Voir comme un client' })}
          onPress={() => router.push(`/(auth)/pro/${userId}`)}
        />
      </View>

      <Text style={styles.foot}>{t('booking.hubSoon', { defaultValue: 'Bientôt : historique clients & statistiques' })}</Text>
    </ScrollView>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  scroll: { padding: spacing.md, paddingBottom: spacing.xl },
  head: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 4, marginBottom: spacing.xs },
  headName: { color: colors.textPrimary, fontSize: fontSizes.md + 1, fontWeight: '800' },
  headSub: { color: colors.cta, fontSize: fontSizes.xs + 1, marginTop: 1, fontWeight: '600' },
  eyebrow: {
    color: colors.textMuted, fontSize: fontSizes.xs, fontWeight: '800',
    textTransform: 'uppercase', letterSpacing: 0.8, marginTop: spacing.md + 2, marginBottom: spacing.sm,
  },
  card: { backgroundColor: colors.surface, borderRadius: radius.card, padding: spacing.md, ...shadows.card },
  emptyLine: { color: colors.textSecondary, fontSize: fontSizes.sm },
  todayLine: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 2, paddingVertical: 4 },
  todaySep: { borderTopWidth: 1, borderTopColor: colors.textMuted + '1A', marginTop: spacing.sm, paddingTop: spacing.sm + 4 },
  slotChip: { minWidth: 52, alignItems: 'center', borderRadius: 9, paddingHorizontal: 7, paddingVertical: 5 },
  slotChipText: { fontSize: fontSizes.xs - 1, fontWeight: '800' },
  todayName: { color: colors.textPrimary, fontSize: fontSizes.sm + 1, fontWeight: '700' },
  todaySub: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, marginTop: 1 },
  roundBtn: {
    width: 32, height: 32, borderRadius: 16, backgroundColor: colors.surfaceAlt,
    alignItems: 'center', justifyContent: 'center',
  },
  reqHead: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 2 },
  reqName: { color: colors.textPrimary, fontSize: fontSizes.sm + 1, fontWeight: '700' },
  reqMeta: { fontSize: fontSizes.sm - 1, marginTop: 1, fontWeight: '600' },
  reqMsg: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, fontStyle: 'italic', marginTop: spacing.sm },
  reqActs: { flexDirection: 'row', gap: spacing.sm, marginTop: spacing.sm + 2, alignItems: 'center' },
  btnGhost: { paddingVertical: spacing.sm + 1, paddingHorizontal: spacing.md, borderRadius: radius.full },
  btnGhostText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600' },
  btnPrimary: {
    flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6,
    backgroundColor: colors.cta, borderRadius: radius.full, paddingVertical: spacing.sm + 2, paddingHorizontal: spacing.md,
  },
  btnPrimaryText: { color: colors.onCta, fontSize: fontSizes.sm, fontWeight: '700' },
  seeAll: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700', textAlign: 'center', paddingVertical: spacing.sm },
  pressed: { opacity: 0.85, transform: [{ scale: 0.98 }] },
  tiles: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm + 2 },
  tile: {
    width: '48%', flexGrow: 1, backgroundColor: colors.surface,
    borderRadius: radius.card, padding: spacing.sm + 5, ...shadows.card,
  },
  tileTop: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: spacing.sm },
  ico: {
    width: 32, height: 32, borderRadius: radius.lg + 2, backgroundColor: colors.cta + '18',
    alignItems: 'center', justifyContent: 'center',
  },
  tileTitle: { color: colors.textPrimary, fontSize: fontSizes.sm + 1, fontWeight: '800' },
  tileSub: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, marginTop: 2 },
  badge: {
    minWidth: 20, height: 20, borderRadius: 10, backgroundColor: colors.error,
    alignItems: 'center', justifyContent: 'center', paddingHorizontal: 6,
  },
  badgeText: { color: '#FFFFFF', fontSize: fontSizes.xs - 1, fontWeight: '800' },
  foot: { textAlign: 'center', color: colors.textMuted, fontSize: fontSizes.xs, marginTop: spacing.md },
});
