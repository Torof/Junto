import { useMemo, useState } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet, Modal, TextInput, Platform } from 'react-native';
import { Stack } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import * as Burnt from 'burnt';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import DateTimePicker from '@react-native-community/datetimepicker';
import { Plus, Phone, Send, X } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useAuth } from '@/hooks/use-auth';
import { bookingService, type AgendaItem, type BookingPeriod } from '@/services/booking-service';
import { proOfferingService } from '@/services/pro-offering-service';
import { AvailabilityCalendar } from '@/components/availability-calendar';
import { UserAvatar } from '@/components/user-avatar';
import { LogoSpinner } from '@/components/logo-spinner';
import { getFriendlyError } from '@/utils/friendly-error';

type TFn = (key: string, options?: { defaultValue?: string }) => string;
const periodLabel = (p: BookingPeriod, t: TFn) =>
  p === 'am' ? t('booking.am', { defaultValue: 'matin' }) : t('booking.pm', { defaultValue: 'après-midi' });

export default function ProAgendaScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const { session } = useAuth();
  const userId = session?.user?.id ?? null;
  const queryClient = useQueryClient();

  const [monthStart, setMonthStart] = useState(() => dayjs().startOf('month').format('YYYY-MM-DD'));
  // Agenda window: the visible month, elargie d'un mois de chaque côté pour que
  // les compteurs restent justes en navigation rapide.
  const from = dayjs(monthStart).subtract(1, 'month').format('YYYY-MM-DD');
  const to = dayjs(monthStart).add(2, 'month').format('YYYY-MM-DD');

  const { data: agenda, isLoading } = useQuery({
    queryKey: ['pro-agenda', from, to],
    queryFn: () => bookingService.getAgenda(from, to),
  });

  const { data: offerings } = useQuery({
    queryKey: ['pro-offerings', userId],
    queryFn: () => proOfferingService.getByProId(userId as string),
    enabled: !!userId,
  });

  const invalidate = () => queryClient.invalidateQueries({ queryKey: ['pro-agenda'] });

  // Index (day|period) → slot state for the calendar.
  const slotIndex = useMemo(() => {
    const map = new Map<string, { available: boolean; accepted: number; pending: number }>();
    for (const it of agenda ?? []) {
      const key = `${it.day}|${it.period}`;
      const cur = map.get(key) ?? { available: false, accepted: 0, pending: 0 };
      if (it.kind === 'availability') cur.available = true;
      else if (it.status === 'accepted') cur.accepted += 1;
      else if (it.status === 'pending') cur.pending += 1;
      map.set(key, cur);
    }
    return map;
  }, [agenda]);

  const handleToggle = async (day: string, period: BookingPeriod, next: boolean) => {
    try {
      await bookingService.setAvailability(day, period, next);
      await invalidate();
    } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
  };

  const pendings = (agenda ?? []).filter((a) => a.kind === 'booking' && a.status === 'pending');
  const upcoming = (agenda ?? [])
    .filter((a) => a.kind === 'booking' && a.status === 'accepted' && a.day >= dayjs().format('YYYY-MM-DD'))
    .sort((a, b) => (a.day + a.period).localeCompare(b.day + b.period))
    .slice(0, 10);

  const handleAccept = async (b: AgendaItem) => {
    try {
      await bookingService.accept(b.id);
      Burnt.toast({ title: t('booking.acceptedToast', { defaultValue: 'Réservation confirmée' }), preset: 'done' });
      await invalidate();
    } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
  };
  const handleDecline = async (b: AgendaItem) => {
    try {
      await bookingService.decline(b.id);
      await invalidate();
    } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
  };
  const handleCancelPro = async (b: AgendaItem) => {
    try {
      await bookingService.cancelAsPro(b.id);
      Burnt.toast({ title: t('booking.cancelledToast', { defaultValue: 'Réservation annulée' }) });
      await invalidate();
    } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
  };

  // ----- Manual booking sheet -----
  const [manualOpen, setManualOpen] = useState(false);
  const [mOffering, setMOffering] = useState<string | null>(null);
  const [mDay, setMDay] = useState(() => dayjs().add(1, 'day').toDate());
  const [mShowPicker, setMShowPicker] = useState(false);
  const [mPeriod, setMPeriod] = useState<BookingPeriod>('am');
  const [mSize, setMSize] = useState(2);
  const [mName, setMName] = useState('');
  const [mPhone, setMPhone] = useState('');

  const submitManual = async () => {
    if (!mOffering || !mName.trim()) {
      Burnt.toast({ title: t('booking.manualMissing', { defaultValue: 'Choisis une offre et un nom' }) });
      return;
    }
    try {
      await bookingService.createManualBooking(
        mOffering, dayjs(mDay).format('YYYY-MM-DD'), mPeriod, mSize, mName.trim(), mPhone.trim() || undefined,
      );
      setManualOpen(false);
      setMName(''); setMPhone('');
      Burnt.toast({ title: t('booking.manualAdded', { defaultValue: 'Réservation ajoutée' }), preset: 'done' });
      await invalidate();
    } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
  };

  return (
    <View style={styles.container}>
      <Stack.Screen options={{ title: t('booking.agendaTitle', { defaultValue: 'Agenda' }) }} />
      <ScrollView contentContainerStyle={styles.scroll} showsVerticalScrollIndicator={false}>
        <AvailabilityCalendar
          mode="edit"
          slotState={(day, period) => slotIndex.get(`${day}|${period}`) ?? { available: false }}
          onToggle={handleToggle}
          onMonthChange={setMonthStart}
        />
        <Text style={styles.hint}>{t('booking.toggleHint', { defaultValue: 'Tape une demi-journée pour basculer dispo / indispo.' })}</Text>

        {isLoading ? <View style={styles.center}><LogoSpinner size={32} /></View> : (
          <>
            {pendings.length > 0 && (
              <>
                <Text style={styles.sectionLabel}>
                  {t('booking.requests', { defaultValue: 'Demandes' })} · {pendings.length}
                </Text>
                {pendings.map((b) => (
                  <View key={b.id} style={styles.reqCard}>
                    <View style={styles.rowTop}>
                      <UserAvatar name={b.client_name ?? '?'} avatarUrl={null} size={38} />
                      <View style={{ flex: 1, minWidth: 0 }}>
                        <Text style={styles.reqName}>
                          {b.client_name ?? '—'}
                          <Text style={styles.reqSize}>  · {b.party_size} pers.</Text>
                        </Text>
                        <Text style={styles.reqMeta} numberOfLines={1}>
                          {b.offering_title} — {dayjs(b.day).locale('fr').format('ddd D MMM')}, {periodLabel(b.period, t)}
                        </Text>
                        {b.message ? <Text style={styles.reqMsg} numberOfLines={2}>« {b.message} »</Text> : null}
                      </View>
                    </View>
                    <View style={styles.reqActs}>
                      <Pressable style={({ pressed }) => [styles.btnGhost, pressed && styles.pressed]} onPress={() => handleDecline(b)}>
                        <Text style={styles.btnGhostText}>{t('booking.decline', { defaultValue: 'Refuser' })}</Text>
                      </Pressable>
                      <Pressable style={({ pressed }) => [styles.btnPrimary, { flex: 1 }, pressed && styles.pressed]} onPress={() => handleAccept(b)}>
                        <Text style={styles.btnPrimaryText}>{t('booking.accept', { defaultValue: 'Accepter' })}</Text>
                      </Pressable>
                    </View>
                  </View>
                ))}
              </>
            )}

            <Text style={styles.sectionLabel}>{t('booking.upcoming', { defaultValue: 'À venir' })}</Text>
            {upcoming.length === 0 ? (
              <Text style={styles.empty}>{t('booking.noUpcoming', { defaultValue: 'Aucune réservation confirmée à venir.' })}</Text>
            ) : upcoming.map((b) => (
              <View key={b.id} style={styles.bkRow}>
                <View style={styles.bkPeriod}>
                  <Text style={styles.bkPeriodText}>{dayjs(b.day).locale('fr').format('D/M')} {b.period === 'am' ? 'AM' : 'PM'}</Text>
                </View>
                <View style={{ flex: 1, minWidth: 0 }}>
                  <Text style={styles.bkName} numberOfLines={1}>
                    {b.client_name ?? '—'} ({b.party_size}) · {b.offering_title}
                  </Text>
                  <Text style={styles.bkSub} numberOfLines={1}>
                    {b.is_manual
                      ? `${t('booking.manualTag', { defaultValue: 'manuel' })}${b.manual_phone ? ' · ' + b.manual_phone : ''}`
                      : t('booking.viaJunto', { defaultValue: 'via l’app' })}
                  </Text>
                </View>
                {b.is_manual && b.manual_phone ? <Phone size={15} color={colors.textMuted} strokeWidth={2.2} /> : null}
                <Pressable onPress={() => handleCancelPro(b)} hitSlop={8}>
                  <X size={16} color={colors.textMuted} strokeWidth={2.4} />
                </Pressable>
              </View>
            ))}
            <View style={{ height: 90 }} />
          </>
        )}
      </ScrollView>

      <Pressable style={({ pressed }) => [styles.fab, pressed && styles.pressed]} onPress={() => setManualOpen(true)}>
        <Plus size={17} color="#FFFFFF" strokeWidth={2.6} />
        <Text style={styles.fabText}>{t('booking.addManual', { defaultValue: 'Ajouter une résa' })}</Text>
      </Pressable>

      {/* Résa manuelle — client hors app */}
      <Modal visible={manualOpen} transparent animationType="slide" onRequestClose={() => setManualOpen(false)}>
        <Pressable style={styles.backdrop} onPress={() => setManualOpen(false)}>
          <Pressable style={styles.sheet} onPress={(e) => e.stopPropagation()}>
            <Text style={styles.sheetTitle}>{t('booking.manualTitle', { defaultValue: 'Ajouter une réservation' })}</Text>

            <Text style={styles.fieldLabel}>{t('booking.manualOffering', { defaultValue: 'Offre' })}</Text>
            <View style={styles.chipsWrap}>
              {(offerings ?? []).map((o) => (
                <Pressable key={o.id} style={[styles.chip, mOffering === o.id && styles.chipOn]} onPress={() => setMOffering(o.id)}>
                  <Text style={[styles.chipText, mOffering === o.id && styles.chipTextOn]} numberOfLines={1}>{o.title}</Text>
                </Pressable>
              ))}
            </View>

            <Text style={styles.fieldLabel}>{t('booking.manualWhen', { defaultValue: 'Date & créneau' })}</Text>
            <View style={styles.rowWrap}>
              <Pressable style={styles.chip} onPress={() => setMShowPicker(true)}>
                <Text style={styles.chipText}>{dayjs(mDay).locale('fr').format('ddd D MMM')}</Text>
              </Pressable>
              {(['am', 'pm'] as BookingPeriod[]).map((p) => (
                <Pressable key={p} style={[styles.chip, mPeriod === p && styles.chipOn]} onPress={() => setMPeriod(p)}>
                  <Text style={[styles.chipText, mPeriod === p && styles.chipTextOn]}>{periodLabel(p, t)}</Text>
                </Pressable>
              ))}
            </View>
            {mShowPicker && (
              <DateTimePicker
                value={mDay}
                mode="date"
                display={Platform.OS === 'ios' ? 'inline' : 'default'}
                minimumDate={new Date()}
                maximumDate={dayjs().add(6, 'month').toDate()}
                onChange={(_, d) => { setMShowPicker(false); if (d) setMDay(d); }}
              />
            )}

            <Text style={styles.fieldLabel}>{t('booking.manualWho', { defaultValue: 'Client' })}</Text>
            <TextInput
              style={styles.input}
              placeholder={t('booking.manualName', { defaultValue: 'Nom (ex. Famille Perrin)' })}
              placeholderTextColor={colors.textMuted}
              value={mName}
              onChangeText={setMName}
              maxLength={80}
            />
            <TextInput
              style={styles.input}
              placeholder={t('booking.manualPhone', { defaultValue: 'Téléphone (optionnel)' })}
              placeholderTextColor={colors.textMuted}
              value={mPhone}
              onChangeText={setMPhone}
              keyboardType="phone-pad"
              maxLength={30}
            />

            <View style={styles.rowWrap}>
              <Text style={styles.fieldLabel}>{t('booking.partySize', { defaultValue: 'Personnes' })}</Text>
              <Pressable style={styles.stepBtn} onPress={() => setMSize((s) => Math.max(1, s - 1))}><Text style={styles.stepBtnText}>−</Text></Pressable>
              <Text style={styles.stepVal}>{mSize}</Text>
              <Pressable style={styles.stepBtn} onPress={() => setMSize((s) => Math.min(50, s + 1))}><Text style={styles.stepBtnText}>+</Text></Pressable>
            </View>

            <Pressable style={({ pressed }) => [styles.btnPrimary, styles.btnBig, pressed && styles.pressed]} onPress={submitManual}>
              <Send size={15} color="#FFFFFF" strokeWidth={2.4} />
              <Text style={styles.btnPrimaryText}>{t('booking.manualSubmit', { defaultValue: 'Ajouter' })}</Text>
            </Pressable>
          </Pressable>
        </Pressable>
      </Modal>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  scroll: { padding: spacing.md },
  center: { paddingVertical: spacing.xl, alignItems: 'center' },
  hint: { color: colors.textMuted, fontSize: fontSizes.xs + 1, marginTop: spacing.xs + 2, marginHorizontal: 2 },
  sectionLabel: {
    color: colors.textMuted, fontSize: fontSizes.xs, fontWeight: '800',
    textTransform: 'uppercase', letterSpacing: 0.8, marginTop: spacing.lg, marginBottom: spacing.sm,
  },
  reqCard: { backgroundColor: colors.surface, borderRadius: 16, padding: spacing.md, marginBottom: spacing.sm + 2 },
  rowTop: { flexDirection: 'row', gap: spacing.sm + 2, alignItems: 'center' },
  reqName: { color: colors.textPrimary, fontSize: fontSizes.sm + 1, fontWeight: '800' },
  reqSize: { color: colors.textSecondary, fontWeight: '500', fontSize: fontSizes.sm },
  reqMeta: { color: colors.textPrimary, fontSize: fontSizes.sm - 1, marginTop: 2 },
  reqMsg: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, fontStyle: 'italic', marginTop: 3 },
  reqActs: { flexDirection: 'row', gap: spacing.sm, marginTop: spacing.sm + 2, alignItems: 'center' },
  btnGhost: { paddingVertical: spacing.sm + 1, paddingHorizontal: spacing.md, borderRadius: radius.full },
  btnGhostText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600' },
  btnPrimary: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6,
    backgroundColor: colors.cta, borderRadius: radius.full, paddingVertical: spacing.sm + 2, paddingHorizontal: spacing.md,
  },
  btnPrimaryText: { color: '#FFFFFF', fontSize: fontSizes.sm, fontWeight: '800' },
  btnBig: { marginTop: spacing.md, paddingVertical: spacing.sm + 4 },
  empty: { color: colors.textSecondary, fontSize: fontSizes.sm, marginBottom: spacing.sm },
  bkRow: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 2,
    backgroundColor: colors.surface, borderRadius: 14, padding: spacing.sm + 4, marginBottom: spacing.xs + 2,
  },
  bkPeriod: { backgroundColor: colors.cta + '22', borderRadius: 7, paddingHorizontal: 7, paddingVertical: 4 },
  bkPeriodText: { color: colors.cta, fontSize: fontSizes.xs - 1, fontWeight: '800' },
  bkName: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700' },
  bkSub: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, marginTop: 1 },
  fab: {
    position: 'absolute', right: spacing.md, bottom: spacing.lg,
    flexDirection: 'row', alignItems: 'center', gap: 6,
    backgroundColor: colors.cta, borderRadius: radius.full, paddingVertical: spacing.sm + 4, paddingHorizontal: spacing.md + 2,
    ...Platform.select({ ios: { shadowColor: colors.cta, shadowOffset: { width: 0, height: 5 }, shadowOpacity: 0.38, shadowRadius: 12 }, android: { elevation: 5 } }),
  },
  fabText: { color: '#FFFFFF', fontSize: fontSizes.sm, fontWeight: '800' },
  pressed: { opacity: 0.85, transform: [{ scale: 0.98 }] },
  backdrop: { flex: 1, backgroundColor: '#00000088', justifyContent: 'flex-end' },
  sheet: {
    backgroundColor: colors.background, borderTopLeftRadius: radius.xl, borderTopRightRadius: radius.xl,
    padding: spacing.lg, paddingBottom: spacing.xl,
  },
  sheetTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800', marginBottom: spacing.sm },
  fieldLabel: {
    color: colors.textMuted, fontSize: fontSizes.xs, fontWeight: '800',
    textTransform: 'uppercase', letterSpacing: 0.5, marginTop: spacing.md, marginBottom: spacing.xs + 2,
  },
  chipsWrap: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs + 2 },
  rowWrap: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, flexWrap: 'wrap' },
  chip: {
    backgroundColor: colors.surface, borderRadius: radius.full,
    paddingHorizontal: spacing.sm + 4, paddingVertical: 8, maxWidth: 220,
  },
  chipOn: { backgroundColor: colors.cta },
  chipText: { color: colors.textPrimary, fontSize: fontSizes.sm - 1, fontWeight: '600' },
  chipTextOn: { color: '#FFFFFF', fontWeight: '800' },
  input: {
    backgroundColor: colors.surface, borderRadius: 12, paddingHorizontal: spacing.md, paddingVertical: spacing.sm + 3,
    color: colors.textPrimary, fontSize: fontSizes.sm + 1, marginBottom: spacing.sm,
  },
  stepBtn: {
    width: 32, height: 32, borderRadius: 16, backgroundColor: colors.surface,
    alignItems: 'center', justifyContent: 'center',
  },
  stepBtnText: { color: colors.textSecondary, fontSize: fontSizes.lg, fontWeight: '600', marginTop: -2 },
  stepVal: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '800', minWidth: 24, textAlign: 'center' },
});
