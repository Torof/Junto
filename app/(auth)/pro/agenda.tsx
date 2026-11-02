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
import { Plus, Phone, MessageCircle, CalendarDays, ChevronRight, MessagesSquare, CalendarX2, RefreshCw, Copy, Pencil, MapPin, ShieldCheck } from 'lucide-react-native';
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
import { AgendaBookingCard, ClientAvatar, DateBlock, SportTile, bookingWhen, formsState, itemHalves, wouldOverflow as overflowsOuting } from '@/components/agenda-booking';
import { sessionService, type MySession } from '@/services/session-service';
import { sessionBlockSub, sessionHalfDays, sessionRange } from '@/utils/session-time';

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
// An outing = one offering at one start half-day (a booking over days shows on each of its days).
const groupByOffering = (items: AgendaItem[]) => groupBy(items, (it) => `${it.offering_id ?? it.id}|${it.day}|${it.period}`);

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

  // Fixed dates (00575) of the same window.
  const { data: sessions } = useQuery({
    queryKey: ['my-sessions', from, to],
    queryFn: () => sessionService.getMine(from, to),
  });
  // (day|period) → the fixed date covering it, and its label on the calendar.
  const fixedIndex = useMemo(() => {
    const map = new Map<string, { session: MySession; label: string }>();
    for (const se of sessions ?? []) {
      const halves = sessionHalfDays(se);
      halves.forEach(([day, period], i) => {
        const label = i === 0 ? `${se.taken}/${se.max_participants}` : i === halves.length - 1 ? t('session.calEnd', { defaultValue: 'fin' }) : '→';
        map.set(`${day}|${period}`, { session: se, label });
      });
    }
    return map;
  }, [sessions, t]);

  const invalidate = () => Promise.all([
    queryClient.invalidateQueries({ queryKey: ['pro-agenda'] }),
    queryClient.invalidateQueries({ queryKey: ['my-sessions'] }),
    // The pro's own outing pages show places from these.
    queryClient.invalidateQueries({ queryKey: ['offering-sessions'] }),
    queryClient.invalidateQueries({ queryKey: ['pro-availability'] }),
  ]);

  // Consulter ≠ éditer (maquette 2026-09-28) : lecture par défaut, édition explicite.
  const [editMode, setEditMode] = useState(false);
  const [sheetDay, setSheetDay] = useState<string | null>(null);

  // Index (day|period) → slot state for the calendar.
  const slotIndex = useMemo(() => {
    // The half-day shows the booked outing's sport icon (a confirmed booking
    // wins over a request) and the places taken, « 5/6 » (Scott 2026-11-01:
    // see at a glance how many clients are missing).
    const map = new Map<string, {
      available: boolean; busy: boolean; accepted: number; pending: number; taken: number; max: number | null;
      sportKey: string | null; sportCategory: string | null; places: string | null;
    }>();
    // A booking over days (00577) fills every half-day of its range.
    for (const it of agenda ?? []) {
      for (const [day, period] of it.kind === 'booking' ? itemHalves(it) : [[it.day, it.period] as const]) {
        const key = `${day}|${period}`;
        const cur = map.get(key) ?? { available: false, busy: false, accepted: 0, pending: 0, taken: 0, max: null, sportKey: null, sportCategory: null, places: null };
        if (it.kind === 'availability') cur.available = true;
        else if (it.kind === 'busy') cur.busy = true;
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
    }
    return map;
  }, [agenda]);

  // Same count as the DB (00566, 00577): places ACCEPTED on every half-day of
  // the request, all outings.
  const wouldOverflow = (b: AgendaItem) => overflowsOuting(b, agenda ?? []);
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

  const slotState = (day: string, period: BookingPeriod) => {
    const st = slotIndex.get(`${day}|${period}`) ?? { available: false };
    const fx = fixedIndex.get(`${day}|${period}`);
    return fx ? { ...st, fixed: fx.label, sportKey: fx.session.sport_key, sportCategory: fx.session.sport_category } : st;
  };

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
    // Sign-ups of a fixed date live under « Mes dates fixes ».
    const accepted = (agenda ?? []).filter((a) => a.kind === 'booking' && a.status === 'accepted' && (a.end_day ?? a.day) >= today && !a.session_id);
    return groupBy(accepted, (a) => `${a.day}|${a.period}|${a.offering_id}`)
      .sort((x, y) => (x.head.day + x.head.period).localeCompare(y.head.day + y.head.period))
      .slice(0, 10);
  }, [agenda]);

  // One accept at a time: a double tap fired it twice (success, then an error toast).
  const [accepting, setAccepting] = useState(false);
  const handleAccept = async (b: AgendaItem) => {
    if (accepting) return;
    setAccepting(true);
    try {
      await bookingService.accept(b.id);
      Burnt.toast({ title: t('booking.acceptedToast', { defaultValue: 'Réservation confirmée' }), preset: 'done' });
      await invalidate();
    } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
    finally { setAccepting(false); }
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

  // ----- Une sortie entière : écrire à tous / annuler (00567) -----
  const [outing, setOuting] = useState<{ kind: 'write' | 'cancel'; head: AgendaItem; sessionId?: string; when?: string } | null>(null);
  const [outingText, setOutingText] = useState('');
  const [outingBusy, setOutingBusy] = useState(false);
  const openOuting = (kind: 'write' | 'cancel', head: AgendaItem, sessionId?: string, when?: string) => {
    setOutingText('');
    setSheetDay(null);
    setSessionOpenId(null);
    setOuting({ kind, head, sessionId, when });
  };
  const submitOuting = async () => {
    if (!outing || !outing.head.offering_id || outingBusy) return;
    const { kind, head } = outing;
    const offeringId = head.offering_id;
    if (!offeringId) return;
    const text = outingText.trim();
    if (kind === 'write' && !text) return;
    const run = async () => {
      setOutingBusy(true);
      try {
        if (kind === 'write') {
          const n = await bookingService.messageOutingClients(offeringId, head.day, head.period, text);
          Burnt.toast({
            title: n > 0
              ? t('booking.writeAllSent', { defaultValue: 'Message envoyé à {{count}} clients', count: n })
              : t('booking.writeAllNone', { defaultValue: 'Aucun client confirmé dans l’app sur cette sortie' }),
            preset: n > 0 ? 'done' : 'none',
          });
        } else {
          if (outing.sessionId) await sessionService.cancel(outing.sessionId, text || undefined);
          else await bookingService.cancelOuting(offeringId, head.day, head.period, text || undefined);
          Burnt.toast({ title: t('booking.outingCancelled', { defaultValue: 'Sortie annulée, clients prévenus' }), preset: 'done' });
          await invalidate();
        }
        setOuting(null);
      } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
      finally { setOutingBusy(false); }
    };
    if (kind === 'write') { void run(); return; }
    Alert.alert(
      t('booking.cancelOutingTitle', { defaultValue: 'Annuler toute la sortie ?' }),
      t('booking.cancelOutingBody', { defaultValue: 'Toutes les réservations et demandes de ce créneau seront annulées, et les clients prévenus.' }),
      [
        { text: t('activity.no', { defaultValue: 'Non' }), style: 'cancel' },
        { text: t('booking.cancelOutingConfirm', { defaultValue: 'Annuler la sortie' }), style: 'destructive', onPress: () => void run() },
      ],
    );
  };

  // ----- Fixed dates (00575): the date's sheet -----
  const [sessionOpenId, setSessionOpenId] = useState<string | null>(null);
  const openSession = (sessions ?? []).find((se) => se.id === sessionOpenId) ?? null;
  const sessionHead = (se: MySession): AgendaItem => ({
    kind: 'booking', id: se.id, day: se.start_day, period: se.start_period, status: 'accepted',
    offering_id: se.offering_id, offering_title: se.offering_title, party_size: se.taken,
    client_id: null, client_name: null, manual_phone: null, message: null, is_manual: null,
    sport_key: se.sport_key, sport_category: se.sport_category, participant_fields: null, participant_info: null,
    client_avatar_url: null, max_participants: se.max_participants, session_id: se.id,
    end_day: null, min_participants: se.min_participants, confirmed: se.confirmed,
  });
  const signUpsOf = (id: string) => (agenda ?? []).filter((a) => a.kind === 'booking' && a.status === 'accepted' && a.session_id === id);
  // Minimum of an outing (00577): reached, maintained by the pro, or short —
  // then the pro can maintain it before the automatic cancellation at D-1 9h.
  const outingMin = (min: number | null, taken: number, confirmed: boolean): { text: string; ok: boolean; short: boolean } | null => {
    if (min == null) return null;
    if (taken >= min) return { text: t('session.sureMin', { defaultValue: 'Départ assuré (min. {{count}})', count: min }), ok: true, short: false };
    if (confirmed) return { text: t('booking.maintained', { defaultValue: 'Sortie maintenue (min. {{count}})', count: min }), ok: true, short: false };
    return { text: t('session.missingForMin', { defaultValue: 'Il manque {{count}} pers. pour partir', count: min - taken }), ok: false, short: true };
  };
  const minLine = (se: MySession) => outingMin(se.min_participants, se.taken, se.confirmed);
  const handleMaintain = (offeringId: string, day: string, period: BookingPeriod, taken: number) => {
    Alert.alert(
      t('booking.maintainTitle', { defaultValue: 'Maintenir la sortie ?' }),
      t('booking.maintainBody', { defaultValue: 'Elle partira à {{count}} : les clients sont prévenus que le départ est confirmé, et elle ne sera plus annulée automatiquement.', count: taken }),
      [
        { text: t('activity.no', { defaultValue: 'Non' }), style: 'cancel' },
        {
          text: t('booking.maintain', { defaultValue: 'Maintenir la sortie' }),
          onPress: async () => {
            try {
              await bookingService.confirmOuting(offeringId, day, period);
              Burnt.toast({ title: t('booking.maintainedToast', { defaultValue: 'Sortie maintenue, clients prévenus' }), preset: 'done' });
              await invalidate();
            } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
          },
        },
      ],
    );
  };
  const today = dayjs().format('YYYY-MM-DD');
  const upcomingSessions = (sessions ?? []).filter((se) => se.end_day >= today);

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
  // A booking over days (00577) belongs to each of its days.
  const dayItems = (agenda ?? []).filter((a) =>
    a.kind === 'booking' ? itemHalves(a).some(([d]) => d === sheetDay) : a.day === sheetDay);
  const dayBookings = (period: BookingPeriod) =>
    dayItems.filter((a) => a.kind === 'booking' && itemHalves(a).some(([d, p]) => d === sheetDay && p === period)
      && (a.status === 'accepted' || a.status === 'pending'));
  const dayOpen = (period: BookingPeriod) =>
    dayItems.some((a) => a.kind === 'availability' && a.period === period);
  const sheetIsPast = !!sheetDay && sheetDay < dayjs().format('YYYY-MM-DD');
  const dayCount = dayItems
    .filter((a, i, all) => a.kind === 'booking' && (a.status === 'accepted' || a.status === 'pending')
      && all.findIndex((x) => x.id === a.id) === i)
    .reduce((acc, a) => ({ bookings: acc.bookings + 1, people: acc.people + (a.party_size ?? 0) }), { bookings: 0, people: 0 });

  return (
    <View style={styles.container}>
      <Stack.Screen
        options={{
          title: t('booking.agendaTitle', { defaultValue: 'Agenda' }),
          // Manual booking lives in the header (was a floating button that sat
          // on the calendar's last row and the legend — lot 2 pro).
          headerRight: () => (
            <View style={{ flexDirection: 'row', gap: spacing.sm }}>
              <PressableScale onPress={() => router.push('/(auth)/pro/session-form')} hitSlop={8} style={[styles.headerBtn, { backgroundColor: colors.brand }]} accessibilityLabel={t('session.newTitle', { defaultValue: 'Poser une date' })}>
                <Plus size={14} color={colors.onCta} strokeWidth={2.6} />
                <AppText style={[styles.headerBtnText, { color: colors.onCta }]}>{t('session.addShort', { defaultValue: 'Date' })}</AppText>
              </PressableScale>
              <PressableScale onPress={() => openManualSheet()} hitSlop={8} style={styles.headerBtn} accessibilityLabel={t('booking.addManual', { defaultValue: 'Ajouter une résa' })}>
                <Plus size={14} color={colors.textPrimary} strokeWidth={2.6} />
                <AppText style={styles.headerBtnText}>{t('booking.addManualShort', { defaultValue: 'Résa' })}</AppText>
              </PressableScale>
            </View>
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
          showBusyLegend={(agenda ?? []).some((a) => a.kind === 'busy')}
          showFixedLegend={(sessions ?? []).length > 0}
        />

        {!editMode && (
          <AppText style={styles.hint}>{t('booking.viewHint', { defaultValue: 'Tape un jour pour voir qui vient et gérer ses créneaux.' })}</AppText>
        )}

        {/* Calendar links (00568): export to Google/Apple/Outlook, import busy times. */}
        <Pressable style={({ pressed }) => [styles.syncRow, pressed && styles.pressed]} onPress={() => router.push('/(auth)/pro/calendar-sync')} accessibilityRole="button">
          <View style={styles.syncIcon}><RefreshCw size={16} color={colors.cta} strokeWidth={2.4} /></View>
          <View style={{ flex: 1, minWidth: 0 }}>
            <AppText style={styles.syncTitle}>{t('calendarSync.entryTitle', { defaultValue: 'Synchroniser avec mon agenda' })}</AppText>
            <AppText style={styles.syncSub} numberOfLines={1}>{t('calendarSync.entrySub', { defaultValue: 'Google Agenda, Apple, Outlook' })}</AppText>
          </View>
          <ChevronRight size={18} color={colors.textMuted} strokeWidth={2.2} />
        </Pressable>

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

            {upcomingSessions.length > 0 && (
              <>
                <AppText style={styles.sectionLabel}>{t('session.mine', { defaultValue: 'Mes dates fixes' })}</AppText>
                {upcomingSessions.map((se) => {
                  const c = sportCategoryColor(se.sport_category, colors.cta);
                  const ml = minLine(se);
                  return (
                    <Pressable
                      key={se.id}
                      style={({ pressed }) => [styles.bkRow, { borderColor: c, borderWidth: 1.5 }, pressed && styles.pressed]}
                      onPress={() => setSessionOpenId(se.id)}
                      accessibilityRole="button"
                    >
                      <View style={{ width: 56, borderRadius: radius.lg, backgroundColor: c, alignItems: 'center', paddingVertical: 6 }}>
                        <AppText style={{ color: colors.onCta, fontSize: fontSizes.xs - 2, fontWeight: '800' }}>{dayjs(se.start_day).format('ddd').toUpperCase()}</AppText>
                        <AppText style={{ color: colors.onCta, fontSize: fontSizes.lg + 2, lineHeight: 24, fontWeight: '800' }}>{dayjs(se.start_day).date()}</AppText>
                        <AppText style={{ color: colors.onCta, fontSize: fontSizes.xs - 2, fontWeight: '700' }}>{sessionBlockSub(se)}</AppText>
                      </View>
                      <View style={{ flex: 1, minWidth: 0 }}>
                        <AppText style={styles.bkName} numberOfLines={1}>{se.offering_title}</AppText>
                        <AppText style={styles.bkWho} numberOfLines={1}>{sessionRange(se)}</AppText>
                        <AppText style={[styles.bkWho, { fontWeight: '700', color: ml && !ml.ok ? colors.warning : colors.cta }]} numberOfLines={1}>
                          {placesLabel(se.taken, se.max_participants)}{ml ? ` · ${ml.text}` : ''}
                        </AppText>
                      </View>
                      <ChevronRight size={18} color={colors.textMuted} strokeWidth={2.2} />
                    </Pressable>
                  );
                })}
              </>
            )}

            <AppText style={styles.sectionLabel}>{t('booking.upcoming', { defaultValue: 'À venir' })}</AppText>
            {upcoming.length === 0 ? (
              <AppText style={styles.empty}>{t('booking.noUpcoming', { defaultValue: 'Aucune réservation confirmée à venir.' })}</AppText>
            ) : upcoming.map(({ head: b, items: g }) => {
              const taken = g.reduce((n, x) => n + (x.party_size ?? 0), 0);
              const om = outingMin(b.min_participants, taken, g.some((x) => x.confirmed));
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
                    {om?.short ? (
                      <AppText style={[styles.bkWho, { fontWeight: '700', color: colors.warning }]} numberOfLines={1}>{om.text}</AppText>
                    ) : null}
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
                const busy = dayItems.some((a) => a.kind === 'busy' && a.period === period);
                const fx = sheetDay ? fixedIndex.get(`${sheetDay}|${period}`) : undefined;
                return (
                  <View key={period} style={styles.slotBlock}>
                    <View style={styles.slotHead}>
                      <AppText style={styles.slotLabel}>{periodLabel(period, t).toUpperCase()}</AppText>
                      <View style={styles.slotRule} />
                      {busy && (
                        <View style={[styles.statePill, { backgroundColor: colors.textMuted + '22' }]}>
                          <AppText style={[styles.statePillText, { color: colors.textSecondary }]}>
                            {t('booking.legendBusy', { defaultValue: 'Occupé (ton agenda)' })}
                          </AppText>
                        </View>
                      )}
                      {fx && (
                        <PressableScale hitSlop={6} onPress={() => { setSheetDay(null); setSessionOpenId(fx.session.id); }}>
                          <View style={[styles.statePill, { backgroundColor: colors.cta + '1A' }]}>
                            <AppText style={[styles.statePillText, { color: colors.cta }]} numberOfLines={1}>
                              {t('session.legend', { defaultValue: 'Date fixe' })} · {fx.session.offering_title} ›
                            </AppText>
                          </View>
                        </PressableScale>
                      )}
                      {bks.length === 0 && !busy && !fx && (
                        <View style={[styles.statePill, { backgroundColor: open ? colors.cta + '1A' : colors.textMuted + '22' }]}>
                          <AppText style={[styles.statePillText, { color: open ? colors.cta : colors.textMuted }]}>
                            {open ? t('booking.slotOpen', { defaultValue: 'Ouvert' }) : t('booking.slotClosed', { defaultValue: 'Fermé' })}
                          </AppText>
                        </View>
                      )}
                      {!sheetIsPast && bks.length === 0 && !fx && (
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
                      // On request only: a fixed date's minimum lives on its own sheet.
                      const om = !head.session_id && taken > 0
                        ? outingMin(head.min_participants, taken, g.some((x) => x.confirmed)) : null;
                      return (
                        <View key={`${head.offering_id ?? head.id}|${head.day}|${head.period}`} style={{ gap: spacing.sm }}>
                          <View style={styles.outHead}>
                            <SportTile b={{ ...head, status: 'accepted' }} size={30} />
                            <AppText style={styles.outTitle} numberOfLines={1}>{head.offering_title ?? '—'}</AppText>
                            <View style={[styles.statePill, { backgroundColor: isFull ? colors.cta + '1F' : colors.surfaceAlt }]}>
                              <AppText style={[styles.statePillText, { color: isFull ? colors.cta : colors.textSecondary }]}>
                                {isFull ? t('booking.full', { defaultValue: 'Complet' }) : placesLabel(taken, head.max_participants)}
                              </AppText>
                            </View>
                          </View>
                          {head.end_day ? (
                            <AppText style={styles.hint}>{bookingWhen(head.day, head.period, t, head.end_day)}</AppText>
                          ) : null}
                          {om ? (
                            <AppText style={[styles.hint, { fontWeight: '700', color: om.ok ? colors.cta : colors.warning }]}>{om.text}</AppText>
                          ) : null}
                          {/* Actions follow the outing's start: on day 2 of a range already begun, cancelling or maintaining is closed. */}
                          {head.day >= today && (
                            <View style={styles.outActs}>
                              {om?.short && head.offering_id ? (
                                <Pressable style={({ pressed }) => [styles.outActBtn, pressed && styles.pressed]} onPress={() => handleMaintain(head.offering_id as string, head.day, head.period, taken)} accessibilityRole="button">
                                  <ShieldCheck size={15} color={colors.cta} strokeWidth={2.2} />
                                  <AppText style={styles.outActText}>{t('booking.maintain', { defaultValue: 'Maintenir la sortie' })}</AppText>
                                </Pressable>
                              ) : null}
                              {g.some((x) => x.status === 'accepted' && x.client_id) && (
                                <Pressable style={({ pressed }) => [styles.outActBtn, pressed && styles.pressed]} onPress={() => openOuting('write', head)} accessibilityRole="button">
                                  <MessagesSquare size={15} color={colors.cta} strokeWidth={2.2} />
                                  <AppText style={styles.outActText}>{t('booking.writeAll', { defaultValue: 'Écrire à tous' })}</AppText>
                                </Pressable>
                              )}
                              <Pressable style={({ pressed }) => [styles.outActBtn, styles.outActDanger, pressed && styles.pressed]} onPress={() => openOuting('cancel', head)} accessibilityRole="button">
                                <CalendarX2 size={15} color={colors.error} strokeWidth={2.2} />
                                <AppText style={[styles.outActText, { color: colors.error }]}>{t('booking.cancelOuting', { defaultValue: 'Annuler la sortie' })}</AppText>
                              </Pressable>
                            </View>
                          )}
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
                      <AppText style={[styles.dWhen, { color: c }]}>{bookingWhen(detail.day, detail.period, t, detail.end_day)}</AppText>
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

      {/* Fiche d'une date fixe (00575) : remplissage, le groupe et ses fiches, actions. */}
      <Modal visible={!!openSession} transparent animationType="slide" onRequestClose={() => setSessionOpenId(null)}>
        <Pressable style={styles.backdrop} onPress={() => setSessionOpenId(null)}>
          <Pressable style={[styles.sheet, styles.sheetTall]} onPress={(e) => e.stopPropagation()}>
            <View style={styles.grab} />
            {openSession ? (() => {
              const se = openSession;
              const head = sessionHead(se);
              const c = sportCategoryColor(se.sport_category, colors.cta);
              const ml = minLine(se);
              const signUps = signUpsOf(se.id);
              const asks = signUps.some((b) => formsState(b) != null);
              const done = signUps.reduce((n, b) => n + (formsState(b)?.done ?? 0), 0);
              const started = se.start_day < today;
              return (
                <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={{ gap: spacing.md }}>
                  <View style={styles.dHead}>
                    <SportTile b={head} size={48} />
                    <View style={{ flex: 1, minWidth: 0 }}>
                      <AppText style={styles.dTitle}>{se.offering_title}</AppText>
                      <AppText style={[styles.dWhen, { color: c }]}>{sessionRange(se)}</AppText>
                      {se.meeting_point ? (
                        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4, marginTop: 2 }}>
                          <MapPin size={12} color={colors.textSecondary} strokeWidth={2.2} />
                          <AppText style={styles.dClientSub} numberOfLines={2}>{se.meeting_point}</AppText>
                        </View>
                      ) : null}
                    </View>
                  </View>

                  <View style={styles.fillBox}>
                    <View style={styles.fillHead}>
                      <AppText style={styles.dClientName}>{t('session.placesTaken', { defaultValue: '{{taken}} / {{max}} places prises', taken: se.taken, max: se.max_participants })}</AppText>
                      {ml ? <AppText style={[styles.fillMin, { color: ml.ok ? colors.cta : colors.warning }]}>{ml.text}</AppText> : null}
                    </View>
                    {ml?.short && !started && se.taken > 0 ? (
                      <Pressable style={({ pressed }) => [styles.btnOutline, { marginTop: spacing.sm }, pressed && styles.pressed]} onPress={() => handleMaintain(se.offering_id, se.start_day, se.start_period, se.taken)} accessibilityRole="button">
                        <ShieldCheck size={16} color={colors.textPrimary} strokeWidth={2.2} />
                        <AppText style={styles.btnOutlineText}>{t('booking.maintain', { defaultValue: 'Maintenir la sortie' })}</AppText>
                      </Pressable>
                    ) : null}
                    <View style={styles.fillTrack}>
                      <View style={[styles.fillBar, { width: `${Math.min(100, Math.round((se.taken / se.max_participants) * 100))}%`, backgroundColor: c }]} />
                    </View>
                  </View>

                  <View style={{ gap: 6 }}>
                    <AppText style={styles.dLabel}>
                      {asks
                        ? t('session.groupForms', { defaultValue: 'Le groupe · fiches {{done}} sur {{total}}', done, total: se.taken })
                        : t('session.group', { defaultValue: 'Le groupe' })}
                    </AppText>
                    {signUps.length === 0 ? (
                      <AppText style={styles.empty}>{t('session.noSignUp', { defaultValue: 'Personne d’inscrit pour l’instant.' })}</AppText>
                    ) : (
                      <View style={styles.dForms}>
                        {signUps.map((b, bi) => {
                          const forms = formsState(b);
                          return (
                            <View key={b.id} style={[bi > 0 && styles.dFormSep, { paddingBottom: spacing.sm }]}>
                              <View style={styles.groupHead}>
                                <ClientAvatar b={b} size={30} onProfile={b.client_id ? () => openProfile(b) : undefined} />
                                <AppText style={[styles.dClientName, { flex: 1 }]} numberOfLines={1}>
                                  {b.client_name ?? '—'} · {t('booking.peopleCount', { defaultValue: '{{count}} personnes', count: b.party_size ?? 0 })}
                                </AppText>
                                {b.client_id ? (
                                  <PressableScale hitSlop={8} onPress={() => openProfile(b)}>
                                    <AppText style={styles.dLink}>{t('booking.profileLink', { defaultValue: 'Profil ›' })}</AppText>
                                  </PressableScale>
                                ) : null}
                              </View>
                              {/* The client's note from the sign-up screen (« Un mot pour … »). */}
                              {b.message ? (
                                <AppText style={[styles.dFormText, { marginTop: 4 }]} numberOfLines={4}>« {b.message} »</AppText>
                              ) : null}
                              {forms ? Array.from({ length: forms.total }, (_, i) => {
                                const e = b.participant_info?.[i];
                                return e ? (
                                  <View key={i} style={styles.dFormRow}>
                                    <AppText style={styles.dFormNum}>{i + 1}</AppText>
                                    <AppText style={styles.dFormText} numberOfLines={2}>{formatEntry(e)}</AppText>
                                  </View>
                                ) : null;
                              }) : null}
                              {forms && forms.done < forms.total ? (
                                <View style={styles.missingRow}>
                                  <AppText style={styles.missingText}>
                                    {t('session.formsMissing', { defaultValue: '{{count}} fiches pas encore remplies', count: forms.total - forms.done })}
                                  </AppText>
                                  {b.client_id ? (
                                    <PressableScale hitSlop={6} onPress={() => { setSessionOpenId(null); void handleWrite(b); }}>
                                      <AppText style={styles.dLink}>{t('booking.write', { defaultValue: 'Écrire' })} ›</AppText>
                                    </PressableScale>
                                  ) : null}
                                </View>
                              ) : null}
                              {!started ? (
                                <PressableScale hitSlop={6} onPress={() => { setSessionOpenId(null); handleCancelPro(b); }}>
                                  <AppText style={styles.removeText}>{t('session.removeSignUp', { defaultValue: 'Retirer' })}</AppText>
                                </PressableScale>
                              ) : null}
                            </View>
                          );
                        })}
                      </View>
                    )}
                  </View>

                  <View style={styles.reqActs}>
                    {signUps.some((b) => b.client_id) ? (
                      <Pressable style={({ pressed }) => [styles.btnPrimary, { flex: 1 }, pressed && styles.pressed]} onPress={() => openOuting('write', head, se.id, sessionRange(se))}>
                        <MessagesSquare size={16} color={colors.onCta} strokeWidth={2.2} />
                        <AppText style={styles.btnPrimaryText}>{t('booking.writeAll', { defaultValue: 'Écrire à tous' })}</AppText>
                      </Pressable>
                    ) : null}
                    <Pressable style={({ pressed }) => [styles.btnOutline, pressed && styles.pressed]} onPress={() => { setSessionOpenId(null); router.push(`/(auth)/pro/session-form?dup=${se.id}`); }}>
                      <Copy size={16} color={colors.textPrimary} strokeWidth={2.2} />
                      <AppText style={styles.btnOutlineText}>{t('session.duplicate', { defaultValue: 'Dupliquer' })}</AppText>
                    </Pressable>
                  </View>
                  {!started ? (
                    <View style={styles.sessionFoot}>
                      <PressableScale hitSlop={6} onPress={() => { setSessionOpenId(null); router.push(`/(auth)/pro/session-form?id=${se.id}`); }} style={styles.footBtn}>
                        <Pencil size={14} color={colors.textPrimary} strokeWidth={2.2} />
                        <AppText style={styles.footText}>{t('session.edit', { defaultValue: 'Modifier la date' })}</AppText>
                      </PressableScale>
                      <PressableScale hitSlop={6} onPress={() => openOuting('cancel', head, se.id, sessionRange(se))} style={styles.footBtn}>
                        <CalendarX2 size={14} color={colors.error} strokeWidth={2.2} />
                        <AppText style={[styles.footText, { color: colors.error }]}>{t('booking.cancelOuting', { defaultValue: 'Annuler la sortie' })}</AppText>
                      </PressableScale>
                    </View>
                  ) : null}
                </ScrollView>
              );
            })() : null}
          </Pressable>
        </Pressable>
      </Modal>

      {/* Une sortie entière : message à tous / annulation avec motif (00567). */}
      <Modal visible={!!outing} transparent animationType="slide" onRequestClose={() => setOuting(null)}>
        <Pressable style={styles.backdrop} onPress={() => setOuting(null)}>
          <Animated.View style={imePadding}>
          <Pressable style={styles.sheet} onPress={(e) => e.stopPropagation()}>
            <View style={styles.grab} />
            {outing ? (
              <>
                <AppText style={[styles.sheetTitle, { textTransform: 'none', marginBottom: 2 }]}>
                  {outing.kind === 'write'
                    ? t('booking.writeAllTitle', { defaultValue: 'Message à tous les clients' })
                    : t('booking.cancelOuting', { defaultValue: 'Annuler la sortie' })}
                </AppText>
                <AppText style={styles.outSub} numberOfLines={1}>
                  {outing.head.offering_title ?? '—'} · {outing.when ?? bookingWhen(outing.head.day, outing.head.period, t, outing.head.end_day)}
                </AppText>
                {outing.kind === 'cancel' && (
                  <AppText style={[styles.inputLabel, { marginTop: spacing.md }]}>{t('booking.cancelReasonLabel', { defaultValue: 'Motif (facultatif)' })}</AppText>
                )}
                <AppTextInput
                  style={[styles.input, styles.outInput, outing.kind === 'write' && { marginTop: spacing.md }]}
                  placeholder={outing.kind === 'write'
                    ? t('booking.writeAllPlaceholder', { defaultValue: 'Ex. RDV 8 h au parking du col, prévoyez de l’eau.' })
                    : t('booking.cancelReasonPlaceholder', { defaultValue: 'Ex. Orages annoncés, je vous propose une autre date.' })}
                  placeholderTextColor={colors.textMuted}
                  value={outingText}
                  onChangeText={setOutingText}
                  multiline
                  maxLength={outing.kind === 'write' ? 2000 : 300}
                  autoFocus={outing.kind === 'write'}
                />
                <AppText style={styles.mIntro}>
                  {outing.kind === 'write'
                    ? t('booking.writeAllHint', { defaultValue: 'Chaque client confirmé le reçoit dans sa conversation privée. Ils ne se voient pas entre eux.' })
                    : t('booking.cancelReasonHint', { defaultValue: 'Envoyé à chaque client dans sa conversation.' })}
                </AppText>
                <Pressable
                  style={({ pressed }) => [
                    styles.btnPrimary, styles.btnBig,
                    outing.kind === 'cancel' && { backgroundColor: colors.error },
                    (outingBusy || (outing.kind === 'write' && !outingText.trim())) && { opacity: 0.5 },
                    pressed && styles.pressed,
                  ]}
                  disabled={outingBusy || (outing.kind === 'write' && !outingText.trim())}
                  onPress={() => void submitOuting()}
                >
                  <AppText style={styles.btnPrimaryText}>
                    {outing.kind === 'write'
                      ? t('booking.send', { defaultValue: 'Envoyer' })
                      : t('booking.cancelOutingConfirm', { defaultValue: 'Annuler la sortie' })}
                  </AppText>
                </Pressable>
              </>
            ) : null}
          </Pressable>
          </Animated.View>
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
  fillBox: { backgroundColor: colors.surfaceAlt, borderRadius: radius.lg, padding: spacing.sm + 4, gap: 8 },
  fillHead: { flexDirection: 'row', alignItems: 'baseline', justifyContent: 'space-between', gap: spacing.sm, flexWrap: 'wrap' },
  fillMin: { fontSize: fontSizes.xs, fontWeight: '700' },
  fillTrack: { height: 8, borderRadius: 4, backgroundColor: colors.lineStrong, overflow: 'hidden' },
  fillBar: { height: 8 },
  groupHead: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, paddingHorizontal: spacing.sm + 2, paddingTop: spacing.sm },
  missingRow: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm, marginHorizontal: spacing.sm + 2, marginTop: 6,
    paddingHorizontal: spacing.sm + 2, paddingVertical: spacing.sm, borderRadius: radius.md, backgroundColor: colors.warning + '14',
  },
  missingText: { flex: 1, color: colors.warning, fontSize: fontSizes.xs + 1, fontWeight: '700' },
  removeText: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, fontWeight: '700', paddingHorizontal: spacing.sm + 2, paddingTop: 6 },
  sessionFoot: { flexDirection: 'row', justifyContent: 'space-between', paddingHorizontal: 2 },
  footBtn: { flexDirection: 'row', alignItems: 'center', gap: 6, paddingVertical: 6 },
  footText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700' },
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
  syncRow: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 2, marginTop: spacing.md,
    backgroundColor: colors.surface, borderRadius: radius.card, padding: spacing.sm + 4,
    borderWidth: 1, borderColor: colors.lineStrong, ...shadows.card,
  },
  syncIcon: { width: 32, height: 32, borderRadius: 10, backgroundColor: colors.cta + '1F', alignItems: 'center', justifyContent: 'center' },
  syncTitle: { color: colors.textPrimary, fontSize: fontSizes.sm + 1, fontWeight: '700' },
  syncSub: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, marginTop: 1 },
  outActs: { flexDirection: 'row', gap: spacing.sm },
  outActBtn: {
    flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6,
    backgroundColor: colors.cta + '1F', borderRadius: radius.full, paddingVertical: spacing.sm,
  },
  outActDanger: { backgroundColor: colors.error + '14' },
  outActText: { color: colors.cta, fontSize: fontSizes.sm - 1, fontWeight: '700' },
  outSub: { color: colors.textSecondary, fontSize: fontSizes.sm - 1 },
  outInput: { minHeight: 96, textAlignVertical: 'top' },
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
