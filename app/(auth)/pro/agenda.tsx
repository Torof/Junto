import { useMemo, useState } from 'react';
import { View, Pressable, ScrollView, StyleSheet, Modal, Platform, Alert, RefreshControl } from 'react-native';
import { AppText, AppTextInput } from '@/components/app-text';
import Animated from 'react-native-reanimated';
import { useKeyboardDockPadding } from '@/hooks/use-keyboard-dock-padding';
import { Stack, useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import * as Burnt from 'burnt';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import DateTimePicker from '@react-native-community/datetimepicker';
import { Plus, Phone, Send, X, MessageCircle } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import { useAuth } from '@/hooks/use-auth';
import { bookingService, type AgendaItem, type BookingPeriod } from '@/services/booking-service';
import { proOfferingService } from '@/services/pro-offering-service';
import { AvailabilityCalendar } from '@/components/availability-calendar';
import { UserAvatar } from '@/components/user-avatar';
import { LogoSpinner } from '@/components/logo-spinner';
import { PressableScale } from '@/components/pressable-scale';
import { getFriendlyError } from '@/utils/friendly-error';
import { sportCategoryColor } from '@/utils/sport-category-color';

type TFn = (key: string, options?: { defaultValue?: string }) => string;
const periodLabel = (p: BookingPeriod, t: TFn) =>
  p === 'am' ? t('booking.am', { defaultValue: 'matin' }) : t('booking.pm', { defaultValue: 'après-midi' });

// Initials for the calendar half-day label ("Famille Perrin" → "FP").
// Fiche participant (00422) : "P. 43 · 178 cm · 72 kg" par entrée.
const formatEntry = (e: Record<string, unknown>): string => {
  const parts: string[] = [];
  if (typeof e.shoe_size === 'string' && e.shoe_size) parts.push(`P. ${e.shoe_size}`);
  if (typeof e.height === 'string' && e.height) parts.push(`${e.height} cm`);
  if (typeof e.weight === 'string' && e.weight) parts.push(`${e.weight} kg`);
  if (typeof e.age === 'string' && e.age) parts.push(`${e.age} ans`);
  if (typeof e.level === 'string' && e.level) parts.push(String(e.level));
  const custom = e.custom as Record<string, string> | undefined;
  if (custom) for (const [q, a] of Object.entries(custom)) if (a) parts.push(`${q} : ${a}`);
  return parts.join(' · ') || '—';
};

const initials = (name: string | null): string => {
  if (!name) return '?';
  const parts = name.trim().split(/\s+/).slice(0, 2);
  return parts.map((p) => (p[0] ?? '').toUpperCase()).join('');
};

export default function ProAgendaScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const { session } = useAuth();
  const userId = session?.user?.id ?? null;
  const queryClient = useQueryClient();
  // Manual-booking sheet rides the IME inset (never a KeyboardAvoidingView).
  const imePadding = useKeyboardDockPadding(0);

  const [monthStart, setMonthStart] = useState(() => dayjs().startOf('month').format('YYYY-MM-DD'));
  // Agenda window: the visible month, élargie d'un mois de chaque côté pour que
  // les compteurs restent justes en navigation rapide.
  const from = dayjs(monthStart).subtract(1, 'month').format('YYYY-MM-DD');
  const to = dayjs(monthStart).add(2, 'month').format('YYYY-MM-DD');

  const { data: agenda, isLoading, refetch, isRefetching } = useQuery({
    queryKey: ['pro-agenda', from, to],
    queryFn: () => bookingService.getAgenda(from, to),
  });

  const { data: offerings } = useQuery({
    queryKey: ['pro-offerings', userId],
    queryFn: () => proOfferingService.getByProId(userId as string),
    enabled: !!userId,
  });

  const invalidate = () => queryClient.invalidateQueries({ queryKey: ['pro-agenda'] });

  // Consulter ≠ éditer (maquette 2026-09-28) : lecture par défaut, édition explicite.
  const [editMode, setEditMode] = useState(false);
  const [sheetDay, setSheetDay] = useState<string | null>(null);

  // Index (day|period) → slot state for the calendar.
  const slotIndex = useMemo(() => {
    const map = new Map<string, {
      available: boolean; accepted: number; pending: number;
      label: string | null; sportCategory: string | null;
    }>();
    for (const it of agenda ?? []) {
      const key = `${it.day}|${it.period}`;
      const cur = map.get(key) ?? { available: false, accepted: 0, pending: 0, label: null, sportCategory: null };
      if (it.kind === 'availability') cur.available = true;
      else if (it.status === 'accepted') {
        cur.accepted += 1;
        cur.label = cur.accepted > 1 ? `+${cur.accepted}` : initials(it.client_name);
        cur.sportCategory = it.sport_category;
      } else if (it.status === 'pending') {
        cur.pending += 1;
        if (cur.accepted === 0) {
          cur.label = `${initials(it.client_name)}?`;
          cur.sportCategory = it.sport_category;
        }
      }
      map.set(key, cur);
    }
    return map;
  }, [agenda]);

  const slotState = (day: string, period: BookingPeriod) =>
    slotIndex.get(`${day}|${period}`) ?? { available: false };

  // Optimistic: the half-day flips under the finger, the RPC follows; on error
  // the previous window is restored (lot 2 pro, Scott 2026-10-15 — « le tap
  // répond tout de suite, la synchro suit »).
  const handleToggle = async (day: string, period: BookingPeriod, next: boolean) => {
    const key = ['pro-agenda', from, to] as const;
    const previous = queryClient.getQueryData<AgendaItem[]>(key);
    queryClient.setQueryData<AgendaItem[]>(key, (cur) => {
      const list = cur ?? [];
      if (next) {
        const stub = { kind: 'availability', day, period, id: `tmp-${day}-${period}` } as unknown as AgendaItem;
        return [...list, stub];
      }
      return list.filter((it) => !(it.kind === 'availability' && it.day === day && it.period === period));
    });
    try {
      await bookingService.setAvailability(day, period, next);
      await invalidate();
    } catch (e) {
      if (previous) queryClient.setQueryData(key, previous);
      Burnt.toast({ title: getFriendlyError(e, 'generic') });
    }
  };
  const [shortcutsOpen, setShortcutsOpen] = useState(false);

  // ----- Raccourcis d'ouverture (mode édition) -----
  const bulkOpen = async (slots: { day: string; period: BookingPeriod }[], successMsg: string) => {
    // N'ouvre que les créneaux futurs, pas déjà ouverts, sans réservation.
    const todo = slots.filter(({ day, period }) => {
      if (day < dayjs().format('YYYY-MM-DD')) return false;
      const st = slotIndex.get(`${day}|${period}`);
      return !st?.available && !(st && (st.accepted > 0 || st.pending > 0));
    });
    if (todo.length === 0) {
      Burnt.toast({ title: t('booking.bulkNothing', { defaultValue: 'Rien à ouvrir' }) });
      return;
    }
    try {
      await bookingService.setAvailabilityBulk(todo, true);
      Burnt.toast({ title: successMsg, preset: 'done' });
      await invalidate();
    } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
  };

  const monthDays = useMemo(() => {
    const start = dayjs(monthStart);
    return Array.from({ length: start.daysInMonth() }, (_, i) => start.date(i + 1));
  }, [monthStart]);

  const openWeekends = () => {
    const slots = monthDays
      .filter((d) => d.day() === 0 || d.day() === 6)
      .flatMap((d) => (['am', 'pm'] as BookingPeriod[]).map((period) => ({ day: d.format('YYYY-MM-DD'), period })));
    void bulkOpen(slots, t('booking.bulkWeekendsDone', { defaultValue: 'Week-ends ouverts' }));
  };

  const openWholeMonth = () => {
    const slots = monthDays
      .flatMap((d) => (['am', 'pm'] as BookingPeriod[]).map((period) => ({ day: d.format('YYYY-MM-DD'), period })));
    void bulkOpen(slots, t('booking.bulkMonthDone', { defaultValue: 'Mois ouvert' }));
  };

  // « Copier la semaine passée » : reprend le motif hebdo (jour de semaine ×
  // période) des 7 derniers jours — dispos ET jours travaillés (résas) — et
  // l'applique aux 4 prochaines semaines.
  const copyLastWeek = () => {
    const pattern = new Set<string>(); // 'dow|period'
    for (const it of agenda ?? []) {
      const d = dayjs(it.day);
      if (d.isBefore(dayjs().subtract(7, 'day'), 'day') || !d.isBefore(dayjs(), 'day')) continue;
      if (it.kind === 'availability' || it.status === 'accepted') pattern.add(`${d.day()}|${it.period}`);
    }
    if (pattern.size === 0) {
      Burnt.toast({ title: t('booking.bulkNoPattern', { defaultValue: 'Aucune dispo la semaine passée' }) });
      return;
    }
    const slots: { day: string; period: BookingPeriod }[] = [];
    for (let i = 0; i < 28; i++) {
      const d = dayjs().add(i, 'day');
      for (const period of ['am', 'pm'] as BookingPeriod[]) {
        if (pattern.has(`${d.day()}|${period}`)) slots.push({ day: d.format('YYYY-MM-DD'), period });
      }
    }
    void bulkOpen(slots, t('booking.bulkCopyDone', { defaultValue: 'Semaine type appliquée (4 semaines)' }));
  };

  const closeMonth = () => {
    const slots = monthDays
      .flatMap((d) => (['am', 'pm'] as BookingPeriod[]).map((period) => ({ day: d.format('YYYY-MM-DD'), period })))
      .filter(({ day, period }) => {
        if (day < dayjs().format('YYYY-MM-DD')) return false;
        const st = slotIndex.get(`${day}|${period}`);
        return !!st?.available && !(st.accepted > 0 || st.pending > 0);
      });
    if (slots.length === 0) {
      Burnt.toast({ title: t('booking.bulkNothingClose', { defaultValue: 'Rien à fermer' }) });
      return;
    }
    Alert.alert(
      t('booking.closeMonthTitle', { defaultValue: 'Fermer le mois ?' }),
      t('booking.closeMonthBody', { defaultValue: 'Tous les créneaux ouverts sans réservation seront fermés. Les réservations existantes ne bougent pas.' }),
      [
        { text: t('activity.no', { defaultValue: 'Non' }), style: 'cancel' },
        {
          text: t('activity.yes', { defaultValue: 'Oui' }),
          style: 'destructive',
          onPress: async () => {
            try {
              await bookingService.setAvailabilityBulk(slots, false);
              await invalidate();
            } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
          },
        },
      ],
    );
  };

  // ----- Demandes / à venir -----
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
  const handleCancelPro = (b: AgendaItem) => {
    Alert.alert(
      t('booking.cancelProConfirmTitle', { defaultValue: 'Annuler cette réservation ?' }),
      t('booking.cancelProConfirmBody', { defaultValue: 'Le client sera prévenu. Cette action est définitive.' }),
      [
        { text: t('activity.no', { defaultValue: 'Non' }), style: 'cancel' },
        {
          text: t('activity.yes', { defaultValue: 'Oui' }),
          style: 'destructive',
          onPress: async () => {
            try {
              await bookingService.cancelAsPro(b.id);
              Burnt.toast({ title: t('booking.cancelledToast', { defaultValue: 'Réservation annulée' }) });
              await invalidate();
            } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
          },
        },
      ],
    );
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

  const openManualSheet = (presetDay?: string, presetPeriod?: BookingPeriod) => {
    if (presetDay) setMDay(dayjs(presetDay).toDate());
    if (presetPeriod) setMPeriod(presetPeriod);
    setSheetDay(null);
    setManualOpen(true);
  };

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

  // ----- Fiche jour (mode lecture) -----
  const dayItems = (agenda ?? []).filter((a) => a.day === sheetDay);
  const dayBookings = (period: BookingPeriod) =>
    dayItems.filter((a) => a.kind === 'booking' && a.period === period && (a.status === 'accepted' || a.status === 'pending'));
  const dayOpen = (period: BookingPeriod) =>
    dayItems.some((a) => a.kind === 'availability' && a.period === period);
  const sheetIsPast = !!sheetDay && sheetDay < dayjs().format('YYYY-MM-DD');

  return (
    <View style={styles.container}>
      <Stack.Screen
        options={{
          title: t('booking.agendaTitle', { defaultValue: 'Agenda' }),
          // Manual booking lives in the header (was a floating button that sat
          // on the calendar's last row and the legend — lot 2 pro).
          headerRight: () => (
            <PressableScale onPress={() => openManualSheet()} hitSlop={8} style={styles.headerBtn} accessibilityLabel={t('booking.addManual', { defaultValue: 'Ajouter une résa' })}>
              <Plus size={14} color={colors.textPrimary} strokeWidth={2.6} />
              <AppText style={styles.headerBtnText}>{t('booking.addManualShort', { defaultValue: 'Résa' })}</AppText>
            </PressableScale>
          ),
        }}
      />
      <ScrollView
        contentContainerStyle={styles.scroll}
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={isRefetching && !isLoading} onRefresh={() => refetch()} tintColor={colors.cta} colors={[colors.cta]} />}
      >
        {/* Consulter ≠ modifier : a visible segmented control instead of a
            header toggle nobody found (audit 2026-10-08). */}
        <View style={styles.segmented}>
          <Pressable style={[styles.segment, !editMode && styles.segmentOn]} onPress={() => setEditMode(false)}>
            <AppText style={[styles.segmentText, !editMode && styles.segmentTextOn]}>{t('booking.modeView', { defaultValue: 'Consulter' })}</AppText>
          </Pressable>
          <Pressable style={[styles.segment, editMode && styles.segmentOn]} onPress={() => setEditMode(true)}>
            <AppText style={[styles.segmentText, editMode && styles.segmentTextOn]}>{t('booking.modeEdit', { defaultValue: 'Modifier mes dispos' })}</AppText>
          </Pressable>
        </View>

        {editMode && (
          <View style={styles.editBanner}>
            <AppText style={styles.editBannerText}>
              {t('booking.editHint', { defaultValue: 'Tape une demi-journée pour l’ouvrir ou la fermer. Les réservations ne bougent pas.' })}
            </AppText>
            <PressableScale style={styles.shortcutsBtn} onPress={() => setShortcutsOpen(true)}>
              <AppText style={styles.shortcutsBtnText}>{t('booking.shortcuts', { defaultValue: 'Raccourcis' })}</AppText>
            </PressableScale>
          </View>
        )}

        <AvailabilityCalendar
          mode={editMode ? 'edit' : 'view'}
          slotState={slotState}
          onToggle={handleToggle}
          onDayPress={(day) => setSheetDay(day)}
          onMonthChange={setMonthStart}
          selectedDay={sheetDay}
        />

        {!editMode && (
          <AppText style={styles.hint}>{t('booking.viewHint', { defaultValue: 'Tape un jour pour voir qui vient et gérer ses créneaux.' })}</AppText>
        )}

        {isLoading ? <View style={styles.center}><LogoSpinner size={32} /></View> : (
          <>
            {pendings.length > 0 && (
              <>
                <AppText style={styles.sectionLabel}>
                  {t('booking.requests', { defaultValue: 'Demandes' })} · {pendings.length}
                </AppText>
                {pendings.map((b) => (
                  <View key={b.id} style={styles.reqCard}>
                    <PressableScale
                      style={styles.rowTop}
                      onPress={() => b.client_id && router.push(`/(auth)/profile/${b.client_id}`)}
                      disabled={!b.client_id}
                    >
                      <UserAvatar name={b.client_name ?? '?'} avatarUrl={null} size={38} />
                      <View style={{ flex: 1, minWidth: 0 }}>
                        <AppText style={styles.reqName}>
                          {b.client_name ?? '—'}
                          <AppText style={styles.reqSize}>  · {b.party_size} pers.</AppText>
                        </AppText>
                        <AppText style={[styles.reqMeta, { color: sportCategoryColor(b.sport_category, colors.textPrimary) }]} numberOfLines={1}>
                          {b.offering_title} — {dayjs(b.day).format('ddd D MMM')}, {periodLabel(b.period, t)}
                        </AppText>
                        {b.message ? <AppText style={styles.reqMsg} numberOfLines={2}>« {b.message} »</AppText> : null}
                      </View>
                    </PressableScale>
                    <View style={styles.reqActs}>
                      <Pressable style={({ pressed }) => [styles.btnGhost, pressed && styles.pressed]} onPress={() => handleDecline(b)}>
                        <AppText style={styles.btnGhostText}>{t('booking.decline', { defaultValue: 'Refuser' })}</AppText>
                      </Pressable>
                      <Pressable style={({ pressed }) => [styles.btnPrimary, { flex: 1 }, pressed && styles.pressed]} onPress={() => handleAccept(b)}>
                        <AppText style={styles.btnPrimaryText}>{t('booking.accept', { defaultValue: 'Accepter' })}</AppText>
                      </Pressable>
                    </View>
                  </View>
                ))}
              </>
            )}

            <AppText style={styles.sectionLabel}>{t('booking.upcoming', { defaultValue: 'À venir' })}</AppText>
            {upcoming.length === 0 ? (
              <AppText style={styles.empty}>{t('booking.noUpcoming', { defaultValue: 'Aucune réservation confirmée à venir.' })}</AppText>
            ) : upcoming.map((b) => (
              <Pressable key={b.id} style={({ pressed }) => [styles.bkRow, pressed && styles.pressed]} onPress={() => setSheetDay(b.day)}>
                <View style={[styles.bkPeriod, { backgroundColor: sportCategoryColor(b.sport_category, colors.cta) + '22' }]}>
                  <AppText style={[styles.bkPeriodText, { color: sportCategoryColor(b.sport_category, colors.cta) }]}>
                    {dayjs(b.day).format('D/M')} {b.period === 'am' ? 'AM' : 'PM'}
                  </AppText>
                </View>
                <View style={{ flex: 1, minWidth: 0 }}>
                  <AppText style={styles.bkName} numberOfLines={1}>
                    {b.client_name ?? '—'} ({b.party_size}) · {b.offering_title}
                  </AppText>
                  <AppText style={styles.bkSub} numberOfLines={1}>
                    {b.is_manual
                      ? `${t('booking.manualTag', { defaultValue: 'manuel' })}${b.manual_phone ? ' · ' + b.manual_phone : ''}`
                      : t('booking.viaJunto', { defaultValue: 'via l’app' })}
                  </AppText>
                </View>
                {b.is_manual && b.manual_phone ? <Phone size={15} color={colors.textMuted} strokeWidth={2.2} /> : null}
              </Pressable>
            ))}
            <View style={{ height: spacing.lg }} />
          </>
        )}
      </ScrollView>

      {/* Raccourcis d'ouverture — derrière un bouton (lot 2 pro) : la rangée
          de puces ne tenait plus avec des demi-journées de 44 pt. */}
      <Modal visible={shortcutsOpen} transparent animationType="slide" onRequestClose={() => setShortcutsOpen(false)}>
        <Pressable style={styles.backdrop} onPress={() => setShortcutsOpen(false)}>
          <Pressable style={styles.sheet} onPress={(e) => e.stopPropagation()}>
            <View style={styles.grab} />
            <AppText style={styles.sheetTitle}>{t('booking.shortcuts', { defaultValue: 'Raccourcis' })}</AppText>
            <AppText style={styles.hint}>{t('booking.shortcutsHint', { defaultValue: 'Sur le mois affiché. Les créneaux déjà réservés ne bougent pas.' })}</AppText>
            {([
              [t('booking.bulkWeekends', { defaultValue: 'Ouvrir les week-ends' }), openWeekends, false],
              [t('booking.bulkMonth', { defaultValue: 'Ouvrir tout le mois' }), openWholeMonth, false],
              [t('booking.bulkCopy', { defaultValue: 'Copier la semaine passée' }), copyLastWeek, false],
              [t('booking.bulkClose', { defaultValue: 'Tout fermer' }), closeMonth, true],
            ] as const).map(([label, run, danger]) => (
              <PressableScale key={label} style={styles.shortcutRow} onPress={() => { setShortcutsOpen(false); run(); }}>
                <AppText style={[styles.shortcutRowText, danger && { color: colors.error }]}>{label}</AppText>
              </PressableScale>
            ))}
          </Pressable>
        </Pressable>
      </Modal>

      {/* Fiche jour — qui vient, état des créneaux, actions contextuelles */}
      <Modal visible={!!sheetDay} transparent animationType="slide" onRequestClose={() => setSheetDay(null)}>
        <Pressable style={styles.backdrop} onPress={() => setSheetDay(null)}>
          <Pressable style={styles.sheet} onPress={(e) => e.stopPropagation()}>
            <View style={styles.grab} />
            <AppText style={styles.sheetTitle}>
              {sheetDay ? dayjs(sheetDay).format('dddd D MMMM') : ''}
            </AppText>

            {(['am', 'pm'] as BookingPeriod[]).map((period) => {
              const bks = dayBookings(period);
              const open = dayOpen(period);
              return (
                <View key={period} style={styles.slotBlock}>
                  <View style={styles.slotHead}>
                    <AppText style={styles.slotLabel}>{periodLabel(period, t).toUpperCase()}</AppText>
                    {bks.length === 0 && (
                      <View style={[styles.statePill, { backgroundColor: open ? colors.cta + '1A' : colors.textMuted + '22' }]}>
                        <AppText style={[styles.statePillText, { color: open ? colors.cta : colors.textMuted }]}>
                          {open ? t('booking.slotOpen', { defaultValue: 'Ouvert' }) : t('booking.slotClosed', { defaultValue: 'Fermé' })}
                        </AppText>
                      </View>
                    )}
                    {!sheetIsPast && bks.length === 0 && (
                      <PressableScale hitSlop={6} onPress={() => sheetDay && handleToggle(sheetDay, period, !open)}>
                        <AppText style={styles.slotToggle}>
                          {open ? t('booking.closeSlot', { defaultValue: 'Fermer' }) : t('booking.openSlot', { defaultValue: 'Ouvrir' })}
                        </AppText>
                      </PressableScale>
                    )}
                  </View>
                  {bks.map((b) => (
                    <View key={b.id} style={styles.sheetBk}>
                      <View style={[styles.sportDot, { backgroundColor: sportCategoryColor(b.sport_category, colors.cta) }]} />
                      <View style={{ flex: 1, minWidth: 0 }}>
                        <AppText style={styles.sheetBkName} numberOfLines={1}>
                          {b.client_name ?? '—'} · {b.party_size} pers.
                          {b.status === 'pending' ? `  (${t('booking.status.pending', { defaultValue: 'En attente' }).toLowerCase()})` : ''}
                        </AppText>
                        <AppText style={styles.sheetBkSub} numberOfLines={1}>
                          {b.offering_title}
                          {b.is_manual
                            ? ` · ${t('booking.manualTag', { defaultValue: 'manuel' })}${b.manual_phone ? ' · ' + b.manual_phone : ''}`
                            : ` · ${t('booking.viaJunto', { defaultValue: 'via l’app' })}`}
                        </AppText>
                        {b.status === 'accepted'
                          && ((b.participant_fields?.std?.length ?? 0) + (b.participant_fields?.custom?.length ?? 0)) > 0 ? (
                          <View style={styles.pInfoBlock}>
                            {(b.participant_info ?? []).map((e, i) => (
                              <AppText key={i} style={styles.pInfoLine} numberOfLines={2}>
                                <AppText style={styles.pInfoNum}>{i + 1}  </AppText>{formatEntry(e)}
                              </AppText>
                            ))}
                            {(b.participant_info?.length ?? 0) < (b.party_size ?? 0) ? (
                              <AppText style={[styles.pInfoLine, { color: colors.warning }]}>
                                {t('booking.formMissing', {
                                  defaultValue: '{{count}} fiche(s) manquante(s)',
                                  count: (b.party_size ?? 0) - (b.participant_info?.length ?? 0),
                                })}
                              </AppText>
                            ) : null}
                          </View>
                        ) : null}
                      </View>
                      {!b.is_manual && b.client_id ? (
                        <PressableScale hitSlop={8} onPress={() => { setSheetDay(null); router.push(`/(auth)/profile/${b.client_id}`); }}>
                          <MessageCircle size={17} color={colors.textSecondary} strokeWidth={2.2} />
                        </PressableScale>
                      ) : null}
                      {b.status === 'accepted' && !sheetIsPast ? (
                        <PressableScale hitSlop={8} onPress={() => handleCancelPro(b)}>
                          <X size={17} color={colors.textMuted} strokeWidth={2.4} />
                        </PressableScale>
                      ) : null}
                    </View>
                  ))}
                </View>
              );
            })}

            {!sheetIsPast && (
              <Pressable
                style={({ pressed }) => [styles.btnPrimary, styles.btnBig, pressed && styles.pressed]}
                onPress={() => sheetDay && openManualSheet(sheetDay, dayOpen('am') || dayBookings('am').length === 0 ? 'am' : 'pm')}
              >
                <Plus size={15} color={colors.onCta} strokeWidth={2.4} />
                <AppText style={styles.btnPrimaryText}>{t('booking.addManualHere', { defaultValue: 'Ajouter une résa ce jour' })}</AppText>
              </Pressable>
            )}
          </Pressable>
        </Pressable>
      </Modal>

      {/* Résa manuelle — client hors app */}
      <Modal visible={manualOpen} transparent animationType="slide" onRequestClose={() => setManualOpen(false)}>
        <Pressable style={styles.backdrop} onPress={() => setManualOpen(false)}>
          {/* The sheet rides the IME inset (same pattern as the report modal) —
              the keyboard used to cover Nom / Téléphone / Ajouter. */}
          <Animated.View style={imePadding}>
          <Pressable style={styles.sheet} onPress={(e) => e.stopPropagation()}>
            <AppText style={styles.sheetTitle}>{t('booking.manualTitle', { defaultValue: 'Ajouter une réservation' })}</AppText>

            <AppText style={styles.fieldLabel}>{t('booking.manualOffering', { defaultValue: 'Offre' })}</AppText>
            <View style={styles.chipsWrap}>
              {(offerings ?? []).map((o) => (
                <Pressable key={o.id} style={[styles.chip, mOffering === o.id && styles.chipOn]} onPress={() => setMOffering(o.id)}>
                  <AppText style={[styles.chipText, mOffering === o.id && styles.chipTextOn]} numberOfLines={1}>{o.title}</AppText>
                </Pressable>
              ))}
            </View>

            <AppText style={styles.fieldLabel}>{t('booking.manualWhen', { defaultValue: 'Date & créneau' })}</AppText>
            <View style={styles.rowWrap}>
              <Pressable style={styles.chip} onPress={() => setMShowPicker(true)}>
                <AppText style={styles.chipText}>{dayjs(mDay).format('ddd D MMM')}</AppText>
              </Pressable>
              {(['am', 'pm'] as BookingPeriod[]).map((p) => (
                <Pressable key={p} style={[styles.chip, mPeriod === p && styles.chipOn]} onPress={() => setMPeriod(p)}>
                  <AppText style={[styles.chipText, mPeriod === p && styles.chipTextOn]}>{periodLabel(p, t)}</AppText>
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

            <AppText style={styles.fieldLabel}>{t('booking.manualWho', { defaultValue: 'Client' })}</AppText>
            <AppTextInput
              style={styles.input}
              placeholder={t('booking.manualName', { defaultValue: 'Nom (ex. Famille Perrin)' })}
              placeholderTextColor={colors.textMuted}
              value={mName}
              onChangeText={setMName}
              maxLength={80}
            />
            <AppTextInput
              style={styles.input}
              placeholder={t('booking.manualPhone', { defaultValue: 'Téléphone (optionnel)' })}
              placeholderTextColor={colors.textMuted}
              value={mPhone}
              onChangeText={setMPhone}
              keyboardType="phone-pad"
              maxLength={30}
            />

            <View style={styles.rowWrap}>
              <AppText style={styles.fieldLabel}>{t('booking.partySize', { defaultValue: 'Personnes' })}</AppText>
              <Pressable style={styles.stepBtn} onPress={() => setMSize((s) => Math.max(1, s - 1))}><AppText style={styles.stepBtnText}>−</AppText></Pressable>
              <AppText style={styles.stepVal}>{mSize}</AppText>
              <Pressable style={styles.stepBtn} onPress={() => setMSize((s) => Math.min(50, s + 1))}><AppText style={styles.stepBtnText}>+</AppText></Pressable>
            </View>

            <Pressable style={({ pressed }) => [styles.btnPrimary, styles.btnBig, pressed && styles.pressed]} onPress={submitManual}>
              <Send size={15} color={colors.onCta} strokeWidth={2.4} />
              <AppText style={styles.btnPrimaryText}>{t('booking.manualSubmit', { defaultValue: 'Ajouter' })}</AppText>
            </Pressable>
          </Pressable>
          </Animated.View>
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
  headerBtn: {
    flexDirection: 'row', alignItems: 'center', gap: 4,
    backgroundColor: colors.surfaceAlt, borderRadius: radius.full,
    paddingHorizontal: spacing.sm + 4, paddingVertical: 7,
  },
  headerBtnText: { color: colors.textPrimary, fontSize: fontSizes.sm - 1, fontWeight: '700' },
  segmented: {
    flexDirection: 'row', backgroundColor: colors.surfaceAlt, borderRadius: radius.full,
    padding: 4, marginBottom: spacing.sm + 2,
  },
  segment: { flex: 1, alignItems: 'center', justifyContent: 'center', borderRadius: radius.full, paddingVertical: spacing.sm + 2 },
  segmentOn: { backgroundColor: colors.surface, ...shadows.card },
  segmentText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '700' },
  segmentTextOn: { color: colors.textPrimary },
  editBanner: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm,
    backgroundColor: colors.cta + '1F', borderRadius: radius.card - 4,
    paddingVertical: spacing.sm + 2, paddingHorizontal: spacing.sm + 4,
    marginBottom: spacing.sm + 2,
  },
  editBannerText: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.sm - 1, fontWeight: '500', lineHeight: 18 },
  shortcutsBtn: { backgroundColor: colors.surface, borderRadius: radius.full, paddingHorizontal: spacing.sm + 4, paddingVertical: 7 },
  shortcutsBtnText: { color: colors.cta, fontSize: fontSizes.xs + 1, fontWeight: '700' },
  shortcutRow: { paddingVertical: spacing.sm + 6, borderTopWidth: 1, borderTopColor: colors.line },
  shortcutRowText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '600' },
  sectionLabel: {
    color: colors.textMuted, fontSize: fontSizes.xs, fontWeight: '800',
    textTransform: 'uppercase', letterSpacing: 0.8, marginTop: spacing.lg, marginBottom: spacing.sm,
  },
  reqCard: { borderWidth: 1, borderColor: colors.lineStrong, backgroundColor: colors.surface, borderRadius: radius.card, padding: spacing.md, marginBottom: spacing.sm + 2, ...shadows.card },
  rowTop: { flexDirection: 'row', gap: spacing.sm + 2, alignItems: 'center' },
  reqName: { color: colors.textPrimary, fontSize: fontSizes.sm + 1, fontWeight: '700' },
  reqSize: { color: colors.textSecondary, fontWeight: '500', fontSize: fontSizes.sm },
  reqMeta: { fontSize: fontSizes.sm - 1, marginTop: 2, fontWeight: '600' },
  reqMsg: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, fontStyle: 'italic', marginTop: 3 },
  reqActs: { flexDirection: 'row', gap: spacing.sm, marginTop: spacing.sm + 2, alignItems: 'center' },
  btnGhost: { paddingVertical: spacing.sm + 1, paddingHorizontal: spacing.md, borderRadius: radius.full },
  btnGhostText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600' },
  btnPrimary: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6,
    backgroundColor: colors.cta, borderRadius: radius.full, paddingVertical: spacing.sm + 2, paddingHorizontal: spacing.md,
  },
  btnPrimaryText: { color: colors.onCta, fontSize: fontSizes.sm, fontWeight: '700' },
  btnBig: { marginTop: spacing.md, paddingVertical: spacing.sm + 4 },
  empty: { color: colors.textSecondary, fontSize: fontSizes.sm, marginBottom: spacing.sm },
  bkRow: { borderWidth: 1, borderColor: colors.lineStrong,
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 2,
    backgroundColor: colors.surface, borderRadius: radius.card, padding: spacing.sm + 4, marginBottom: spacing.xs + 2,
    ...shadows.card,
  },
  bkPeriod: { borderRadius: 7, paddingHorizontal: 7, paddingVertical: 4 },
  bkPeriodText: { fontSize: fontSizes.xs - 1, fontWeight: '700' },
  bkName: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700' },
  bkSub: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, marginTop: 1 },
  pressed: { opacity: 0.85, transform: [{ scale: 0.98 }] },
  backdrop: { flex: 1, backgroundColor: colors.overlay, justifyContent: 'flex-end' },
  sheet: {
    backgroundColor: colors.background, borderTopLeftRadius: radius.xl, borderTopRightRadius: radius.xl,
    padding: spacing.lg, paddingBottom: spacing.xl,
  },
  grab: {
    width: 38, height: 4, borderRadius: 2, backgroundColor: colors.textMuted,
    opacity: 0.5, alignSelf: 'center', marginBottom: spacing.sm + 2,
  },
  sheetTitle: {
    color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800',
    marginBottom: spacing.sm, textTransform: 'capitalize',
  },
  slotBlock: { paddingVertical: spacing.sm, borderTopWidth: 1, borderTopColor: colors.textMuted + '22' },
  slotHead: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  slotLabel: { color: colors.textPrimary, fontSize: fontSizes.xs, fontWeight: '800', letterSpacing: 0.6, width: 74 },
  statePill: { borderRadius: radius.full, paddingHorizontal: spacing.sm + 2, paddingVertical: 4 },
  statePillText: { fontSize: fontSizes.xs, fontWeight: '800' },
  slotToggle: { color: colors.cta, fontSize: fontSizes.sm - 1, fontWeight: '700', marginLeft: 'auto' },
  sheetBk: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 2, paddingVertical: spacing.sm },
  sportDot: { width: 10, height: 10, borderRadius: 5 },
  sheetBkName: { color: colors.textPrimary, fontSize: fontSizes.sm + 1, fontWeight: '700' },
  sheetBkSub: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, marginTop: 1 },
  pInfoBlock: { marginTop: 4, gap: 2 },
  pInfoLine: { color: colors.textSecondary, fontSize: fontSizes.xs + 1 },
  pInfoNum: { color: colors.textMuted, fontWeight: '800' },
  fieldLabel: {
    color: colors.textMuted, fontSize: fontSizes.xs, fontWeight: '800',
    textTransform: 'uppercase', letterSpacing: 0.5, marginTop: spacing.md, marginBottom: spacing.xs + 2,
  },
  chipsWrap: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs + 2 },
  rowWrap: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, flexWrap: 'wrap' },
  chip: { borderWidth: 1, borderColor: colors.lineStrong,
    backgroundColor: colors.surfaceAlt, borderRadius: radius.full,
    paddingHorizontal: spacing.sm + 4, paddingVertical: 8, maxWidth: 220,
  },
  chipOn: { backgroundColor: colors.cta },
  chipText: { color: colors.textPrimary, fontSize: fontSizes.sm - 1, fontWeight: '600' },
  chipTextOn: { color: colors.onCta, fontWeight: '700' },
  input: { borderWidth: 1, borderColor: colors.lineStrong,
    backgroundColor: colors.surfaceAlt, borderRadius: radius.card - 4, paddingHorizontal: spacing.md, paddingVertical: spacing.sm + 3,
    color: colors.textPrimary, fontSize: fontSizes.sm + 1, marginBottom: spacing.sm,
  },
  stepBtn: { borderWidth: 1, borderColor: colors.lineStrong,
    width: 32, height: 32, borderRadius: 16, backgroundColor: colors.surfaceAlt,
    alignItems: 'center', justifyContent: 'center',
  },
  stepBtnText: { color: colors.textSecondary, fontSize: fontSizes.lg, fontWeight: '600', marginTop: -2 },
  stepVal: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700', minWidth: 24, textAlign: 'center' },
});
