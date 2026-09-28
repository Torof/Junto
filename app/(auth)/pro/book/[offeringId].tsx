import { useMemo, useState } from 'react';
import { View, Text, ScrollView, StyleSheet, TextInput } from 'react-native';
import { Stack, useLocalSearchParams, useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import * as Burnt from 'burnt';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { Send, Minus, Plus, CalendarDays, Lock } from 'lucide-react-native';
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
  const { offeringId, day: presetDay, period: presetPeriod } = useLocalSearchParams<{
    offeringId: string; day?: string; period?: string;
  }>();

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

  const maxParty = Math.min(offering?.max_participants ?? 50, 50);

  // Places restantes par créneau — INFORMATIF (la capacité ne bloque pas en
  // DB, le pro reste juge) : « Complet » grise le créneau côté client.
  const slotInfo = useMemo(() => {
    const map = new Map<string, { taken: number; free: number | null }>();
    for (const s of slots ?? []) {
      const free = offering?.max_participants != null
        ? Math.max(0, offering.max_participants - s.taken)
        : null;
      map.set(`${s.day}|${s.period}`, { taken: s.taken, free });
    }
    return map;
  }, [slots, offering?.max_participants]);

  const [selected, setSelected] = useState<{ day: string; period: BookingPeriod } | null>(() =>
    presetDay && (presetPeriod === 'am' || presetPeriod === 'pm')
      ? { day: presetDay, period: presetPeriod }
      : null,
  );
  const [partySize, setPartySize] = useState(2);
  const [message, setMessage] = useState('');
  const [sending, setSending] = useState(false);
  const [showCalendar, setShowCalendar] = useState(false);

  // Liste des prochains créneaux (maquette v2) : le calendrier passe en appui.
  const nextSlots = useMemo(
    () => [...(slots ?? [])].sort((a, b) => (a.day + a.period).localeCompare(b.day + b.period)).slice(0, 6),
    [slots],
  );

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

  const periodName = (p: BookingPeriod) =>
    p === 'am' ? t('booking.am', { defaultValue: 'matin' }) : t('booking.pm', { defaultValue: 'après-midi' });

  const freeLabel = (day: string, period: BookingPeriod): { text: string; full: boolean } => {
    const info = slotInfo.get(`${day}|${period}`);
    if (!info || info.free == null) {
      return info && info.taken > 0
        ? { text: t('booking.slotTaken', { defaultValue: '{{count}} pers. déjà inscrites', count: info.taken }), full: false }
        : { text: t('booking.slotFree', { defaultValue: 'Créneau libre' }), full: false };
    }
    if (info.free === 0) return { text: t('booking.slotFull', { defaultValue: 'Complet — {{max}}/{{max}}', max: offering.max_participants }), full: true };
    if (info.taken === 0) return { text: t('booking.slotAllFree', { defaultValue: '{{count}} places libres', count: info.free }), full: false };
    return { text: t('booking.slotPartial', { defaultValue: '{{taken}} prises · reste {{free}}', taken: info.taken, free: info.free }), full: false };
  };

  // Prix indicatif du récap.
  const estimate = offering.price_eur != null
    ? offering.price_unit === 'group' ? offering.price_eur : offering.price_eur * partySize
    : null;

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
            <Text style={styles.sectionLabel}>{t('booking.nextSlots', { defaultValue: 'Prochains créneaux' })}</Text>
            <View style={styles.slotCard}>
              {nextSlots.map((s, i) => {
                const isOn = selected?.day === s.day && selected?.period === s.period;
                const { text, full } = freeLabel(s.day, s.period);
                return (
                  <PressableScale
                    key={`${s.day}|${s.period}`}
                    style={[styles.slotRow, i > 0 && styles.slotSep, full && styles.slotFull]}
                    onPress={() => setSelected({ day: s.day, period: s.period })}
                    disabled={full}
                    accessibilityState={{ selected: isOn, disabled: full }}
                  >
                    <View style={[styles.radio, isOn && styles.radioOn]} />
                    <View style={{ flex: 1, minWidth: 0 }}>
                      <Text style={styles.slotDay}>{dayjs(s.day).locale('fr').format('ddd D MMMM')}</Text>
                      <Text style={[styles.slotCap, full && { color: colors.textMuted }]}>{text}</Text>
                    </View>
                    <View style={[styles.periodPill, full && styles.periodPillOff]}>
                      <Text style={[styles.periodPillText, full && { color: colors.textMuted }]}>{periodName(s.period)}</Text>
                    </View>
                  </PressableScale>
                );
              })}
              <PressableScale style={styles.calToggle} onPress={() => setShowCalendar((v) => !v)}>
                <CalendarDays size={15} color={colors.cta} strokeWidth={2.2} />
                <Text style={styles.calToggleText}>
                  {showCalendar
                    ? t('booking.hideCalendar', { defaultValue: 'Masquer le calendrier' })
                    : t('booking.pickOnCalendar', { defaultValue: 'Choisir sur le calendrier' })}
                </Text>
              </PressableScale>
            </View>

            {showCalendar && (
              <View style={{ marginTop: spacing.sm }}>
                <AvailabilityCalendar
                  mode="pick"
                  slotState={(day, period) => {
                    const info = slotInfo.get(`${day}|${period}`);
                    return { available: !!info && (info.free == null || info.free > 0) };
                  }}
                  onPick={(day, period) => setSelected({ day, period })}
                  selected={selected}
                />
              </View>
            )}

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

            <View style={styles.recap}>
              <View style={styles.recapLine}>
                <Text style={styles.recapKey}>{t('booking.recapOffering', { defaultValue: 'Sortie' })}</Text>
                <Text style={styles.recapVal} numberOfLines={1}>{offering.title}</Text>
              </View>
              <View style={styles.recapLine}>
                <Text style={styles.recapKey}>{t('booking.slot', { defaultValue: 'Créneau' })}</Text>
                <Text style={styles.recapVal}>
                  {selected
                    ? `${dayjs(selected.day).locale('fr').format('ddd D MMM')} · ${periodName(selected.period)}`
                    : t('booking.noSlotSelected', { defaultValue: 'Aucun créneau choisi' })}
                </Text>
              </View>
              <View style={styles.recapLine}>
                <Text style={styles.recapKey}>{t('booking.recapGroup', { defaultValue: 'Groupe' })}</Text>
                <Text style={styles.recapVal}>{partySize} {t('booking.people', { defaultValue: 'pers.' })}</Text>
              </View>
              {estimate != null && (
                <View style={styles.recapLine}>
                  <Text style={styles.recapKey}>{t('booking.recapPrice', { defaultValue: 'Prix indicatif' })}</Text>
                  <Text style={styles.recapVal}>{estimate} €</Text>
                </View>
              )}
            </View>
            <View style={styles.payNote}>
              <Lock size={13} color={colors.textMuted} strokeWidth={2.2} />
              <Text style={styles.finePrint}>
                {t('booking.payOnSite', { defaultValue: 'Le professionnel confirme ta réservation — le paiement se fait sur place.' })}
              </Text>
            </View>

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
  sectionLabel: {
    color: colors.textMuted, fontSize: fontSizes.xs, fontWeight: '800',
    textTransform: 'uppercase', letterSpacing: 0.8, marginBottom: spacing.sm,
  },
  slotCard: { backgroundColor: colors.surface, borderRadius: radius.card, paddingHorizontal: spacing.md, paddingVertical: spacing.xs, ...shadows.card },
  slotRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 2, paddingVertical: spacing.sm + 3 },
  slotSep: { borderTopWidth: 1, borderTopColor: colors.textMuted + '1F' },
  slotFull: { opacity: 0.55 },
  radio: { width: 20, height: 20, borderRadius: 10, borderWidth: 2, borderColor: colors.textMuted },
  radioOn: { borderColor: colors.cta, backgroundColor: colors.cta },
  slotDay: { color: colors.textPrimary, fontSize: fontSizes.sm + 1, fontWeight: '700', textTransform: 'capitalize' },
  slotCap: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, marginTop: 1 },
  periodPill: { backgroundColor: colors.cta + '1A', borderRadius: radius.full, paddingHorizontal: spacing.sm + 2, paddingVertical: 4 },
  periodPillOff: { backgroundColor: colors.textMuted + '22' },
  periodPillText: { color: colors.cta, fontSize: fontSizes.xs, fontWeight: '700' },
  calToggle: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6, paddingVertical: spacing.sm + 2 },
  calToggleText: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700' },
  pickRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, marginTop: spacing.md },
  fieldLabel: {
    color: colors.textMuted, fontSize: fontSizes.xs, fontWeight: '800',
    textTransform: 'uppercase', letterSpacing: 0.5, minWidth: 82, marginTop: spacing.xs,
  },
  stepBtn: {
    width: 36, height: 36, borderRadius: radius.full, backgroundColor: colors.surfaceAlt,
    alignItems: 'center', justifyContent: 'center',
  },
  stepVal: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700', minWidth: 26, textAlign: 'center' },
  input: {
    backgroundColor: colors.surfaceAlt, borderRadius: radius.card - 4,
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm + 3,
    color: colors.textPrimary, fontSize: fontSizes.sm + 1,
    minHeight: 72, textAlignVertical: 'top', marginTop: spacing.xs,
  },
  recap: { backgroundColor: colors.surfaceAlt, borderRadius: radius.card - 4, padding: spacing.md, marginTop: spacing.md },
  recapLine: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingVertical: 3, gap: spacing.md },
  recapKey: { color: colors.textSecondary, fontSize: fontSizes.sm - 1 },
  recapVal: { color: colors.textPrimary, fontSize: fontSizes.sm - 1, fontWeight: '700', flexShrink: 1 },
  payNote: { flexDirection: 'row', alignItems: 'flex-start', gap: 6, marginTop: spacing.sm, paddingHorizontal: 2 },
  submit: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 7,
    backgroundColor: colors.cta, borderRadius: radius.full,
    paddingVertical: spacing.sm + 5, marginTop: spacing.md,
  },
  submitText: { color: colors.onCta, fontSize: fontSizes.md, fontWeight: '700' },
  disabled: { opacity: 0.45 },
  finePrint: { flex: 1, color: colors.textMuted, fontSize: fontSizes.xs + 1, lineHeight: 17 },
});
