import { useMemo, useState } from 'react';
import { View, Pressable, ScrollView, StyleSheet, Modal, Platform, Alert, RefreshControl, Linking } from 'react-native';
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
import { Plus, Phone, MessageCircle, CalendarDays, ChevronRight } from 'lucide-react-native';
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
import { SportIcon } from '@/components/sport-icon';
import { AgendaBookingCard, ClientAvatar, DateBlock, SportTile, bookingWhen, formsState } from '@/components/agenda-booking';

type TFn = (key: string, options?: { defaultValue?: string }) => string;
const periodLabel = (p: BookingPeriod, t: TFn) =>
  p === 'am' ? t('booking.am', { defaultValue: 'matin' }) : t('booking.pm', { defaultValue: 'après-midi' });

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

// Bookings of one half-day, outing by outing (first-seen order).
type OutingGroup = { head: AgendaItem; items: AgendaItem[] };
const groupBy = (items: AgendaItem[], keyOf: (it: AgendaItem) => string): OutingGroup[] => {
  const groups = new Map<string, OutingGroup>();
  for (const it of items) {
    const key = keyOf(it);
    const g = groups.get(key);
    if (g) g.items.push(it); else groups.set(key, { head: it, items: [it] });
  }
  return [...groups.values()];
};
const groupByOffering = (items: AgendaItem[]) => groupBy(items, (it) => it.offering_id ?? it.id);

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
    // The half-day shows the booked outing's sport icon (a confirmed booking
    // wins over a request) and the places taken, « 5/6 » (Scott 2026-11-01:
    // see at a glance how many clients are missing).
    const map = new Map<string, {
      available: boolean; accepted: number; pending: number; taken: number; max: number | null;
      sportKey: string | null; sportCategory: string | null; places: string | null;
    }>();
    for (const it of agenda ?? []) {
      const key = `${it.day}|${it.period}`;
      const cur = map.get(key) ?? { available: false, accepted: 0, pending: 0, taken: 0, max: null, sportKey: null, sportCategory: null, places: null };
      if (it.kind === 'availability') cur.available = true;
      else if (it.status === 'accepted') {
        if (cur.accepted === 0) { cur.sportKey = it.sport_key; cur.sportCategory = it.sport_category; cur.max = it.max_participants; }
        cur.accepted += 1;
        cur.taken += it.party_size ?? 0;
      } else if (it.status === 'pending') {
        if (cur.accepted === 0 && cur.pending === 0) { cur.sportKey = it.sport_key; cur.sportCategory = it.sport_category; cur.max = it.max_participants; }
        cur.pending += 1;
      }
      cur.places = cur.max != null ? `${cur.taken}/${cur.max}` : cur.taken > 0 ? String(cur.taken) : null;
      map.set(key, cur);
    }
    return map;
  }, [agenda]);

  // Same count as the DB (00566): places ACCEPTED on the half-day, all outings.
  const takenOn = (day: string, period: BookingPeriod) => slotIndex.get(`${day}|${period}`)?.taken ?? 0;
  const wouldOverflow = (b: AgendaItem) =>
    b.status === 'pending' && b.max_participants != null
    && takenOn(b.day, b.period) + (b.party_size ?? 0) > b.max_participants;
  const placesLabel = (taken: number, max: number | null) =>
    max != null
      ? t('booking.placesTaken', { defaultValue: '{{taken}}/{{max}} places', taken, max })
      : t('booking.peopleCount', { defaultValue: '{{count}} personnes', count: taken });
  const openProfile = (b: AgendaItem) => {
    if (!b.client_id) return;
    setSheetDay(null);
    setDetailId(null);
    router.push(`/(auth)/profile/${b.client_id}`);
  };

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
  // « À venir » = one row per outing session (day · half-day · outing), its
  // clients together — several clients often share one outing (Scott 2026-11-01).
  const upcoming = useMemo(() => {
    const today = dayjs().format('YYYY-MM-DD');
    const accepted = (agenda ?? []).filter((a) => a.kind === 'booking' && a.status === 'accepted' && a.day >= today);
    return groupBy(accepted, (a) => `${a.day}|${a.period}|${a.offering_id}`)
      .sort((x, y) => (x.head.day + x.head.period).localeCompare(y.head.day + y.head.period))
      .slice(0, 10);
  }, [agenda]);

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

  // ----- Écrire / appeler / fiche réservation -----
  const [detailId, setDetailId] = useState<string | null>(null);
  const detail = (agenda ?? []).find((a) => a.kind === 'booking' && a.id === detailId) ?? null;
  const [opening, setOpening] = useState(false);
  // 00565: the pro writes from a request too — the thread opens on demand.
  const handleWrite = async (b: AgendaItem) => {
    if (opening) return;
    setOpening(true);
    try {
      const conversationId = await bookingService.openConversation(b.id);
      setSheetDay(null);
      setDetailId(null);
      router.push(`/(auth)/conversation/${conversationId}`);
    } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
    finally { setOpening(false); }
  };
  const handleCall = (b: AgendaItem) => { if (b.manual_phone) void Linking.openURL(`tel:${b.manual_phone}`); };
  const openDetail = (b: AgendaItem) => { setSheetDay(null); setDetailId(b.id); };

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
  const dayCount = dayItems
    .filter((a) => a.kind === 'booking' && (a.status === 'accepted' || a.status === 'pending'))
    .reduce((acc, a) => ({ bookings: acc.bookings + 1, people: acc.people + (a.party_size ?? 0) }), { bookings: 0, people: 0 });

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
                  <AgendaBookingCard
                    key={b.id}
                    b={b}
                    variant="request"
                    full={wouldOverflow(b)}
                    onProfile={b.client_id ? () => openProfile(b) : undefined}
                    onWrite={b.client_id ? () => handleWrite(b) : undefined}
                    onDecline={() => handleDecline(b)}
                    onAccept={() => handleAccept(b)}
                  />
                ))}
              </>
            )}

            <AppText style={styles.sectionLabel}>{t('booking.upcoming', { defaultValue: 'À venir' })}</AppText>
            {upcoming.length === 0 ? (
              <AppText style={styles.empty}>{t('booking.noUpcoming', { defaultValue: 'Aucune réservation confirmée à venir.' })}</AppText>
            ) : upcoming.map(({ head: b, items: g }) => {
              const taken = g.reduce((n, x) => n + (x.party_size ?? 0), 0);
              return (
                // One client → that booking's card; several → the day, outing by outing.
                <Pressable
                  key={`${b.day}|${b.period}|${b.offering_id}`}
                  style={({ pressed }) => [styles.bkRow, pressed && styles.pressed]}
                  onPress={() => (g.length === 1 ? setDetailId(b.id) : setSheetDay(b.day))}
                >
                  <DateBlock b={b} />
                  <View style={{ flex: 1, minWidth: 0 }}>
                    <AppText style={styles.bkName} numberOfLines={1}>{b.offering_title ?? '—'}</AppText>
                    <AppText style={styles.bkWho} numberOfLines={1}>
                      {g.length === 1
                        ? `${b.client_name ?? '—'} · ${t('booking.peopleCount', { defaultValue: '{{count}} personnes', count: b.party_size ?? 0 })}`
                        : `${placesLabel(taken, b.max_participants)} · ${t('booking.clientsCount', { defaultValue: '{{count}} clients', count: g.length })}`}
                    </AppText>
                    <View style={styles.bkAvatars}>
                      {g.slice(0, 5).map((x, i) => (
                        <View key={x.id} style={[styles.bkAvatar, i > 0 && { marginLeft: -8 }]}>
                          <UserAvatar name={x.client_name ?? '?'} avatarUrl={x.client_avatar_url} size={22} />
                        </View>
                      ))}
                    </View>
                  </View>
                  <ChevronRight size={18} color={colors.textMuted} strokeWidth={2.2} />
                </Pressable>
              );
            })}
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

      {/* Fiche jour — les résas par demi-journée, chacune avec ses boutons
          (maquette validée 2026-11-01). Annuler vit dans la fiche réservation. */}
      <Modal visible={!!sheetDay} transparent animationType="slide" onRequestClose={() => setSheetDay(null)}>
        <Pressable style={styles.backdrop} onPress={() => setSheetDay(null)}>
          <Pressable style={[styles.sheet, styles.sheetTall]} onPress={(e) => e.stopPropagation()}>
            <View style={styles.grab} />
            <View style={styles.sheetHead}>
              <AppText style={[styles.sheetTitle, { flex: 1, marginBottom: 0 }]}>
                {sheetDay ? dayjs(sheetDay).format('dddd D MMMM') : ''}
              </AppText>
              {dayCount.bookings > 0 ? (
                <AppText style={styles.sheetCount}>
                  {t('booking.dayCount', { defaultValue: '{{count}} résas · {{people}} pers.', count: dayCount.bookings, people: dayCount.people })}
                </AppText>
              ) : null}
            </View>

            <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={{ paddingTop: spacing.sm }}>
              {(['am', 'pm'] as BookingPeriod[]).map((period) => {
                const bks = dayBookings(period);
                const open = dayOpen(period);
                return (
                  <View key={period} style={styles.slotBlock}>
                    <View style={styles.slotHead}>
                      <AppText style={styles.slotLabel}>{periodLabel(period, t).toUpperCase()}</AppText>
                      <View style={styles.slotRule} />
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
                    {/* Clients grouped under their outing, with its places (Scott 2026-11-01). */}
                    {groupByOffering(bks).map(({ head, items: g }) => {
                      const taken = g.filter((x) => x.status === 'accepted').reduce((n, x) => n + (x.party_size ?? 0), 0);
                      const isFull = head.max_participants != null && taken >= head.max_participants;
                      return (
                        <View key={head.offering_id ?? head.id} style={{ gap: spacing.sm }}>
                          <View style={styles.outHead}>
                            <SportTile b={{ ...head, status: 'accepted' }} size={30} />
                            <AppText style={styles.outTitle} numberOfLines={1}>{head.offering_title ?? '—'}</AppText>
                            <View style={[styles.statePill, { backgroundColor: isFull ? colors.cta + '1F' : colors.surfaceAlt }]}>
                              <AppText style={[styles.statePillText, { color: isFull ? colors.cta : colors.textSecondary }]}>
                                {isFull ? t('booking.full', { defaultValue: 'Complet' }) : placesLabel(taken, head.max_participants)}
                              </AppText>
                            </View>
                          </View>
                          {g.map((b) => (
                            <AgendaBookingCard
                              key={b.id}
                              b={b}
                              variant="day"
                              onProfile={b.client_id ? () => openProfile(b) : undefined}
                              onWrite={b.client_id ? () => handleWrite(b) : undefined}
                              onCall={b.manual_phone ? () => handleCall(b) : undefined}
                              onDetails={() => openDetail(b)}
                            />
                          ))}
                        </View>
                      );
                    })}
                  </View>
                );
              })}

              {!sheetIsPast && (
                <Pressable
                  style={({ pressed }) => [styles.btnPrimary, styles.btnBig, styles.btnBrand, pressed && styles.pressed]}
                  onPress={() => sheetDay && openManualSheet(sheetDay, dayOpen('am') || dayBookings('am').length === 0 ? 'am' : 'pm')}
                >
                  <Plus size={15} color={colors.onCta} strokeWidth={2.4} />
                  <AppText style={styles.btnPrimaryText}>{t('booking.addManualHere', { defaultValue: 'Ajouter une résa ce jour' })}</AppText>
                </Pressable>
              )}
            </ScrollView>
          </Pressable>
        </Pressable>
      </Modal>

      {/* Fiche réservation — depuis « À venir » ou « Détails » */}
      <Modal visible={!!detail} transparent animationType="slide" onRequestClose={() => setDetailId(null)}>
        <Pressable style={styles.backdrop} onPress={() => setDetailId(null)}>
          <Pressable style={[styles.sheet, styles.sheetTall]} onPress={(e) => e.stopPropagation()}>
            <View style={styles.grab} />
            {detail ? (() => {
              const c = sportCategoryColor(detail.sport_category, colors.cta);
              const forms = formsState(detail);
              const pending = detail.status === 'pending';
              const past = detail.day < dayjs().format('YYYY-MM-DD');
              const people = t('booking.peopleCount', { defaultValue: '{{count}} personnes', count: detail.party_size ?? 0 });
              return (
                <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={{ gap: spacing.md }}>
                  <View style={styles.dHead}>
                    <SportTile b={detail} size={48} />
                    <View style={{ flex: 1, minWidth: 0 }}>
                      <AppText style={styles.dTitle}>{detail.offering_title ?? '—'}</AppText>
                      <AppText style={[styles.dWhen, { color: c }]}>{bookingWhen(detail.day, detail.period, t)}</AppText>
                    </View>
                    <View style={[styles.statePill, { backgroundColor: pending ? colors.warning + '22' : colors.cta + '1F' }]}>
                      <AppText style={[styles.statePillText, { color: pending ? colors.warning : colors.cta }]}>
                        {pending
                          ? t('booking.status.pending', { defaultValue: 'En attente' })
                          : t('booking.status.accepted', { defaultValue: 'Confirmée' })}
                      </AppText>
                    </View>
                  </View>

                  <View style={styles.dClient}>
                    <ClientAvatar b={detail} size={40} onProfile={detail.client_id ? () => openProfile(detail) : undefined} />
                    <View style={{ flex: 1, minWidth: 0 }}>
                      <AppText style={styles.dClientName} numberOfLines={1}>{detail.client_name ?? '—'}</AppText>
                      <AppText style={styles.dClientSub} numberOfLines={1}>
                        {detail.is_manual
                          ? `${t('booking.bookedManual', { defaultValue: 'Manuelle' })}${detail.manual_phone ? ' · ' + detail.manual_phone : ''}`
                          : t('booking.bookedInApp', { defaultValue: 'Réservée dans l’app' })} · {people}
                      </AppText>
                    </View>
                    {detail.client_id ? (
                      <PressableScale hitSlop={8} onPress={() => openProfile(detail)}>
                        <AppText style={styles.dLink}>{t('booking.profileLink', { defaultValue: 'Profil ›' })}</AppText>
                      </PressableScale>
                    ) : null}
                  </View>

                  {detail.message ? (
                    <View style={{ gap: 6 }}>
                      <AppText style={styles.dLabel}>{t('booking.clientMessage', { defaultValue: 'Message du client' })}</AppText>
                      <AppText style={styles.dMsg}>« {detail.message} »</AppText>
                    </View>
                  ) : null}

                  {forms ? (
                    <View style={{ gap: 6 }}>
                      <AppText style={styles.dLabel}>
                        {t('booking.formsTitle', { defaultValue: 'Fiches participants · {{done}} sur {{total}}', done: forms.done, total: forms.total })}
                      </AppText>
                      <View style={styles.dForms}>
                        {Array.from({ length: forms.total }, (_, i) => {
                          const e = detail.participant_info?.[i];
                          return (
                            <View key={i} style={[styles.dFormRow, i > 0 && styles.dFormSep, !e && { backgroundColor: colors.warning + '12' }]}>
                              <AppText style={[styles.dFormNum, !e && { color: colors.warning }]}>{i + 1}</AppText>
                              <AppText style={[styles.dFormText, !e && { color: colors.warning }]} numberOfLines={2}>
                                {e ? formatEntry(e) : t('booking.formMissingRow', { defaultValue: 'Fiche manquante' })}
                              </AppText>
                            </View>
                          );
                        })}
                      </View>
                    </View>
                  ) : null}

                  {pending ? (
                    <View style={styles.reqActs}>
                      {detail.client_id ? (
                        <Pressable style={({ pressed }) => [styles.btnOutline, pressed && styles.pressed]} onPress={() => handleWrite(detail)}>
                          <MessageCircle size={16} color={colors.textPrimary} strokeWidth={2.2} />
                          <AppText style={styles.btnOutlineText}>{t('booking.write', { defaultValue: 'Écrire' })}</AppText>
                        </Pressable>
                      ) : null}
                      <Pressable style={({ pressed }) => [styles.btnGhost, pressed && styles.pressed]} onPress={() => { setDetailId(null); handleDecline(detail); }}>
                        <AppText style={styles.btnGhostText}>{t('booking.decline', { defaultValue: 'Refuser' })}</AppText>
                      </Pressable>
                      {wouldOverflow(detail) ? (
                        <View style={[styles.btnPrimary, { flex: 1, backgroundColor: colors.surfaceAlt }]}>
                          <AppText style={[styles.btnPrimaryText, { color: colors.textMuted }]}>{t('booking.full', { defaultValue: 'Complet' })}</AppText>
                        </View>
                      ) : (
                        <Pressable style={({ pressed }) => [styles.btnPrimary, { flex: 1 }, pressed && styles.pressed]} onPress={() => { setDetailId(null); void handleAccept(detail); }}>
                          <AppText style={styles.btnPrimaryText}>{t('booking.accept', { defaultValue: 'Accepter' })}</AppText>
                        </Pressable>
                      )}
                    </View>
                  ) : (
                    <>
                      {detail.client_id ? (
                        <Pressable style={({ pressed }) => [styles.btnPrimary, styles.btnTall, pressed && styles.pressed]} onPress={() => handleWrite(detail)}>
                          <MessageCircle size={16} color={colors.onCta} strokeWidth={2.2} />
                          <AppText style={styles.btnPrimaryText} numberOfLines={1}>
                            {t('booking.writeTo', { defaultValue: 'Écrire à {{name}}', name: detail.client_name ?? '' })}
                          </AppText>
                        </Pressable>
                      ) : detail.manual_phone ? (
                        <Pressable style={({ pressed }) => [styles.btnPrimary, styles.btnTall, pressed && styles.pressed]} onPress={() => handleCall(detail)}>
                          <Phone size={16} color={colors.onCta} strokeWidth={2.2} />
                          <AppText style={styles.btnPrimaryText}>{t('booking.call', { defaultValue: 'Appeler' })}</AppText>
                        </Pressable>
                      ) : null}
                      {!past ? (
                        <PressableScale style={styles.dCancel} onPress={() => { setDetailId(null); handleCancelPro(detail); }}>
                          <AppText style={styles.dCancelText}>{t('booking.cancelBooking', { defaultValue: 'Annuler la réservation' })}</AppText>
                        </PressableScale>
                      ) : null}
                    </>
                  )}
                </ScrollView>
              );
            })() : null}
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
            <View style={styles.grab} />
            <AppText style={[styles.sheetTitle, { textTransform: 'none' }]}>{t('booking.manualTitle', { defaultValue: 'Ajouter une réservation' })}</AppText>
            <AppText style={styles.mIntro}>{t('booking.manualIntro', { defaultValue: 'Pour un client qui a réservé par téléphone ou sur place.' })}</AppText>

            <AppText style={styles.fieldLabel}>{t('booking.manualOutingLabel', { defaultValue: 'Sortie' })}</AppText>
            <View style={styles.offerGrid}>
              {(offerings ?? []).map((o) => {
                const on = mOffering === o.id;
                const c = sportCategoryColor(o.sport_category, colors.cta);
                return (
                  <Pressable
                    key={o.id}
                    style={({ pressed }) => [styles.offerTile, on && { borderColor: c, borderWidth: 2 }, pressed && styles.pressed]}
                    onPress={() => setMOffering(o.id)}
                    accessibilityState={{ selected: on }}
                  >
                    <View style={[styles.offerIcon, { backgroundColor: on ? c : c + '1F' }]}>
                      <SportIcon sportKey={o.sport_key} size={16} color={on ? colors.onCta : c} />
                    </View>
                    <AppText style={styles.offerTitle} numberOfLines={2}>{o.title}</AppText>
                  </Pressable>
                );
              })}
            </View>

            <AppText style={styles.fieldLabel}>{t('booking.manualWhenLabel', { defaultValue: 'Quand' })}</AppText>
            <Pressable style={({ pressed }) => [styles.dateBtn, pressed && styles.pressed]} onPress={() => setMShowPicker(true)} accessibilityRole="button">
              <CalendarDays size={18} color={colors.cta} strokeWidth={2.2} />
              <AppText style={styles.dateBtnText}>{dayjs(mDay).format('dddd D MMMM')}</AppText>
              <AppText style={styles.dateBtnChange}>{t('booking.change', { defaultValue: 'Changer' })}</AppText>
            </Pressable>
            <View style={[styles.segmented, { marginTop: spacing.sm, marginBottom: 0 }]}>
              {(['am', 'pm'] as BookingPeriod[]).map((p) => (
                <Pressable key={p} style={[styles.segment, mPeriod === p && styles.segmentOn]} onPress={() => setMPeriod(p)}>
                  <AppText style={[styles.segmentText, mPeriod === p && styles.segmentTextOn]}>
                    {p === 'am' ? t('booking.periodAm', { defaultValue: 'Matin' }) : t('booking.periodPm', { defaultValue: 'Après-midi' })}
                  </AppText>
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
            <AppText style={styles.inputLabel}>{t('booking.manualNameLabel', { defaultValue: 'Nom' })}</AppText>
            <AppTextInput
              style={styles.input}
              placeholder={t('booking.manualName', { defaultValue: 'Nom (ex. Famille Perrin)' })}
              placeholderTextColor={colors.textMuted}
              value={mName}
              onChangeText={setMName}
              maxLength={80}
            />
            <View style={styles.mRow}>
              <View style={{ flex: 1 }}>
                <AppText style={styles.inputLabel}>{t('booking.manualPhoneLabel', { defaultValue: 'Téléphone (optionnel)' })}</AppText>
                <AppTextInput
                  style={[styles.input, { marginBottom: 0 }]}
                  placeholder="06 12 34 56 78"
                  placeholderTextColor={colors.textMuted}
                  value={mPhone}
                  onChangeText={setMPhone}
                  keyboardType="phone-pad"
                  maxLength={30}
                />
              </View>
              <View>
                <AppText style={styles.inputLabel}>{t('booking.partySize', { defaultValue: 'Personnes' })}</AppText>
                <View style={styles.stepper}>
                  <Pressable style={styles.stepBtn} onPress={() => setMSize((s) => Math.max(1, s - 1))} accessibilityLabel="−"><AppText style={styles.stepBtnText}>−</AppText></Pressable>
                  <AppText style={styles.stepVal}>{mSize}</AppText>
                  <Pressable style={styles.stepBtn} onPress={() => setMSize((s) => Math.min(50, s + 1))} accessibilityLabel="+"><AppText style={styles.stepBtnText}>+</AppText></Pressable>
                </View>
              </View>
            </View>

            <Pressable style={({ pressed }) => [styles.btnPrimary, styles.btnBig, styles.btnBrand, pressed && styles.pressed]} onPress={submitManual}>
              <AppText style={styles.btnPrimaryText}>{t('booking.manualSubmitFull', { defaultValue: 'Ajouter la réservation' })}</AppText>
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
  reqActs: { flexDirection: 'row', gap: spacing.sm, marginTop: spacing.sm + 2, alignItems: 'center' },
  btnGhost: { paddingVertical: spacing.sm + 1, paddingHorizontal: spacing.md, borderRadius: radius.full },
  btnGhostText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600' },
  btnPrimary: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6,
    backgroundColor: colors.cta, borderRadius: radius.full, paddingVertical: spacing.sm + 2, paddingHorizontal: spacing.md,
  },
  btnPrimaryText: { color: colors.onCta, fontSize: fontSizes.sm, fontWeight: '700' },
  btnBig: { marginTop: spacing.md, paddingVertical: spacing.sm + 4 },
  btnBrand: { backgroundColor: colors.brand },
  empty: { color: colors.textSecondary, fontSize: fontSizes.sm, marginBottom: spacing.sm },
  bkRow: { borderWidth: 1, borderColor: colors.lineStrong,
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 2,
    backgroundColor: colors.surface, borderRadius: radius.card, padding: spacing.sm + 4, marginBottom: spacing.xs + 2,
    ...shadows.card,
  },
  bkName: { color: colors.textPrimary, fontSize: fontSizes.sm + 1, fontWeight: '800' },
  bkWho: { color: colors.textPrimary, fontSize: fontSizes.sm - 1, marginTop: 2 },
  bkAvatars: { flexDirection: 'row', marginTop: 5 },
  bkAvatar: { borderRadius: 13, borderWidth: 2, borderColor: colors.surface },
  outHead: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  outTitle: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.sm + 1, fontWeight: '800' },
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
  slotBlock: { paddingVertical: spacing.sm, gap: spacing.sm },
  slotHead: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, marginBottom: 2 },
  slotLabel: { color: colors.textMuted, fontSize: fontSizes.xs, fontWeight: '800', letterSpacing: 0.8 },
  slotRule: { flex: 1, height: 1, backgroundColor: colors.line },
  statePill: { borderRadius: radius.full, paddingHorizontal: spacing.sm + 2, paddingVertical: 4 },
  statePillText: { fontSize: fontSizes.xs, fontWeight: '800' },
  slotToggle: { color: colors.cta, fontSize: fontSizes.sm - 1, fontWeight: '700' },
  sheetTall: { maxHeight: '88%' },
  sheetHead: { flexDirection: 'row', alignItems: 'baseline', gap: spacing.sm },
  sheetCount: { color: colors.textSecondary, fontSize: fontSizes.sm - 1 },
  dHead: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 4 },
  dTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800' },
  dWhen: { fontSize: fontSizes.sm, fontWeight: '600', marginTop: 2 },
  dClient: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 4,
    backgroundColor: colors.surfaceAlt, borderRadius: radius.card - 2, paddingHorizontal: spacing.sm + 4, paddingVertical: spacing.sm + 2,
  },
  dClientName: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '800' },
  dClientSub: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, marginTop: 1 },
  dLink: { color: colors.cta, fontSize: fontSizes.sm - 1, fontWeight: '700' },
  dLabel: {
    color: colors.textMuted, fontSize: fontSizes.xs, fontWeight: '800', textTransform: 'uppercase', letterSpacing: 0.8,
  },
  dMsg: { color: colors.textPrimary, fontSize: fontSizes.sm, lineHeight: 20 },
  dForms: { borderWidth: 1, borderColor: colors.lineStrong, borderRadius: radius.card - 2, overflow: 'hidden' },
  dFormRow: { flexDirection: 'row', gap: spacing.sm + 2, paddingHorizontal: spacing.sm + 4, paddingVertical: spacing.sm + 1 },
  dFormSep: { borderTopWidth: 1, borderTopColor: colors.line },
  dFormNum: { color: colors.textMuted, fontSize: fontSizes.sm - 1, fontWeight: '800', width: 14 },
  dFormText: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.sm - 1 },
  btnOutline: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6,
    borderWidth: 1, borderColor: colors.lineStrong, backgroundColor: colors.surface,
    borderRadius: radius.full, paddingVertical: spacing.sm + 2, paddingHorizontal: spacing.md - 2,
  },
  btnOutlineText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700' },
  btnTall: { paddingVertical: spacing.sm + 5 },
  dCancel: { alignSelf: 'center', paddingVertical: spacing.xs + 2 },
  dCancelText: { color: colors.error, fontSize: fontSizes.sm, fontWeight: '700' },
  mIntro: { color: colors.textSecondary, fontSize: fontSizes.sm - 1, marginTop: -spacing.xs },
  offerGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  offerTile: {
    width: '48%', flexGrow: 1, minHeight: 56, flexDirection: 'row', alignItems: 'center', gap: spacing.sm,
    padding: spacing.sm + 2, borderRadius: radius.card - 2, borderWidth: 1, borderColor: colors.lineStrong, backgroundColor: colors.surface,
  },
  offerIcon: { width: 30, height: 30, borderRadius: 9, alignItems: 'center', justifyContent: 'center' },
  offerTitle: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.sm - 1, fontWeight: '700', lineHeight: 16 },
  dateBtn: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 2,
    borderWidth: 1, borderColor: colors.lineStrong, backgroundColor: colors.surface,
    borderRadius: radius.card - 2, paddingHorizontal: spacing.md - 2, paddingVertical: spacing.sm + 4,
  },
  dateBtnText: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.md - 1, fontWeight: '700', textTransform: 'capitalize' },
  dateBtnChange: { color: colors.cta, fontSize: fontSizes.sm - 1, fontWeight: '600' },
  inputLabel: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, fontWeight: '600', marginBottom: 4 },
  mRow: { flexDirection: 'row', alignItems: 'flex-end', gap: spacing.sm + 2 },
  stepper: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, height: 46 },
  fieldLabel: {
    color: colors.textMuted, fontSize: fontSizes.xs, fontWeight: '800',
    textTransform: 'uppercase', letterSpacing: 0.5, marginTop: spacing.md, marginBottom: spacing.xs + 2,
  },
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
