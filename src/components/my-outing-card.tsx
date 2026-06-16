import { useMemo, useState, forwardRef, useImperativeHandle } from 'react';
import { View, Text, Pressable, Modal, ScrollView, StyleSheet } from 'react-native';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import * as Burnt from 'burnt';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import {
  Car,
  Users,
  Backpack,
  Bike,
  TrainFront,
  Footprints,
  HelpCircle,
  Compass,
  Clock,
  Check,
  Plus,
  ChevronRight,
  MapPin,
  type LucideIcon,
} from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { spacing, fontSizes, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { transportService } from '@/services/transport-service';
import { gearService } from '@/services/gear-service';

interface Props {
  activityId: string;
  startsAt: string;
  status: string;
  currentUserId: string | null;
  isParticipant: boolean;
  onEditTransport: () => void;
  onEditGearItem: (name: string) => void;
  onAddMaterial: () => void;
  // When set, only the matching stamp renders — used by the split
  // Transport / Matériel tabs so each tab shows only its half of
  // "what I'm doing for this outing".
  view?: 'transport' | 'gear';
}

// Imperative handle so the parent (and sibling components like the
// GroupCard's "Réserver" CTA) can route through Mine's cancel-first
// gate. requestCancelIfNeeded returns true when it opens the cancel
// modal — the caller then knows to NOT proceed with the new action;
// the user has to clear their existing transport first. Returns
// false if no transport is set, in which case the caller is free to
// open whatever sheet they wanted.
export interface MyOutingCardHandle {
  requestCancelIfNeeded: () => boolean;
}

const CAR_TYPES = ['car', 'carpool'] as const;

type StampState = 'set' | 'pending' | 'todo' | 'neutral';

interface StampSubRow {
  Icon: LucideIcon;
  text: string;
}

interface StampItem {
  name: string;
  quantity: number;
}

interface StampDef {
  caption: string;
  Icon: LucideIcon;
  content: string;
  state: StampState;
  subRows?: StampSubRow[];
  // When set, the stamp renders this as a bulleted list (one per line)
  // instead of the `content` string. Used by matériel so each item gets
  // its own row, with overflowCount surfacing how many fall off.
  itemsList?: StampItem[];
  overflowCount?: number;
}

// How many gear items fit nicely in a stamp before we collapse the rest
// into "+N autres". Keeps the card height in check while still giving
// the user a real list, not a single ellipsized line.
const STAMP_ITEMS_CAP = 4;
const STAMP_ITEMS_BEFORE_OVERFLOW = 3;

// Compact French H[h]mm format (e.g. "7h00", "14h30") — same as
// transport-section uses, so departure times read consistently across
// the app whether you're in Mine, Group, or the dense view.
const formatHm = (iso: string | null | undefined): string | null =>
  iso ? dayjs(iso).format('H[h]mm') : null;

// Builds the place + time sub-rows used uniformly across every
// transport mode (driver, passenger, cyclist, walker, transit, other).
// Returns one row per piece of info — time gets its own line so it
// stays visible even when the place name is long enough to ellipsize.
const locationTimeRows = (
  place: string | null | undefined,
  time: string | null,
): StampSubRow[] => {
  const cleanPlace = place?.trim() || null;
  const rows: StampSubRow[] = [];
  if (cleanPlace) rows.push({ Icon: MapPin, text: cleanPlace });
  if (time) rows.push({ Icon: Clock, text: time });
  return rows;
};


const COLOR_AMBER = '#E8A33D';

// Mine — your personal status panel for this outing. The card carries
// only what's about you for this specific activity: when it is, what
// role you've taken, what you're contributing. No activity title or
// meeting point here — those live in the screen header.
//
// The caption slot at the top doubles as a countdown ("AUJOURD'HUI",
// "DEMAIN", "DANS 3 JOURS", "EN COURS") so it earns its space — it's
// label and reminder at once.
//
// Tap targets:
//   TRANSPORT stamp → opens the transport editor sheet directly.
//   MATÉRIEL stamp → opens the "mon matériel" sheet (this card's own),
//     which lists all your declared items. Tapping a line in that
//     sheet opens the existing per-item editor; "+ Ajouter" expands
//     the dense gear view in the parent so you can pick from catalog.
export const MyOutingCard = forwardRef<MyOutingCardHandle, Props>(function MyOutingCard({
  activityId,
  startsAt,
  status,
  currentUserId,
  isParticipant,
  onEditTransport,
  onEditGearItem,
  onAddMaterial,
  view,
}, ref) {
  const { t, i18n } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const queryClient = useQueryClient();
  // Logistics edits (transport / gear) are writable only while the
  // activity is published/in_progress AND its start is still in the
  // future. Once it starts — or once it goes past/cancelled/expired —
  // stamps go non-tappable and the "Ajouter" CTA disappears. Mirrors
  // the DB-side `starts_at > NOW()` gate from migration 00233 so users
  // don't tap into a generic "Operation not permitted".
  const isActive =
    (status === 'published' || status === 'in_progress') &&
    new Date(startsAt).getTime() > Date.now();
  const [showMyGear, setShowMyGear] = useState(false);
  // Pending-request gate: tapping the transport stamp while a seat
  // request is pending opens this modal first. The user must cancel
  // their pending request before changing mode — otherwise we'd leave
  // the driver with a stale "pending" they could later approve.
  const [showCancelPending, setShowCancelPending] = useState(false);
  const [cancellingPending, setCancellingPending] = useState(false);

  const { data: transports = [] } = useQuery({
    queryKey: ['transport', activityId],
    queryFn: () => transportService.getForActivity(activityId),
    enabled: isParticipant,
    staleTime: 0,
  });
  const { data: seatAssignments = [] } = useQuery({
    queryKey: ['seat-requests-accepted', activityId],
    queryFn: () => transportService.getSeatAssignments(activityId),
    enabled: isParticipant,
  });
  const { data: pendingRequests = [] } = useQuery({
    queryKey: ['seat-requests', activityId],
    queryFn: () => transportService.getPendingSeatRequests(activityId),
    enabled: isParticipant,
  });
  const { data: gearDeclared = [] } = useQuery({
    queryKey: ['activity-gear', activityId],
    queryFn: () => gearService.getForActivity(activityId),
    enabled: isParticipant,
  });

  // Cancel-first gate: tapping the transport stamp while ANY transport
  // is set opens a confirmation modal so the user has to explicitly
  // "cancel" before changing. Covers four cases:
  //   - pending      → cancel_pending_seat_request RPC
  //   - accepted     → cancel_accepted_seat RPC (restores driver's seat)
  //   - driver/self  → clearTransport (no side effects)
  // Without the gate, a user could silently swap modes while a pending
  // request lingered with a driver, or while their accepted seat was
  // still on the books.
  const myPending = useMemo(
    () => pendingRequests.find((r) => r.requester_id === currentUserId) ?? null,
    [pendingRequests, currentUserId],
  );
  const myAcceptedSeatLocal = useMemo(
    () => seatAssignments.find((r) => r.requester_id === currentUserId) ?? null,
    [seatAssignments, currentUserId],
  );
  const myTransportLocal = useMemo(
    () => transports.find((p) => p.user_id === currentUserId) ?? null,
    [transports, currentUserId],
  );

  type CancelState = 'pending' | 'accepted' | 'driver' | 'selfMover' | 'none';
  const cancelState: CancelState = useMemo(() => {
    if (myPending) return 'pending';
    if (myAcceptedSeatLocal) return 'accepted';
    if (myTransportLocal?.transport_type && (CAR_TYPES as readonly string[]).includes(myTransportLocal.transport_type)) {
      return 'driver';
    }
    if (myTransportLocal?.transport_type) return 'selfMover';
    return 'none';
  }, [myPending, myAcceptedSeatLocal, myTransportLocal]);

  // Driver name surfaced in the modal copy where applicable. Pending
  // and accepted cases reference a specific driver; driver/self-mover
  // don't.
  const cancelModalDriverName = useMemo(() => {
    if (myPending) return transports.find((p) => p.user_id === myPending.driver_id)?.display_name ?? '?';
    if (myAcceptedSeatLocal) return transports.find((p) => p.user_id === myAcceptedSeatLocal.driver_id)?.display_name ?? '?';
    return null;
  }, [myPending, myAcceptedSeatLocal, transports]);

  const cancelModalModeLabel = useMemo(() => {
    if (cancelState !== 'selfMover' || !myTransportLocal?.transport_type) return null;
    return t(`myOuting.stamp.mode.${myTransportLocal.transport_type}`, {
      defaultValue: myTransportLocal.transport_type,
    });
  }, [cancelState, myTransportLocal, t]);

  const handleCancelTransport = async () => {
    setCancellingPending(true);
    try {
      if (cancelState === 'pending' && myPending) {
        await transportService.cancelPendingSeatRequest(myPending.id);
      } else if (cancelState === 'accepted' && myAcceptedSeatLocal) {
        await transportService.cancelAcceptedSeat(myAcceptedSeatLocal.id);
      } else if (cancelState === 'driver' || cancelState === 'selfMover') {
        await transportService.clearTransport(activityId);
      }
      await queryClient.invalidateQueries({ queryKey: ['seat-requests', activityId] });
      await queryClient.invalidateQueries({ queryKey: ['seat-requests-accepted', activityId] });
      await queryClient.invalidateQueries({ queryKey: ['transport', activityId] });
      setShowCancelPending(false);
      Burnt.toast({
        title: t('myOuting.cancelTransport.toastDone', { defaultValue: 'Annulé' }),
        preset: 'done',
      });
    } catch {
      Burnt.toast({ title: t('auth.unknownError', { defaultValue: 'Erreur' }) });
    } finally {
      setCancellingPending(false);
    }
  };

  const handleTransportStampPress = () => {
    if (!isActive) return;
    if (cancelState !== 'none') {
      setShowCancelPending(true);
    } else {
      onEditTransport();
    }
  };

  // Exposed to parent — lets the GroupCard's "Réserver" tap route
  // through the same cancel-first gate that Mine's transport-stamp
  // tap uses. Returns true if it intercepted (modal opened); false
  // if no transport is set so the caller can proceed.
  useImperativeHandle(ref, () => ({
    requestCancelIfNeeded: () => {
      if (!isActive) return false;
      if (cancelState !== 'none') {
        setShowCancelPending(true);
        return true;
      }
      return false;
    },
  }), [cancelState, isActive]);

  // Caption — countdown / status. Computed against the user's local day
  // boundary so a 22h activity tonight reads "AUJOURD'HUI" right up to
  // midnight, then "EN COURS" once status flips.
  // Returns text + a tone tag the renderer maps to a color: the caption
  // warms up as the activity approaches (cool muted → amber → cta orange
  // → green when active) so the slot acts as both label and pulse.
  const caption = useMemo(() => {
    if (status === 'in_progress') {
      return {
        text: t('myOuting.captionInProgress', { defaultValue: 'En cours' }),
        tone: 'live' as const,
      };
    }
    const days = dayjs(startsAt).startOf('day').diff(dayjs().startOf('day'), 'day');
    if (days < 0) {
      return {
        text: t('myOuting.captionPast', { defaultValue: 'Terminée' }),
        tone: 'past' as const,
      };
    }
    if (days === 0) {
      return {
        text: t('myOuting.captionToday', { defaultValue: "Aujourd'hui" }),
        tone: 'today' as const,
      };
    }
    if (days === 1) {
      return {
        text: t('myOuting.captionTomorrow', { defaultValue: 'Demain' }),
        tone: 'soon' as const,
      };
    }
    if (days <= 7) {
      return {
        text: t('myOuting.captionInDays', {
          count: days,
          defaultValue: `Dans ${days} jours`,
        }),
        tone: 'soon' as const,
      };
    }
    if (days <= 30) {
      return {
        text: t('myOuting.captionInDays', {
          count: days,
          defaultValue: `Dans ${days} jours`,
        }),
        tone: 'far' as const,
      };
    }
    // Far-future activities — short date so the caption doesn't grow
    // ridiculous ("Dans 87 jours" reads as nag, not reminder).
    return {
      text: dayjs(startsAt)
        .locale(i18n.language === 'fr' ? 'fr' : 'en')
        .format(i18n.language === 'fr' ? 'D MMM' : 'MMM D'),
      tone: 'far' as const,
    };
  }, [startsAt, status, t, i18n.language]);

  const captionColor =
    caption.tone === 'live' ? colors.success
    : caption.tone === 'today' ? colors.cta
    : caption.tone === 'soon' ? COLOR_AMBER
    : colors.textMuted;

  const transportStamp = useMemo<StampDef>(() => {
    const empty: StampDef = {
      caption: t('myOuting.stamp.transport', { defaultValue: 'Ton transport' }),
      Icon: Compass,
      content: t('myOuting.stamp.toSettle', { defaultValue: 'À régler' }),
      state: 'todo',
    };
    if (!currentUserId) return empty;

    // For the driver case, count the seats already taken by accepted
    // requesters — that's the user's passenger headcount.
    const myPassengerCount = seatAssignments.filter((r) => r.driver_id === currentUserId).length;

    if (myPending) {
      const driver = transports.find((p) => p.user_id === myPending.driver_id);
      return {
        caption: t('myOuting.stamp.transport', { defaultValue: 'Ton transport' }),
        Icon: Clock,
        content: t('myOuting.stamp.transportPending', {
          driver: driver?.display_name ?? '?',
          defaultValue: `En attente · ${driver?.display_name ?? '?'}`,
        }),
        state: 'pending',
      };
    }

    if (myTransportLocal && (CAR_TYPES as readonly string[]).includes(myTransportLocal.transport_type ?? '')) {
      const subRows: StampSubRow[] = [
        ...locationTimeRows(
          myTransportLocal.transport_from_name,
          formatHm(myTransportLocal.transport_departs_at),
        ),
      ];
      // Passenger count — render even at 0 so the stamp's role as "I'm
      // a driver carrying N people" is consistently visible.
      subRows.push({
        Icon: Users,
        text: t('myOuting.stamp.passengersCount', {
          count: myPassengerCount,
          defaultValue: myPassengerCount === 1 ? '1 passager' : `${myPassengerCount} passagers`,
        }),
      });
      return {
        caption: t('myOuting.stamp.transport', { defaultValue: 'Ton transport' }),
        Icon: Car,
        content: t('myOuting.stamp.transportDriver', { defaultValue: 'Tu conduis' }),
        state: 'set',
        subRows,
      };
    }

    if (myAcceptedSeatLocal) {
      const driver = transports.find((p) => p.user_id === myAcceptedSeatLocal.driver_id);
      const where = locationTimeRows(
        myAcceptedSeatLocal.pickup_from,
        formatHm(myAcceptedSeatLocal.requested_pickup_at),
      );
      return {
        caption: t('myOuting.stamp.transport', { defaultValue: 'Ton transport' }),
        Icon: Users,
        content: t('myOuting.stamp.transportPassenger', {
          driver: driver?.display_name ?? '?',
          defaultValue: `Tu pars avec ${driver?.display_name ?? '?'}`,
        }),
        state: 'set',
        subRows: where.length > 0 ? where : undefined,
      };
    }

    if (myTransportLocal?.transport_type) {
      const Icon =
        myTransportLocal.transport_type === 'bike'
          ? Bike
          : myTransportLocal.transport_type === 'on_foot'
            ? Footprints
            : myTransportLocal.transport_type === 'public_transport'
              ? TrainFront
              : HelpCircle;
      // Self-movers (bike / foot / transit / other) get the same
      // place + time rows as drivers and passengers — coordination
      // signal is just as useful for them.
      const where = locationTimeRows(
        myTransportLocal.transport_from_name,
        formatHm(myTransportLocal.transport_departs_at),
      );
      return {
        caption: t('myOuting.stamp.transport', { defaultValue: 'Ton transport' }),
        Icon,
        content: t(`myOuting.stamp.mode.${myTransportLocal.transport_type}`, {
          defaultValue: myTransportLocal.transport_type,
        }),
        state: 'set',
        subRows: where.length > 0 ? where : undefined,
      };
    }

    return empty;
  }, [myPending, myAcceptedSeatLocal, myTransportLocal, transports, seatAssignments, currentUserId, t]);

  const myGearItems = useMemo(() => {
    if (!currentUserId) return [];
    return gearDeclared
      .filter((g) => g.user_id === currentUserId)
      .map((g) => ({ name: g.gear_name, quantity: g.quantity }));
  }, [gearDeclared, currentUserId]);

  const materialStamp = useMemo<StampDef>(() => {
    if (myGearItems.length === 0) {
      return {
        caption: t('myOuting.stamp.material', { defaultValue: 'Ton matériel' }),
        Icon: Backpack,
        content: t('myOuting.stamp.materialNothing', { defaultValue: 'Tu n\'apportes rien pour le moment' }),
        state: 'neutral',
      };
    }
    // Each item gets its own bulleted row. We show up to STAMP_ITEMS_CAP;
    // beyond that, collapse the tail into "+N autres" and let the my-gear
    // sheet carry the full list on tap. STAMP_ITEMS_BEFORE_OVERFLOW
    // governs how many we show when overflow is present so the "+N"
    // pill actually visible (otherwise we'd show CAP items + cramped
    // overflow line).
    const visible =
      myGearItems.length <= STAMP_ITEMS_CAP
        ? myGearItems
        : myGearItems.slice(0, STAMP_ITEMS_BEFORE_OVERFLOW);
    const overflowCount = myGearItems.length - visible.length;
    return {
      caption: t('myOuting.stamp.material', { defaultValue: 'Ton matériel' }),
      Icon: Backpack,
      content: '',
      state: 'set',
      itemsList: visible,
      overflowCount: overflowCount > 0 ? overflowCount : undefined,
    };
  }, [myGearItems, t]);

  // "Prêt" seal stays scoped to the transport context — gear has no
  // notion of "ready" (it's an open-ended list, can't be measured),
  // so the seal hides entirely on the gear view. AND we don't show
  // it on a combined view either; transport-set is no longer treated
  // as a proxy for overall readiness.
  const isReady = view === 'transport' && transportStamp.state === 'set';

  if (!isParticipant) return null;

  return (
    <View style={styles.cardWrapper}>
      <View style={styles.card}>
        <View style={styles.headerBand}>
          {/* Row 1: title + small Prêt seal (when ready). */}
          <View style={styles.headerTopRow}>
            <Text style={styles.cardTitle} numberOfLines={1}>
              {t('myOuting.cardTitle', { defaultValue: 'Tes préparatifs' })}
            </Text>
            {isReady && (
              <View style={[styles.seal, { borderColor: colors.success }]}>
                <Check size={10} color={colors.success} strokeWidth={3} />
                <Text style={[styles.sealText, { color: colors.success }]}>
                  {t('myOuting.ready', { defaultValue: 'Prêt' })}
                </Text>
              </View>
            )}
          </View>
          {/* Row 2: countdown caption — its own line so the title isn't
              compressed when the caption gets long ("Dans 14 jours"). */}
          <Text style={[styles.caption, { color: captionColor }]} numberOfLines={1}>
            {caption.text}
          </Text>
        </View>
        <View style={styles.body}>
          <View style={styles.stampsRow}>
            {view !== 'gear' && (
              <Stamp
                stamp={transportStamp}
                onPress={handleTransportStampPress}
                colors={colors}
                styles={styles}
                t={t}
              />
            )}
            {view !== 'transport' && (
              <Stamp
                stamp={materialStamp}
                onPress={() => setShowMyGear(true)}
                colors={colors}
                styles={styles}
                t={t}
              />
            )}
          </View>
        </View>
      </View>

      {/* Mon matériel modal — full list of what I bring, each row tappable
          to edit, plus "Ajouter" to bring something new. Centered floating
          card on a tinted scrim, matching the visual language of the
          trust-pillar popups in the profile. */}
      <Modal
        visible={showMyGear}
        animationType="fade"
        transparent
        onRequestClose={() => setShowMyGear(false)}
      >
        <Pressable style={styles.backdrop} onPress={() => setShowMyGear(false)}>
          <Pressable style={styles.sheet} onPress={(e) => e.stopPropagation()}>
            <Text style={styles.sheetTitle}>
              {t('myOuting.gearListTitle', { defaultValue: 'Ton matériel' })}
            </Text>

            {myGearItems.length === 0 ? (
              <Text style={styles.sheetEmpty}>
                {t('myOuting.gearListEmpty', {
                  defaultValue: 'Tu n\'apportes rien pour le moment.',
                })}
              </Text>
            ) : (
              <ScrollView style={styles.gearList} showsVerticalScrollIndicator={false}>
                {myGearItems.map((g, i) => (
                  <Pressable
                    key={g.name}
                    style={[styles.gearListRow, i < myGearItems.length - 1 && styles.gearListRowBorder]}
                    onPress={() => {
                      if (!isActive) return;
                      setShowMyGear(false);
                      onEditGearItem(g.name);
                    }}
                    disabled={!isActive}
                    hitSlop={4}
                  >
                    <View style={styles.gearListIconWrap}>
                      <Backpack size={14} color={colors.success} strokeWidth={2.2} />
                    </View>
                    <Text style={styles.gearListName} numberOfLines={1}>
                      {g.name}
                    </Text>
                    {g.quantity > 1 && (
                      <Text style={styles.gearListQty}>×{g.quantity}</Text>
                    )}
                    <ChevronRight size={14} color={colors.textMuted} strokeWidth={2} />
                  </Pressable>
                ))}
              </ScrollView>
            )}

            {isActive && (
              <Pressable
                style={styles.addBtn}
                onPress={() => {
                  setShowMyGear(false);
                  onAddMaterial();
                }}
                hitSlop={4}
              >
                <Plus size={14} color={colors.cta} strokeWidth={2.6} />
                <Text style={styles.addBtnText}>
                  {t('myOuting.addMaterial', { defaultValue: 'Ajouter du matériel' })}
                </Text>
              </Pressable>
            )}
          </Pressable>
        </Pressable>
      </Modal>

      {/* Cancel-transport modal — tapping the transport stamp while
          ANY transport is set (pending request, accepted seat, driver,
          or self-mover) opens this first. The user must explicitly
          cancel their current state before they can pick a different
          mode. Copy adapts per state; the action dispatches to the
          right service call. */}
      <Modal
        visible={showCancelPending}
        animationType="fade"
        transparent
        onRequestClose={() => setShowCancelPending(false)}
      >
        <Pressable style={styles.backdrop} onPress={() => setShowCancelPending(false)}>
          <Pressable style={styles.sheet} onPress={(e) => e.stopPropagation()}>
            <Text style={styles.sheetTitle}>
              {t(`myOuting.cancelTransport.title.${cancelState}`, {
                mode: cancelModalModeLabel ?? '',
                defaultValue: 'Annuler ton transport',
              })}
            </Text>
            <Text style={styles.pendingCancelBody}>
              {t(`myOuting.cancelTransport.body.${cancelState}`, {
                driver: cancelModalDriverName ?? '?',
                mode: cancelModalModeLabel ?? '',
                defaultValue: 'Annule ton transport actuel pour pouvoir en choisir un autre.',
              })}
            </Text>
            <View style={styles.pendingCancelActions}>
              <Pressable
                style={styles.pendingCancelKeep}
                onPress={() => setShowCancelPending(false)}
                hitSlop={4}
              >
                <Text style={styles.pendingCancelKeepText}>
                  {t('myOuting.cancelTransport.keep', { defaultValue: 'Garder' })}
                </Text>
              </Pressable>
              <Pressable
                style={[styles.pendingCancelConfirm, cancellingPending && { opacity: 0.5 }]}
                onPress={handleCancelTransport}
                disabled={cancellingPending}
                hitSlop={4}
              >
                <Text style={styles.pendingCancelConfirmText}>
                  {t(`myOuting.cancelTransport.confirm.${cancelState}`, { defaultValue: 'Annuler' })}
                </Text>
              </Pressable>
            </View>
          </Pressable>
        </Pressable>
      </Modal>
    </View>
  );
});

interface StampProps {
  stamp: StampDef;
  onPress: () => void;
  colors: AppColors;
  styles: ReturnType<typeof createStyles>;
  t: (k: string, opts?: Record<string, unknown>) => string;
}

function Stamp({ stamp, onPress, colors, styles, t }: StampProps) {
  const accent =
    stamp.state === 'set' ? colors.success
    : stamp.state === 'pending' || stamp.state === 'todo' ? COLOR_AMBER
    : colors.textMuted;

  const isFilledLook = stamp.state === 'set' || stamp.state === 'pending';
  const dashedBorder = stamp.state === 'todo' || stamp.state === 'neutral';
  const mutedContent = stamp.state === 'todo' || stamp.state === 'neutral';
  const hasItemsList = stamp.itemsList && stamp.itemsList.length > 0;

  return (
    <Pressable
      onPress={onPress}
      style={({ pressed }) => [
        styles.stamp,
        isFilledLook && {
          backgroundColor: accent + '14',
          borderColor: accent + '4D',
        },
        dashedBorder && { borderStyle: 'dashed' },
        pressed && { opacity: 0.6 },
      ]}
      hitSlop={4}
    >
      <View style={styles.stampHeaderRow}>
        <stamp.Icon
          size={14}
          color={isFilledLook ? accent : colors.textMuted}
          strokeWidth={2.2}
        />
        <Text
          style={[
            styles.stampCaption,
            { color: isFilledLook ? accent : colors.textMuted },
          ]}
        >
          {stamp.caption}
        </Text>
      </View>

      {hasItemsList ? (
        <View style={styles.stampItemsList}>
          {stamp.itemsList!.map((item, i) => (
            <View key={`${item.name}-${i}`} style={styles.stampItemRow}>
              <Text style={[styles.stampItemBullet, { color: accent }]}>•</Text>
              <Text style={styles.stampItemName} numberOfLines={1}>
                {item.name}
                {item.quantity > 1 ? ` ×${item.quantity}` : ''}
              </Text>
            </View>
          ))}
          {stamp.overflowCount && stamp.overflowCount > 0 && (
            <Text style={styles.stampItemOverflow} numberOfLines={1}>
              {t('myOuting.stamp.itemsOverflow', {
                count: stamp.overflowCount,
                defaultValue: `+ ${stamp.overflowCount} autres`,
              })}
            </Text>
          )}
        </View>
      ) : (
        <Text
          style={[
            styles.stampContent,
            mutedContent ? { color: colors.textSecondary } : { color: colors.textPrimary },
          ]}
          numberOfLines={2}
        >
          {stamp.content}
        </Text>
      )}

      {stamp.subRows && stamp.subRows.length > 0 && (
        <View style={styles.stampSubRowsCol}>
          {stamp.subRows.map((row, i) => (
            <View key={i} style={styles.stampSubRow}>
              <row.Icon size={11} color={colors.textSecondary} strokeWidth={2.2} />
              <Text style={styles.stampSubText} numberOfLines={1}>
                {row.text}
              </Text>
            </View>
          ))}
        </View>
      )}

      <View style={styles.stampMarkRow}>
        {stamp.state === 'set' && <Check size={14} color={accent} strokeWidth={3} />}
        {stamp.state === 'pending' && <Clock size={14} color={accent} strokeWidth={2.4} />}
        {/* Empty states (nothing set yet) surface an explicit "Ajouter"
            chip instead of a subtle dot — makes the tap-to-add obvious.
            The chip is visual; the whole stamp is the press target. */}
        {(stamp.state === 'todo' || stamp.state === 'neutral') && (
          <View style={styles.addStampChip}>
            <Plus size={12} color={colors.cta} strokeWidth={2.6} />
            <Text style={styles.addStampChipText}>
              {t('myOuting.addChip', { defaultValue: 'Ajouter' })}
            </Text>
          </View>
        )}
      </View>
    </Pressable>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  cardWrapper: { marginBottom: spacing.md },
  // Header band — surfaceAlt bg sets it apart from the card body
  // (slightly darker), bottom divider seals it as its own zone, and
  // the uppercase letter-spaced title gives it a distinct "headline"
  // feel within the system font.
  headerBand: {
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm + 2,
    backgroundColor: colors.surfaceAlt,
    borderBottomWidth: 1,
    borderBottomColor: colors.line,
    gap: 2,
  },
  headerTopRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  cardTitle: {
    flex: 1,
    color: colors.textPrimary,
    fontSize: fontSizes.xs + 1,
    fontWeight: '800',
    letterSpacing: 1.4,
    textTransform: 'uppercase',
  },
  // Body — the actual card content, separated from the header band
  // by the bg-color step and the divider.
  body: {
    padding: spacing.md - 2,
  },
  card: {
    backgroundColor: colors.surface,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.line,
    overflow: 'hidden',
  },
  caption: {
    color: colors.textMuted,
    fontSize: 9.5,
    fontWeight: '700',
    letterSpacing: 1.5,
    textTransform: 'uppercase',
  },
  seal: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    borderWidth: 1.5,
    borderRadius: 999,
    paddingHorizontal: 8,
    paddingVertical: 2,
  },
  sealText: {
    fontSize: 9.5,
    fontWeight: '800',
    letterSpacing: 1,
    textTransform: 'uppercase',
  },

  stampsRow: {
    flexDirection: 'row',
    gap: spacing.sm + 2,
  },
  stamp: {
    flex: 1,
    minHeight: 96,
    borderRadius: radius.md,
    borderWidth: 1.5,
    borderColor: colors.line,
    paddingVertical: spacing.sm + 2,
    paddingHorizontal: spacing.sm + 2,
    backgroundColor: 'transparent',
  },
  stampHeaderRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    marginBottom: 6,
  },
  stampCaption: {
    fontSize: 9.5,
    fontWeight: '800',
    letterSpacing: 1.4,
    textTransform: 'uppercase',
  },
  stampContent: {
    fontSize: fontSizes.sm,
    fontWeight: '700',
    lineHeight: 18,
    letterSpacing: -0.1,
    flexShrink: 1,
  },
  // Bulleted items list — bullet rendered as a sibling Text in a flex row
  // (not as inline Text inside the name Text), since inline-text-in-text
  // can swallow the bullet on some RN/iOS rendering paths.
  stampItemsList: {
    gap: 2,
  },
  stampItemRow: {
    flexDirection: 'row',
    alignItems: 'baseline',
    gap: 5,
  },
  stampItemBullet: {
    fontSize: fontSizes.sm + 2,
    fontWeight: '800',
    lineHeight: 17,
  },
  stampItemName: {
    flex: 1,
    color: colors.textPrimary,
    fontSize: fontSizes.xs + 1,
    fontWeight: '600',
    lineHeight: 17,
    letterSpacing: -0.05,
  },
  stampItemOverflow: {
    color: colors.textMuted,
    fontSize: fontSizes.xs,
    fontWeight: '600',
    fontStyle: 'italic',
    marginTop: 2,
  },
  stampSubRowsCol: {
    marginTop: 4,
    gap: 2,
  },
  stampSubRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  stampSubText: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '500',
    flexShrink: 1,
  },
  stampMarkRow: {
    marginTop: 'auto',
    paddingTop: 6,
    flexDirection: 'row',
    justifyContent: 'flex-end',
    alignItems: 'center',
  },
  addStampChip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 3,
    backgroundColor: colors.cta + '14',
    borderRadius: radius.sm,
    paddingHorizontal: 8,
    paddingVertical: 3,
  },
  addStampChipText: {
    color: colors.cta,
    fontSize: 11,
    fontWeight: '800',
    letterSpacing: 0.3,
  },

  // My-gear modal — centered floating card on a near-opaque scrim so
  // the active modal carries the user's attention without competing
  // with the cards underneath.
  backdrop: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.92)',
    alignItems: 'center',
    justifyContent: 'center',
    padding: spacing.lg,
  },
  sheet: {
    width: '100%',
    maxWidth: 380,
    maxHeight: '85%',
    backgroundColor: colors.background,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.line,
    padding: spacing.lg,
  },
  sheetTitle: {
    color: colors.textPrimary,
    fontSize: fontSizes.lg,
    fontWeight: 'bold',
    marginBottom: spacing.md,
  },

  // Pending-cancel modal
  pendingCancelBody: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
    lineHeight: 20,
    marginBottom: spacing.lg,
  },
  pendingCancelActions: {
    flexDirection: 'row',
    gap: spacing.sm,
  },
  pendingCancelKeep: {
    flex: 1,
    height: 44,
    borderRadius: radius.md,
    backgroundColor: colors.surfaceAlt,
    borderWidth: 1,
    borderColor: colors.line,
    alignItems: 'center',
    justifyContent: 'center',
  },
  pendingCancelKeepText: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '600',
  },
  pendingCancelConfirm: {
    flex: 1.4,
    height: 44,
    borderRadius: radius.md,
    backgroundColor: colors.error,
    alignItems: 'center',
    justifyContent: 'center',
  },
  pendingCancelConfirmText: {
    color: '#FFFFFF',
    fontSize: fontSizes.sm,
    fontWeight: '700',
  },
  sheetEmpty: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
    fontStyle: 'italic',
    marginBottom: spacing.md,
  },
  gearList: {
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.line,
    paddingHorizontal: spacing.md,
    marginBottom: spacing.md,
  },
  gearListRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm + 2,
    paddingVertical: spacing.sm + 2,
  },
  gearListRowBorder: {
    borderBottomWidth: 1,
    borderBottomColor: colors.line,
  },
  gearListIconWrap: {
    width: 24,
    height: 24,
    borderRadius: 8,
    backgroundColor: colors.success + '14',
    alignItems: 'center',
    justifyContent: 'center',
  },
  gearListName: {
    flex: 1,
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '600',
  },
  gearListQty: {
    color: colors.success,
    fontSize: fontSizes.sm,
    fontWeight: '700',
  },
  addBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    backgroundColor: colors.cta + '14',
    borderRadius: radius.md,
    paddingVertical: spacing.sm + 4,
  },
  addBtnText: {
    color: colors.cta,
    fontSize: fontSizes.sm,
    fontWeight: '700',
  },
});
