import { useMemo } from 'react';
import { View, Text, FlatList, StyleSheet, Alert } from 'react-native';
import { Stack, useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import * as Burnt from 'burnt';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { CalendarX2, MessageCircle, X } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import { bookingService, type MyBooking, type BookingStatus } from '@/services/booking-service';
import { PressableScale } from '@/components/pressable-scale';
import { LogoSpinner } from '@/components/logo-spinner';
import { getFriendlyError } from '@/utils/friendly-error';

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
    const cancellable = item.status === 'pending' || (item.status === 'accepted' && item.day >= dayjs().format('YYYY-MM-DD'));
    return (
      <View style={styles.card}>
        <View style={styles.topRow}>
          <View style={{ flex: 1, minWidth: 0 }}>
            <Text style={styles.title} numberOfLines={1}>{item.offering_title}</Text>
            <Text style={styles.sub} numberOfLines={1}>
              {item.pro_name ?? '—'} · {dayjs(item.day).locale('fr').format('ddd D MMM')} ·{' '}
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
        {(item.conversation_id || cancellable) && (
          <View style={styles.actions}>
            {item.conversation_id ? (
              <PressableScale style={styles.link} onPress={() => router.push(`/(auth)/conversation/${item.conversation_id}`)} hitSlop={6}>
                <MessageCircle size={15} color={colors.textSecondary} strokeWidth={2.2} />
                <Text style={styles.linkText}>{t('booking.openChat', { defaultValue: 'Discuter' })}</Text>
              </PressableScale>
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

  return (
    <View style={styles.container}>
      <Stack.Screen options={{ title: t('booking.myBookings', { defaultValue: 'Mes réservations' }) }} />
      {isLoading ? (
        <View style={styles.center}><LogoSpinner size={36} /></View>
      ) : (
        <FlatList
          data={bookings ?? []}
          keyExtractor={(b) => b.id}
          renderItem={renderItem}
          contentContainerStyle={styles.list}
          ListEmptyComponent={
            <View style={styles.empty}>
              <View style={styles.emptyIc}><CalendarX2 size={30} color={colors.textMuted} strokeWidth={2} /></View>
              <Text style={styles.emptyTitle}>{t('booking.emptyTitle', { defaultValue: 'Aucune réservation' })}</Text>
              <Text style={styles.emptyBody}>
                {t('booking.emptyBody', { defaultValue: 'Réserve une sortie encadrée depuis la page d’un professionnel sur la carte.' })}
              </Text>
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
  card: {
    backgroundColor: colors.surface, borderRadius: radius.card, padding: spacing.md,
    marginBottom: spacing.sm + 2, gap: spacing.sm, ...shadows.card,
  },
  topRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  title: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '800', letterSpacing: -0.2 },
  sub: { color: colors.textSecondary, fontSize: fontSizes.sm - 1, marginTop: 2 },
  statusPill: { borderRadius: radius.full, paddingHorizontal: spacing.sm + 2, paddingVertical: 4 },
  statusText: { fontSize: fontSizes.xs, fontWeight: '700' },
  actions: { flexDirection: 'row', alignItems: 'center', gap: spacing.md },
  link: { flexDirection: 'row', alignItems: 'center', gap: 5 },
  linkText: { color: colors.textSecondary, fontSize: fontSizes.sm - 1, fontWeight: '600' },
  empty: { alignItems: 'center', paddingVertical: spacing.xl * 2, paddingHorizontal: spacing.lg, gap: spacing.sm },
  emptyIc: {
    width: 72, height: 72, borderRadius: radius.full, backgroundColor: colors.surfaceAlt,
    alignItems: 'center', justifyContent: 'center', marginBottom: spacing.xs,
  },
  emptyTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800', letterSpacing: -0.2 },
  emptyBody: { color: colors.textSecondary, fontSize: fontSizes.sm + 1, textAlign: 'center', lineHeight: 21, maxWidth: 280 },
});
