import { useMemo, useState } from 'react';
import { View, Text, ScrollView, StyleSheet, TextInput } from 'react-native';
import { Stack, useLocalSearchParams, useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import * as Burnt from 'burnt';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { Send, Minus, Plus } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing, radius, glow, shadows } from '@/constants/theme';
import { bookingService, type BookingPeriod } from '@/services/booking-service';
import { proOfferingService } from '@/services/pro-offering-service';
import { AvailabilityCalendar } from '@/components/availability-calendar';
import { PressableScale } from '@/components/pressable-scale';
import { LogoSpinner } from '@/components/logo-spinner';
import { getFriendlyError } from '@/utils/friendly-error';
import { SportIcon } from '@/components/sport-icon';

export default function BookOfferingScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const { offeringId } = useLocalSearchParams<{ offeringId: string }>();

  const { data: offering, isLoading: offeringLoading } = useQuery({
    queryKey: ['offering', offeringId],
    queryFn: () => proOfferingService.getById(offeringId ?? ''),
    enabled: !!offeringId,
  });

  const { data: slots, isLoading: slotsLoading } = useQuery({
    queryKey: ['pro-availability', offering?.pro_id],
    queryFn: () => bookingService.getProAvailability(offering?.pro_id ?? ''),
    enabled: !!offering?.pro_id,
  });

  const slotSet = useMemo(
    () => new Set((slots ?? []).map((s) => `${s.day}|${s.period}`)),
    [slots],
  );

  const [selected, setSelected] = useState<{ day: string; period: BookingPeriod } | null>(null);
  const [partySize, setPartySize] = useState(2);
  const [message, setMessage] = useState('');
  const [sending, setSending] = useState(false);

  const maxParty = Math.min(offering?.max_participants ?? 50, 50);

  const submit = async () => {
    if (!offeringId || !selected) {
      Burnt.toast({ title: t('booking.pickSlotFirst', { defaultValue: 'Choisis un créneau disponible' }) });
      return;
    }
    setSending(true);
    try {
      await bookingService.createBooking(offeringId, selected.day, selected.period, partySize, message.trim() || undefined);
      await queryClient.invalidateQueries({ queryKey: ['my-bookings'] });
      Burnt.toast({ title: t('booking.requestSent', { defaultValue: 'Demande envoyée au professionnel' }), preset: 'done' });
      router.replace('/(auth)/my-bookings');
    } catch (e) {
      Burnt.toast({ title: getFriendlyError(e, 'generic') });
    } finally {
      setSending(false);
    }
  };

  if (offeringLoading || !offering) {
    return (
      <View style={styles.center}>
        <Stack.Screen options={{ title: t('booking.bookTitle', { defaultValue: 'Réserver' }) }} />
        {offeringLoading ? <LogoSpinner size={36} /> : <Text style={styles.emptyText}>{t('booking.offeringGone', { defaultValue: 'Offre indisponible.' })}</Text>}
      </View>
    );
  }

  const periodText = selected
    ? `${dayjs(selected.day).locale('fr').format('ddd D MMM')} · ${selected.period === 'am'
        ? t('booking.am', { defaultValue: 'matin' })
        : t('booking.pm', { defaultValue: 'après-midi' })}`
    : t('booking.noSlotSelected', { defaultValue: 'Aucun créneau choisi' });

  return (
    <View style={styles.container}>
      <Stack.Screen options={{ title: t('booking.bookTitle', { defaultValue: 'Réserver' }) }} />
      <ScrollView contentContainerStyle={styles.scroll} showsVerticalScrollIndicator={false} keyboardShouldPersistTaps="handled">
        <View style={styles.head}>
          <SportIcon sportKey={offering.sport_key} size={26} />
          <View style={{ flex: 1, minWidth: 0 }}>
            <Text style={styles.headTitle} numberOfLines={1}>{offering.title}</Text>
            <Text style={styles.headSub} numberOfLines={1}>
              {offering.pro_name}
              {offering.price_eur != null
                ? ` · ${offering.price_eur} €${offering.price_unit === 'group' ? t('booking.perGroup', { defaultValue: '/groupe' }) : t('booking.perPerson', { defaultValue: '/pers.' })}`
                : ''}
            </Text>
          </View>
        </View>

        {slotsLoading ? (
          <View style={styles.centerBlock}><LogoSpinner size={30} /></View>
        ) : (slots ?? []).length === 0 ? (
          <View style={styles.emptyCard}>
            <Text style={styles.emptyText}>
              {t('booking.noAvailability', { defaultValue: 'Ce professionnel n’a pas encore ouvert de disponibilités. Contacte-le depuis sa page.' })}
            </Text>
          </View>
        ) : (
          <>
            <AvailabilityCalendar
              mode="pick"
              slotState={(day, period) => ({ available: slotSet.has(`${day}|${period}`) })}
              onPick={(day, period) => setSelected({ day, period })}
              selected={selected}
            />

            <View style={styles.pickRow}>
              <Text style={styles.fieldLabel}>{t('booking.slot', { defaultValue: 'Créneau' })}</Text>
              <Text style={[styles.slotText, selected && styles.slotTextOn]}>{periodText}</Text>
            </View>

            <View style={styles.pickRow}>
              <Text style={styles.fieldLabel}>{t('booking.partySize', { defaultValue: 'Personnes' })}</Text>
              <PressableScale style={styles.stepBtn} onPress={() => setPartySize((s) => Math.max(1, s - 1))}>
                <Minus size={18} color={colors.textPrimary} strokeWidth={2.4} />
              </PressableScale>
              <Text style={styles.stepVal}>{partySize}</Text>
              <PressableScale style={styles.stepBtn} onPress={() => setPartySize((s) => Math.min(maxParty, s + 1))}>
                <Plus size={18} color={colors.textPrimary} strokeWidth={2.4} />
              </PressableScale>
            </View>

            <Text style={styles.fieldLabel}>{t('booking.messageLabel', { defaultValue: 'Message (optionnel)' })}</Text>
            <TextInput
              style={styles.input}
              placeholder={t('booking.messagePlaceholder', { defaultValue: 'Niveau, questions, détails utiles…' })}
              placeholderTextColor={colors.textMuted}
              value={message}
              onChangeText={setMessage}
              multiline
              maxLength={500}
            />

            <PressableScale
              style={[styles.submit, glow(colors.cta), (!selected || sending) && styles.disabled]}
              onPress={submit}
              disabled={!selected || sending}
            >
              <Send size={15} color={colors.onCta} strokeWidth={2.4} />
              <Text style={styles.submitText}>
                {sending ? '…' : t('booking.submit', { defaultValue: 'Envoyer la demande' })}
              </Text>
            </PressableScale>
            <Text style={styles.finePrint}>
              {t('booking.payOnSite', { defaultValue: 'Le professionnel confirme ta réservation — le paiement se fait sur place.' })}
            </Text>
          </>
        )}
      </ScrollView>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  scroll: { padding: spacing.md, paddingBottom: spacing.xl + 24 },
  center: { flex: 1, backgroundColor: colors.background, alignItems: 'center', justifyContent: 'center' },
  centerBlock: { paddingVertical: spacing.xl, alignItems: 'center' },
  head: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 4,
    backgroundColor: colors.surface, borderRadius: radius.card, padding: spacing.md,
    marginBottom: spacing.md, ...shadows.card,
  },
  headTitle: { color: colors.textPrimary, fontSize: fontSizes.md + 1, fontWeight: '800', letterSpacing: -0.2 },
  headSub: { color: colors.textSecondary, fontSize: fontSizes.sm - 1, marginTop: 1 },
  emptyCard: { backgroundColor: colors.surface, borderRadius: radius.card, padding: spacing.lg, ...shadows.card },
  emptyText: { color: colors.textSecondary, fontSize: fontSizes.sm + 1, lineHeight: 21, textAlign: 'center' },
  pickRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, marginTop: spacing.md },
  fieldLabel: {
    color: colors.textMuted, fontSize: fontSizes.xs, fontWeight: '800',
    textTransform: 'uppercase', letterSpacing: 0.5, minWidth: 82, marginTop: spacing.xs,
  },
  slotText: { color: colors.textSecondary, fontSize: fontSizes.sm, flex: 1 },
  slotTextOn: { color: colors.textPrimary, fontWeight: '700' },
  stepBtn: {
    width: 36, height: 36, borderRadius: radius.full, backgroundColor: colors.surface,
    alignItems: 'center', justifyContent: 'center',
  },
  stepVal: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700', minWidth: 26, textAlign: 'center' },
  input: {
    backgroundColor: colors.surface, borderRadius: radius.card - 4,
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm + 3,
    color: colors.textPrimary, fontSize: fontSizes.sm + 1,
    minHeight: 72, textAlignVertical: 'top', marginTop: spacing.xs,
  },
  submit: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 7,
    backgroundColor: colors.cta, borderRadius: radius.full,
    paddingVertical: spacing.sm + 5, marginTop: spacing.lg,
  },
  submitText: { color: colors.onCta, fontSize: fontSizes.md, fontWeight: '700' },
  disabled: { opacity: 0.45 },
  finePrint: { color: colors.textMuted, fontSize: fontSizes.xs + 1, textAlign: 'center', marginTop: spacing.sm },
});
