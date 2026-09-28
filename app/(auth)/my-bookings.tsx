import { useMemo, useState } from 'react';
import { View, Text, FlatList, StyleSheet, Alert, Pressable } from 'react-native';
import { Stack, useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import * as Burnt from 'burnt';
import dayjs from 'dayjs';
import relativeTime from 'dayjs/plugin/relativeTime';
import 'dayjs/locale/fr';
import { CalendarX2, MessageCircle, X, MapPin, Banknote } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import { bookingService, type MyBooking, type BookingStatus } from '@/services/booking-service';
import { PressableScale } from '@/components/pressable-scale';
import { LogoSpinner } from '@/components/logo-spinner';
import { getFriendlyError } from '@/utils/friendly-error';
import { sportCategoryColor } from '@/utils/sport-category-color';

dayjs.extend(relativeTime);

const STATUS_META: Record<BookingStatus, { key: string; fallback: string }> = {
  pending: { key: 'booking.status.pending', fallback: 'En attente' },
  accepted: { key: 'booking.status.accepted', fallback: 'Confirmée' },
  declined: { key: 'booking.status.declined', fallback: 'Refusée' },
  cancelled: { key: 'booking.status.cancelled', fallback: 'Annulée' },
  cancelled_pro: { key: 'booking.status.cancelledPro', fallback: 'Annulée par le pro' },
  expired: { key: 'booking.status.expired', fallback: 'Expirée' },
};

export default function MyBookingsScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();

  const { data: bookings, isLoading } = useQuery({
    queryKey: ['my-bookings'],
    queryFn: () => bookingService.getMyBookings(),
  });

  // À venir = pending/accepted futurs ; Passées = le reste (historique + terminés).
  const [tab, setTab] = useState<'upcoming' | 'past'>('upcoming');
  const todayIso = dayjs().format('YYYY-MM-DD');
  const { upcoming, past } = useMemo(() => {
    const up: MyBooking[] = [];
    const pa: MyBooking[] = [];
    for (const b of bookings ?? []) {
      if ((b.status === 'pending' || b.status === 'accepted') && b.day >= todayIso) up.push(b);
      else pa.push(b);
    }
    up.sort((a, b) => (a.day + a.period).localeCompare(b.day + b.period));
    return { upcoming: up, past: pa };
  }, [bookings, todayIso]);

  const statusColor = (s: BookingStatus): string => {
    switch (s) {
      case 'accepted': return colors.cta;
      case 'pending': return colors.warning;
      case 'declined':
      case 'cancelled_pro': return colors.error;
      default: return colors.textMuted;
    }
  };

  const handleCancel = (b: MyBooking) => {
    Alert.alert(
      t('booking.cancelConfirmTitle', { defaultValue: 'Annuler cette réservation ?' }),
      t('booking.cancelConfirmBody', { defaultValue: 'Le professionnel sera prévenu si elle était confirmée.' }),
      [
        { text: t('activity.no', { defaultValue: 'Non' }), style: 'cancel' },
        {
          text: t('activity.yes', { defaultValue: 'Oui' }),
          style: 'destructive',
          onPress: async () => {
            try {
              await bookingService.cancelAsClient(b.id);
              await queryClient.invalidateQueries({ queryKey: ['my-bookings'] });
              Burnt.toast({ title: t('booking.cancelledToast', { defaultValue: 'Réservation annulée' }) });
            } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
          },
        },
      ],
    );
  };

  const renderItem = ({ item }: { item: MyBooking }) => {
    const c = statusColor(item.status);
    const sc = sportCategoryColor(item.sport_category, colors.cta);
    const cancellable = item.status === 'pending' || (item.status === 'accepted' && item.day >= todayIso);
    const price = item.price_eur != null
      ? item.price_unit === 'group' ? item.price_eur : item.price_eur * item.party_size
      : null;
    const showTicket = item.status === 'accepted' && item.day >= todayIso;
    return (
      <View style={styles.card}>
        <View style={styles.topRow}>
          <View style={[styles.bigDate, { backgroundColor: sc + '1A' }]}>
            <Text style={[styles.bigDateDay, { color: sc }]}>{dayjs(item.day).format('D')}</Text>
            <Text style={[styles.bigDateMonth, { color: sc }]}>{dayjs(item.day).locale('fr').format('MMM')}</Text>
          </View>
          <View style={{ flex: 1, minWidth: 0 }}>
            <Text style={styles.title} numberOfLines={1}>{item.offering_title}</Text>
            <Text style={styles.sub} numberOfLines={1}>
              {item.pro_name ?? '—'} ·{' '}
              {item.period === 'am' ? t('booking.am', { defaultValue: 'matin' }) : t('booking.pm', { defaultValue: 'après-midi' })}
              {' · '}{item.party_size} {t('booking.people', { defaultValue: 'pers.' })}
            </Text>
          </View>
          <View style={[styles.statusPill, { backgroundColor: c + '1A' }]}>
            <Text style={[styles.statusText, { color: c }]}>
              {t(STATUS_META[item.status].key, { defaultValue: STATUS_META[item.status].fallback })}
            </Text>
          </View>
        </View>

        {showTicket && (item.location_name || price != null) && (
          <View style={styles.ticketRow}>
            {item.location_name ? (
              <View style={styles.ticketItem}>
                <MapPin size={13} color={colors.textSecondary} strokeWidth={2.2} />
                <Text style={styles.ticketText} numberOfLines={1}>{item.location_name}</Text>
              </View>
            ) : null}
            {price != null ? (
              <View style={styles.ticketItem}>
                <Banknote size={13} color={colors.textSecondary} strokeWidth={2.2} />
                <Text style={styles.ticketText}>
                  {price} € {t('booking.onSite', { defaultValue: 'sur place' })}
                </Text>
              </View>
            ) : null}
          </View>
        )}

        {(item.conversation_id || cancellable) && (
          <View style={styles.actions}>
            {item.conversation_id ? (
              <PressableScale style={styles.link} onPress={() => router.push(`/(auth)/conversation/${item.conversation_id}`)} hitSlop={6}>
                <MessageCircle size={15} color={colors.textSecondary} strokeWidth={2.2} />
                <Text style={styles.linkText}>{t('booking.openChat', { defaultValue: 'Discuter' })}</Text>
              </PressableScale>
            ) : null}
            {item.status === 'pending' ? (
              <Text style={styles.pendingHint}>
                {t('booking.sentAgo', { defaultValue: 'Envoyée {{ago}}', ago: dayjs(item.created_at).locale('fr').fromNow() })}
              </Text>
            ) : null}
            <View style={{ flex: 1 }} />
            {cancellable ? (
              <PressableScale style={styles.link} onPress={() => handleCancel(item)} hitSlop={6}>
                <X size={15} color={colors.error} strokeWidth={2.4} />
                <Text style={[styles.linkText, { color: colors.error }]}>{t('booking.cancel', { defaultValue: 'Annuler' })}</Text>
              </PressableScale>
            ) : null}
          </View>
        )}
      </View>
    );
  };

  const data = tab === 'upcoming' ? upcoming : past;

  return (
    <View style={styles.container}>
      <Stack.Screen options={{ title: t('booking.myBookings', { defaultValue: 'Mes réservations' }) }} />
      {isLoading ? (
        <View style={styles.center}><LogoSpinner size={36} /></View>
      ) : (
        <FlatList
          data={data}
          keyExtractor={(b) => b.id}
          renderItem={renderItem}
          contentContainerStyle={styles.list}
          ListHeaderComponent={
            <View style={styles.seg}>
              {(['upcoming', 'past'] as const).map((k) => (
                <Pressable
                  key={k}
                  style={[styles.segItem, tab === k && styles.segItemOn]}
                  onPress={() => setTab(k)}
                  accessibilityRole="button"
                  accessibilityState={{ selected: tab === k }}
                >
                  <Text style={[styles.segText, tab === k && styles.segTextOn]}>
                    {k === 'upcoming'
                      ? t('booking.tabUpcoming', { defaultValue: 'À venir' })
                      : t('booking.tabPast', { defaultValue: 'Passées' })}
                    {k === 'upcoming' && upcoming.length > 0 ? ` · ${upcoming.length}` : ''}
                  </Text>
                </Pressable>
              ))}
            </View>
          }
          ListEmptyComponent={
            <View style={styles.empty}>
              <View style={styles.emptyIc}><CalendarX2 size={30} color={colors.textMuted} strokeWidth={2} /></View>
              <Text style={styles.emptyTitle}>
                {tab === 'upcoming'
                  ? t('booking.emptyTitle', { defaultValue: 'Aucune réservation' })
                  : t('booking.emptyPastTitle', { defaultValue: 'Aucune réservation passée' })}
              </Text>
              {tab === 'upcoming' ? (
                <Text style={styles.emptyBody}>
                  {t('booking.emptyBody', { defaultValue: 'Réserve une sortie encadrée depuis la page d’un professionnel sur la carte.' })}
                </Text>
              ) : null}
            </View>
          }
        />
      )}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  list: { padding: spacing.md, paddingBottom: spacing.xl },
  seg: {
    flexDirection: 'row', backgroundColor: colors.surface, borderRadius: radius.full,
    padding: 3, marginBottom: spacing.md, ...shadows.card,
  },
  segItem: { flex: 1, alignItems: 'center', borderRadius: radius.full, paddingVertical: spacing.sm },
  segItemOn: { backgroundColor: colors.textPrimary },
  segText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '700' },
  segTextOn: { color: colors.background },
  card: {
    backgroundColor: colors.surface, borderRadius: radius.card, padding: spacing.md,
    marginBottom: spacing.sm + 2, gap: spacing.sm, ...shadows.card,
  },
  topRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 2 },
  bigDate: { minWidth: 48, alignItems: 'center', borderRadius: radius.card - 4, paddingVertical: 6, paddingHorizontal: 8 },
  bigDateDay: { fontSize: fontSizes.lg, fontWeight: '800', lineHeight: fontSizes.lg + 2 },
  bigDateMonth: { fontSize: fontSizes.xs - 1, fontWeight: '700', textTransform: 'uppercase' },
  title: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '800', letterSpacing: -0.2 },
  sub: { color: colors.textSecondary, fontSize: fontSizes.sm - 1, marginTop: 2 },
  statusPill: { borderRadius: radius.full, paddingHorizontal: spacing.sm + 2, paddingVertical: 4 },
  statusText: { fontSize: fontSizes.xs, fontWeight: '700' },
  ticketRow: {
    flexDirection: 'row', flexWrap: 'wrap', gap: spacing.md,
    borderTopWidth: 1, borderTopColor: colors.textMuted + '1F', paddingTop: spacing.sm,
  },
  ticketItem: { flexDirection: 'row', alignItems: 'center', gap: 5, flexShrink: 1 },
  ticketText: { color: colors.textSecondary, fontSize: fontSizes.sm - 1, fontWeight: '600' },
  actions: { flexDirection: 'row', alignItems: 'center', gap: spacing.md },
  link: { flexDirection: 'row', alignItems: 'center', gap: 5 },
  linkText: { color: colors.textSecondary, fontSize: fontSizes.sm - 1, fontWeight: '600' },
  pendingHint: { color: colors.textMuted, fontSize: fontSizes.xs + 1 },
  empty: { alignItems: 'center', paddingVertical: spacing.xl * 2, paddingHorizontal: spacing.lg, gap: spacing.sm },
  emptyIc: {
    width: 72, height: 72, borderRadius: radius.full, backgroundColor: colors.surfaceAlt,
    alignItems: 'center', justifyContent: 'center', marginBottom: spacing.xs,
  },
  emptyTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800', letterSpacing: -0.2 },
  emptyBody: { color: colors.textSecondary, fontSize: fontSizes.sm + 1, textAlign: 'center', lineHeight: 21, maxWidth: 280 },
});
