import { useMemo, useState } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { router } from 'expo-router';
import dayjs from 'dayjs';
import * as Burnt from 'burnt';
import { Users, MapPin, Clock, Check, ChevronDown, Car, Armchair, Bike, TrainFront, Footprints, HelpCircle, Plus, X, type LucideIcon, Backpack } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { spacing, fontSizes, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { transportService } from '@/services/transport-service';
import { gearService } from '@/services/gear-service';
import { participationService } from '@/services/participation-service';
import { UserAvatar } from './user-avatar';
import { ringColorFor } from './profile-hero';
import { supabase } from '@/services/supabase';
import { getFriendlyError } from '@/utils/friendly-error';

interface Props {
  activityId: string;
  onReportMissing?: () => void;
  currentUserId: string | null;
  isParticipant: boolean;
  // True when logistics edits are still allowed — published / in_progress
  // status AND start time still in the future. Once the activity starts
  // (or the status flips to cancelled/finished/expired), the DB rejects
  // transport / gear / seat-request mutations, so the affordances hide.
  isActive: boolean;
  activeSubTab: 'transport' | 'gear';
  onActiveSubTabChange: (tab: 'transport' | 'gear') => void;
  onReserveSeat: (driverId: string) => void;
  onAddGear: () => void;
  onEditGearItem: (name: string, isShared?: boolean) => void;
  // When false, hides the internal folder-style sub-tab bar — used by
  // the parent when the top-level activity tabs (Transport / Matériel)
  // already do that job and rendering a second tab strip would be
  // visually redundant. Defaults to true for backwards compat.
  showSubTabBar?: boolean;
}

const CAR_TYPES = ['car'] as const;


// The sibling card to MyOutingCard. Mine is "what I'm doing for this
// outing"; Group is "what everyone else is doing, and where the group
// still needs help". This is where the active coordination happens —
// reserve a seat from a driver, claim a missing safety item.
//
// Compositional rule: anything that requires interpreting other
// participants' state lives here, not in Mine. Mine stays personal
// and calm; Group is where the user goes when they want to act on
// the group's behalf.
export function GroupCard({
  activityId,
  onReportMissing,
  currentUserId,
  isParticipant,
  isActive,
  activeSubTab,
  onActiveSubTabChange,
  onReserveSeat,
  onAddGear,
  onEditGearItem,
  showSubTabBar = true,
}: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  // Collapse state for the Matériel sub-sections. Inventaire opens by
  // default (it's the action surface — claim missing items, see the
  // covered list); the bringer recaps stay closed by default since
  // they're info-shaped and only useful when the user is curious
  // about a specific person's contribution.
  const [expandedBringers, setExpandedBringers] = useState<Set<string>>(new Set());
  const toggleBringer = (userId: string) => {
    setExpandedBringers((prev) => {
      const next = new Set(prev);
      if (next.has(userId)) next.delete(userId);
      else next.add(userId);
      return next;
    });
  };

  // Driver pills always render fully expanded (full name, departure city +
  // time on their own rows) — no collapse. The passenger thread stays
  // collapsed behind an explicit "Voir tous…" button (a bare chevron got
  // missed in testing; the labelled button reads as tappable).
  const [expandedPassengersByDriver, setExpandedPassengersByDriver] = useState<Set<string>>(new Set());
  const togglePassengersForDriver = (driverId: string) => {
    setExpandedPassengersByDriver((prev) => {
      const next = new Set(prev);
      if (next.has(driverId)) next.delete(driverId);
      else next.add(driverId);
      return next;
    });
  };

  const { data: transports = [] } = useQuery({
    queryKey: ['transport', activityId],
    queryFn: () => transportService.getForActivity(activityId),
    enabled: isParticipant,
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
  const { data: missingItems = [] } = useQuery({
    queryKey: ['gear-missing', activityId],
    queryFn: () => gearService.getMissing(activityId),
    enabled: isParticipant,
  });
  const removeMissing = async (name: string) => {
    try {
      await gearService.removeMissing(activityId, name);
      await queryClient.invalidateQueries({ queryKey: ['gear-missing', activityId] });
    } catch (err) {
      Burnt.toast({ title: getFriendlyError(err, 'generic'), preset: 'error' });
    }
  };
  const { data: participants = [] } = useQuery({
    queryKey: ['participants', activityId],
    queryFn: () => participationService.getForActivity(activityId),
    enabled: isParticipant,
    staleTime: 15_000,
  });

  // Reliability scores keyed by user_id, used for the trust ring around
  // each driver's avatar. Reads from public_profiles (00173 added the
  // column) so we don't need a per-driver RPC. Stale cache fine since
  // scores update slowly.
  const transportUserIdsKey = useMemo(
    () => transports.map((p) => p.user_id).sort().join(','),
    [transports],
  );
  const { data: reliabilityScores = [] } = useQuery({
    queryKey: ['public-profile-scores', transportUserIdsKey],
    queryFn: async () => {
      const ids = transports.map((p) => p.user_id);
      if (ids.length === 0) return [];
      const { data } = await supabase
        .from('public_profiles')
        .select('id, reliability_score')
        .in('id', ids);
      return (data ?? []) as { id: string; reliability_score: number | null }[];
    },
    enabled: isParticipant && transports.length > 0,
    staleTime: 60_000,
  });
  const reliabilityById = useMemo(() => {
    const map = new Map<string, number | null>();
    reliabilityScores.forEach((p) => map.set(p.id, p.reliability_score));
    return map;
  }, [reliabilityScores]);

  // Drivers offering rides — INCLUDES the current user when they're
  // a driver (rendered with a "Toi" marker). Sort by departure time
  // ascending so the earliest meet-up surfaces first.
  const drivers = useMemo(() => {
    const acceptedByDriver = new Map<string, number>();
    seatAssignments.forEach((r) =>
      acceptedByDriver.set(r.driver_id, (acceptedByDriver.get(r.driver_id) ?? 0) + 1),
    );
    return transports
      .filter((p) => {
        if (!p.transport_type || !(CAR_TYPES as readonly string[]).includes(p.transport_type)) return false;
        const offered = (p.transport_seats ?? 0) + (acceptedByDriver.get(p.user_id) ?? 0);
        return offered > 0;
      })
      .map((p) => ({
        ...p,
        accepted: acceptedByDriver.get(p.user_id) ?? 0,
        free: p.transport_seats ?? 0,
        capacity: (p.transport_seats ?? 0) + (acceptedByDriver.get(p.user_id) ?? 0),
      }))
      .sort((a, b) => {
        const ta = a.transport_departs_at ? new Date(a.transport_departs_at).getTime() : Infinity;
        const tb = b.transport_departs_at ? new Date(b.transport_departs_at).getTime() : Infinity;
        return ta - tb;
      });
  }, [transports, seatAssignments]);

  // Self-going modes (bike / foot / public / other) — INCLUDES the
  // current user when they self-move. Small one-line chips so the
  // user can see who's coming under their own steam, including their
  // own entry if applicable.
  const selfMovers = useMemo(() => {
    return transports.filter((p) => {
      if (!p.transport_type) return false;
      return !(CAR_TYPES as readonly string[]).includes(p.transport_type);
    });
  }, [transports]);

  // Per-driver passenger list — looked up from accepted seat assignments
  // and joined to display info. Rendered as small rows under each driver
  // (name · pickup place · pickup time).
  const passengersByDriver = useMemo(() => {
    const map = new Map<string, typeof seatAssignments>();
    seatAssignments.forEach((r) => {
      const list = map.get(r.driver_id) ?? [];
      list.push(r);
      map.set(r.driver_id, list);
    });
    return map;
  }, [seatAssignments]);

  // Free-seats summary at the top of the Transport tab — gives the user
  // a one-glance answer to "is there capacity, and where from?". Cities
  // come from each driver's transport_from_name (deduped, ordered by
  // first appearance — the sort by departs_at carries through).
  const totalFreeSeats = useMemo(
    () => drivers.reduce((sum, d) => sum + d.free, 0),
    [drivers],
  );
  const departureCities = useMemo(() => {
    const seen = new Set<string>();
    const ordered: string[] = [];
    drivers.forEach((d) => {
      const city = d.transport_from_name?.trim();
      if (city && !seen.has(city) && d.free > 0) {
        seen.add(city);
        ordered.push(city);
      }
    });
    return ordered;
  }, [drivers]);

  // Bucket self-movers (bike / foot / transit / other) so each category
  // gets its own caption header. Empty buckets simply don't render.
  const moverBuckets = useMemo(() => {
    const buckets: Record<'bike' | 'on_foot' | 'public_transport' | 'other', typeof selfMovers> = {
      bike: [],
      on_foot: [],
      public_transport: [],
      other: [],
    };
    selfMovers.forEach((p) => {
      const key = (p.transport_type === 'bike' || p.transport_type === 'on_foot' || p.transport_type === 'public_transport')
        ? p.transport_type
        : 'other';
      buckets[key].push(p);
    });
    return buckets;
  }, [selfMovers]);

  // Common inventory — only SHARED gear. Personal items (helmet,
  // harness) belong on each user's personal list, not aggregated as a
  // group total. Sorted alphabetically. Each row carries its per-user
  // breakdown so the row can render one avatar+qty pill per bringer.
  type InventoryBringer = {
    user_id: string;
    display_name: string;
    avatar_url: string | null;
    quantity: number;
  };
  const groupItems = useMemo(() => {
    // Keyed case-insensitively so "corde 60m" and "Corde 60m" merge into one
    // tile (display name = first seen) — keeps counts honest when names were
    // typed by different people. (Scott's corde test, 2026-07-09.)
    const map = new Map<string, { name: string; bringers: InventoryBringer[] }>();
    gearDeclared.forEach((g) => {
      if (!g.is_shared) return;
      const entry = map.get(g.gear_name.trim().toLowerCase());
      const bringer: InventoryBringer = {
        user_id: g.user_id,
        display_name: g.display_name,
        avatar_url: g.avatar_url,
        quantity: g.quantity,
      };
      if (entry) entry.bringers.push(bringer);
      else map.set(g.gear_name.trim().toLowerCase(), { name: g.gear_name, bringers: [bringer] });
    });
    return Array.from(map.values()).sort((a, b) =>
      a.name.localeCompare(b.name, 'fr', { sensitivity: 'base' }),
    );
  }, [gearDeclared]);

  // "Qui apporte quoi" recap — group declared gear by user_id,
  // sorted by contribution count descending so heavy contributors
  // anchor the top. Includes self (with TOI tag at render time)
  // for confirmation that their commitment is registered.
  // Bringer recap — group declared gear by user_id, sorted by
  // contribution count descending so heavy contributors anchor the
  // top. Includes self (with TOI tag at render time) for confirmation
  // that their commitment is registered.
  const bringers = useMemo(() => {
    const map = new Map<string, {
      user_id: string;
      display_name: string;
      avatar_url: string | null;
      items: { name: string; quantity: number; is_shared: boolean }[];
    }>();
    gearDeclared.forEach((g) => {
      const item = { name: g.gear_name, quantity: g.quantity, is_shared: g.is_shared };
      const existing = map.get(g.user_id);
      if (existing) {
        existing.items.push(item);
      } else {
        map.set(g.user_id, {
          user_id: g.user_id,
          display_name: g.display_name,
          avatar_url: g.avatar_url,
          items: [item],
        });
      }
    });
    return Array.from(map.values()).sort((a, b) => b.items.length - a.items.length);
  }, [gearDeclared]);

  const myAcceptedSeat = useMemo(
    () => seatAssignments.find((r) => r.requester_id === currentUserId) ?? null,
    [seatAssignments, currentUserId],
  );
  const myPending = useMemo(
    () => pendingRequests.find((r) => r.requester_id === currentUserId) ?? null,
    [pendingRequests, currentUserId],
  );

  // Inline driver-side incoming requests — visible only to the driver
  // for this activity. Lets them act without context-switching to the
  // messagerie tab. RLS filters seat_requests to (requester=me OR
  // driver=me); when I'm the driver of this activity, this collects
  // the "incoming" rows.
  const myDriverPending = useMemo(
    () => pendingRequests.filter((r) => r.driver_id === currentUserId),
    [pendingRequests, currentUserId],
  );
  const queryClient = useQueryClient();
  const [pendingActionId, setPendingActionId] = useState<string | null>(null);

  const handleAcceptIncoming = async (requestId: string) => {
    setPendingActionId(requestId);
    try {
      const conversationId = await transportService.acceptSeatRequest(requestId);
      await queryClient.invalidateQueries({ queryKey: ['seat-requests', activityId] });
      await queryClient.invalidateQueries({ queryKey: ['seat-requests-accepted', activityId] });
      await queryClient.invalidateQueries({ queryKey: ['transport', activityId] });
      await queryClient.invalidateQueries({ queryKey: ['transport-summary', activityId] });
      Burnt.toast({ title: t('transport.seatAccepted', { defaultValue: 'Place confirmée' }), preset: 'done' });
      if (conversationId) {
        router.push(`/(auth)/conversation/${conversationId}`);
      }
    } catch (err) {
      Burnt.toast({ title: getFriendlyError(err, 'generic') });
    } finally {
      setPendingActionId(null);
    }
  };

  const handleDeclineIncoming = async (requestId: string) => {
    setPendingActionId(requestId);
    try {
      await transportService.declineSeatRequest(requestId);
      await queryClient.invalidateQueries({ queryKey: ['seat-requests', activityId] });
    } catch (err) {
      Burnt.toast({ title: getFriendlyError(err, 'generic') });
    } finally {
      setPendingActionId(null);
    }
  };

  // Whether the current user is allowed to request a seat right now —
  // mirrors TransportSection's existing rule so the affordance behaves
  // consistently with the dense view. `isActive` gates the affordance
  // for terminated activities (request_seat would fail server-side).
  const canReserve = useMemo(() => {
    if (!currentUserId || !isActive) return false;
    const myTransport = transports.find((p) => p.user_id === currentUserId);
    const isMyselfDriver =
      myTransport && (CAR_TYPES as readonly string[]).includes(myTransport.transport_type ?? '');
    return !isMyselfDriver && !myAcceptedSeat;
  }, [transports, myAcceptedSeat, currentUserId, isActive]);

  if (!isParticipant) return null;

  // Render the card even when both transport and gear are empty —
  // it carries the per-section empty hints that tell the user nothing
  // has been added yet. Hiding the whole card made the surface read
  // as broken on fresh activities.

  return (
    <View style={styles.cardWrapper}>
      <View style={styles.card}>
        {/* Header band — same surfaceAlt + uppercase-letter-spaced
            treatment as my-outing-card so the two cards read as
            siblings. Title on the left, people count on the right. */}
        <View style={styles.headerBand}>
          <Text style={styles.cardTitle} numberOfLines={1}>
            {t('group.cardTitle', { defaultValue: 'Préparatifs de groupe' })}
          </Text>
          <View style={styles.headerRight}>
            <Users size={14} color={colors.textSecondary} strokeWidth={2.2} />
            <Text style={styles.peopleCount}>{participants.length}</Text>
          </View>
        </View>

        {/* Folder-tab strip — square tabs sit on a surfaceAlt band
            with a 1px bottom divider. The active tab's bg matches
            the content area below (surface) and its negative
            margin-bottom punches through the divider, creating the
            classic "open folder" look where the active tab visually
            merges with content. Inactive tab stays on the surfaceAlt
            band with a visible divider beneath, looking tucked. */}
        {showSubTabBar && (
          <View style={styles.tabBand}>
            <Pressable
              onPress={() => onActiveSubTabChange('transport')}
              style={[styles.folderTab, activeSubTab === 'transport' && styles.folderTabActive]}
              hitSlop={4}
            >
              <Text style={[
                styles.folderTabLabel,
                activeSubTab === 'transport' && styles.folderTabLabelActive,
              ]}>
                {t('group.transport', { defaultValue: 'Transport' })}
              </Text>
            </Pressable>
            <Pressable
              onPress={() => onActiveSubTabChange('gear')}
              style={[styles.folderTab, activeSubTab === 'gear' && styles.folderTabActive]}
              hitSlop={4}
            >
              <Text style={[
                styles.folderTabLabel,
                activeSubTab === 'gear' && styles.folderTabLabelActive,
              ]}>
                {t('group.gear', { defaultValue: 'Matériel' })}
              </Text>
            </Pressable>
          </View>
        )}

        {activeSubTab === 'transport' && (
          <View style={styles.tabContent}>
            {/* Inline driver-side incoming requests — visible only to
                the driver of this activity, so they can accept / decline
                without context-switching to the messagerie tab. Sits
                above the "Voitures" category since it's the action
                surface for an active driver. */}
            {myDriverPending.length > 0 && (
              <View style={styles.incomingRequests}>
                <Text style={styles.incomingRequestsLabel}>
                  {t('group.incomingRequests', {
                    count: myDriverPending.length,
                    defaultValue: myDriverPending.length === 1 ? '1 demande reçue' : `${myDriverPending.length} demandes reçues`,
                  })}
                </Text>
                {myDriverPending.map((req) => {
                  const subtitleParts = [
                    req.pickup_from,
                    req.requested_pickup_at ? dayjs(req.requested_pickup_at).format('H[h]mm') : null,
                  ].filter(Boolean);
                  const isActing = pendingActionId === req.id;
                  return (
                    <View key={req.id} style={styles.incomingRequestCard}>
                      <UserAvatar
                        size={28}
                        name={req.requester_name}
                        avatarUrl={req.requester_avatar}
                      />
                      <View style={styles.incomingRequestInfo}>
                        <Text style={styles.incomingRequestName} numberOfLines={1}>
                          {req.requester_name}
                          {subtitleParts.length > 0 ? ` · ${subtitleParts.join(' · ')}` : ''}
                        </Text>
                        {req.message && (
                          <Text style={styles.incomingRequestMessage} numberOfLines={2}>
                            {req.message}
                          </Text>
                        )}
                      </View>
                      <View style={styles.incomingRequestActions}>
                        <Pressable
                          style={[styles.incomingAcceptBtn, isActing && styles.incomingActionDisabled]}
                          onPress={() => handleAcceptIncoming(req.id)}
                          disabled={isActing}
                          hitSlop={6}
                        >
                          <Check size={16} color={colors.cta} strokeWidth={3} />
                        </Pressable>
                        <Pressable
                          style={[styles.incomingDeclineBtn, isActing && styles.incomingActionDisabled]}
                          onPress={() => handleDeclineIncoming(req.id)}
                          disabled={isActing}
                          hitSlop={6}
                        >
                          <X size={16} color={colors.textMuted} strokeWidth={3} />
                        </Pressable>
                      </View>
                    </View>
                  );
                })}
              </View>
            )}

            {drivers.length > 0 && (
              <View style={styles.transportCategory}>
                <View style={styles.transportCategoryHeader}>
                  <Car size={13} color={colors.textPrimary} strokeWidth={2.4} />
                  <Text style={styles.transportCategoryLabel}>
                    {t('group.transportCategory.car', { defaultValue: 'Voitures' })}
                  </Text>
                  <Text style={styles.transportCategoryCount}>· {drivers.length}</Text>
                  {totalFreeSeats > 0 && (
                    <Text style={styles.freeSeatsInline}>
                      {' · '}{t('group.freeSeatsCount', {
                        count: totalFreeSeats,
                        defaultValue: totalFreeSeats === 1 ? '1 place libre' : `${totalFreeSeats} places libres`,
                      })}
                    </Text>
                  )}
                </View>
                {drivers.map((d) => {
              const isSelf = d.user_id === currentUserId;
              const isMyDriver = myAcceptedSeat?.driver_id === d.user_id;
              const isPendingFromMe = myPending?.driver_id === d.user_id;
              const isFull = d.free === 0;
              const score = reliabilityById.get(d.user_id) ?? null;
              const ringColor = score !== null ? ringColorFor(score) : null;
              const driverPassengers = passengersByDriver.get(d.user_id) ?? [];
              const hasMeta = Boolean(d.transport_from_name || d.transport_departs_at);
              return (
                <View key={d.user_id} style={styles.nc}>
                  <View style={[styles.ncStripe, isFull && styles.ncStripeFull]} />

                  {/* Top row — driver + colour-coded seats badge. */}
                  <View style={styles.ncTop}>
                    <Pressable
                      style={[styles.avatarRing, ringColor && { borderColor: ringColor }]}
                      onPress={(e) => { e.stopPropagation(); router.push(`/(auth)/profile/${d.user_id}`); }}
                      hitSlop={4}
                    >
                      <UserAvatar
                        name={d.display_name}
                        avatarUrl={d.avatar_url}
                        size={40}
                        confirmedPresent={d.confirmed_present === true}
                      />
                    </Pressable>
                    <View style={styles.ncNameWrap}>
                      <Text style={styles.driverName} numberOfLines={1}>{d.display_name}</Text>
                      {isSelf && (
                        <View style={styles.youTag}>
                          <Text style={styles.youTagText}>{t('group.youTag', { defaultValue: 'Toi' })}</Text>
                        </View>
                      )}
                    </View>
                    <View style={[styles.seatBadge, isFull && styles.seatBadgeFull]}>
                      <Armchair size={13} color={isFull ? colors.error : colors.cta} strokeWidth={2.4} />
                      <Text style={[styles.seatBadgeText, isFull && styles.seatBadgeTextFull]}>
                        {isFull
                          ? t('group.full', { defaultValue: 'Complet' })
                          : t('group.freeSeatsShort', { count: d.free, defaultValue: d.free === 1 ? '1 libre' : `${d.free} libres` })}
                      </Text>
                    </View>
                  </View>

                  {/* Journey line — from → outing · departure time. */}
                  {hasMeta && (
                    <View style={styles.journey}>
                      {d.transport_from_name ? (
                        <>
                          <MapPin size={13} color={colors.cta} strokeWidth={2.4} />
                          <Text style={styles.jFrom} numberOfLines={1}>{d.transport_from_name}</Text>
                        </>
                      ) : null}
                      {d.transport_departs_at ? (
                        <View style={[styles.jTime, d.transport_from_name ? styles.jTimePushed : null]}>
                          <Clock size={12} color={colors.textSecondary} strokeWidth={2.2} />
                          <Text style={styles.jTimeLabel}>{t('group.departLabel', { defaultValue: 'départ' })}</Text>
                          <Text style={styles.jTimeText}>{dayjs(d.transport_departs_at).format('H[h]mm')}</Text>
                        </View>
                      ) : null}
                    </View>
                  )}

                  {/* Bottom row — passengers (tap to expand) · action/status. */}
                  <View style={styles.ncBot}>
                    <Pressable
                      style={styles.paxToggle}
                      onPress={(e) => { e.stopPropagation(); if (driverPassengers.length > 0) togglePassengersForDriver(d.user_id); }}
                      disabled={driverPassengers.length === 0}
                      hitSlop={4}
                    >
                      {driverPassengers.length > 0 && (
                        <View style={styles.paxStack}>
                          {driverPassengers.slice(0, 4).map((pp, i) => (
                            <View key={pp.id} style={[styles.paxAvatar, i > 0 && styles.paxAvatarOverlap]}>
                              <UserAvatar name={pp.display_name} avatarUrl={pp.avatar_url} size={24} />
                            </View>
                          ))}
                        </View>
                      )}
                      <Text style={styles.paxLbl} numberOfLines={1}>
                        {driverPassengers.length > 0
                          ? t('group.aboardCount', { count: d.accepted, defaultValue: `${d.accepted} à bord` })
                          : t('group.noPassengers', { defaultValue: 'Aucun passager' })}
                      </Text>
                      {driverPassengers.length > 0 && (
                        <ChevronDown
                          size={13} color={colors.textSecondary} strokeWidth={2.4}
                          style={{ transform: [{ rotate: expandedPassengersByDriver.has(d.user_id) ? '180deg' : '0deg' }] }}
                        />
                      )}
                    </Pressable>

                    {isSelf ? null
                      : isMyDriver ? (
                        <View style={styles.statusPillSet}>
                          <Check size={10} color={colors.cta} strokeWidth={3} />
                          <Text style={[styles.statusPillText, { color: colors.cta }]}>
                            {t('group.youAreAboard', { defaultValue: 'À bord' })}
                          </Text>
                        </View>
                      ) : isPendingFromMe ? (
                        <View style={styles.statusPillPending}>
                          <Text style={[styles.statusPillText, { color: colors.textMuted }]}>
                            {t('group.pendingRequest', { defaultValue: 'En attente' })}
                          </Text>
                        </View>
                      ) : (!isFull && canReserve) ? (
                        <Pressable
                          style={styles.reserveBtn}
                          onPress={(e) => { e.stopPropagation(); onReserveSeat(d.user_id); }}
                          hitSlop={4}
                        >
                          <Text style={styles.reserveBtnText}>{t('group.reserve', { defaultValue: 'Réserver' })}</Text>
                        </Pressable>
                      ) : null}
                  </View>

                  {/* Expanded passenger detail — pickup city + time per rider. */}
                  {expandedPassengersByDriver.has(d.user_id) && driverPassengers.length > 0 && (
                    <View style={styles.passengersList}>
                      {driverPassengers.map((p) => (
                        <Pressable
                          key={p.id}
                          onPress={() => router.push(`/(auth)/profile/${p.requester_id}`)}
                          style={styles.passengerBlock}
                          hitSlop={4}
                        >
                          <View style={styles.passengerHeader}>
                            <UserAvatar name={p.display_name} avatarUrl={p.avatar_url} size={18} />
                            <Text style={styles.passengerName} numberOfLines={1}>{p.display_name}</Text>
                          </View>
                          {(p.pickup_from || p.requested_pickup_at) && (
                            <View style={styles.passengerMetaRow}>
                              {p.pickup_from && (
                                <>
                                  <MapPin size={10} color={colors.textMuted} strokeWidth={2.2} />
                                  <Text style={styles.passengerMetaText} numberOfLines={1}>{p.pickup_from}</Text>
                                </>
                              )}
                              {p.pickup_from && p.requested_pickup_at && (
                                <Text style={styles.passengerMetaText}>·</Text>
                              )}
                              {p.requested_pickup_at && (
                                <>
                                  <Clock size={10} color={colors.textMuted} strokeWidth={2.2} />
                                  <Text style={styles.passengerMetaText}>{dayjs(p.requested_pickup_at).format('H[h]mm')}</Text>
                                </>
                              )}
                            </View>
                          )}
                        </Pressable>
                      ))}
                    </View>
                  )}
                </View>
              );
            })}
              </View>
            )}

            {/* Self-mover categories — one section per non-empty bucket
                (bike / on_foot / public_transport / other). Each section
                has a small caption header + a chip strip. The user's
                own entry highlights with the CTA-tinted "selfChipSelf"
                variant. */}
            {(['bike', 'on_foot', 'public_transport', 'other'] as const).map((bucket) => {
              const list = moverBuckets[bucket];
              if (list.length === 0) return null;
              const Icon = bucket === 'bike' ? Bike
                : bucket === 'on_foot' ? Footprints
                : bucket === 'public_transport' ? TrainFront
                : HelpCircle;
              return (
                <View key={bucket} style={styles.transportCategory}>
                  <View style={styles.transportCategoryHeader}>
                    <Icon size={13} color={colors.textPrimary} strokeWidth={2.4} />
                    <Text style={styles.transportCategoryLabel}>
                      {t(`group.transportCategory.${bucket}`, { defaultValue: bucket })}
                    </Text>
                    <Text style={styles.transportCategoryCount}>· {list.length}</Text>
                  </View>
                  <View style={styles.selfMoversList}>
                    {list.map((p) => {
                      const isSelf = p.user_id === currentUserId;
                      const place = p.transport_from_name?.trim() || null;
                      const time = p.transport_departs_at
                        ? dayjs(p.transport_departs_at).format('H[h]mm')
                        : null;
                      return (
                        <Pressable
                          key={p.user_id}
                          style={styles.selfMoverRow}
                          onPress={() => router.push(`/(auth)/profile/${p.user_id}`)}
                          hitSlop={4}
                        >
                          <UserAvatar
                            name={p.display_name}
                            avatarUrl={p.avatar_url}
                            size={20}
                          />
                          <View style={styles.selfMoverInfo}>
                            <View style={styles.selfMoverNameRow}>
                              <Text style={styles.selfMoverName} numberOfLines={1}>
                                {p.display_name}
                              </Text>
                              {isSelf && (
                                <View style={styles.youTag}>
                                  <Text style={styles.youTagText}>{t('group.youTag', { defaultValue: 'Toi' })}</Text>
                                </View>
                              )}
                            </View>
                            {(place || time) && (
                              <View style={styles.selfMoverMeta}>
                                {place && (
                                  <>
                                    <MapPin size={10} color={colors.textSecondary} strokeWidth={2.2} />
                                    <Text style={styles.selfMoverMetaText} numberOfLines={1}>
                                      {place}
                                    </Text>
                                  </>
                                )}
                                {place && time && (
                                  <Text style={styles.selfMoverMetaText}>·</Text>
                                )}
                                {time && (
                                  <>
                                    <Clock size={10} color={colors.textSecondary} strokeWidth={2.2} />
                                    <Text style={styles.selfMoverMetaText}>{time}</Text>
                                  </>
                                )}
                              </View>
                            )}
                          </View>
                        </Pressable>
                      );
                    })}
                  </View>
                </View>
              );
            })}

            {drivers.length === 0 && selfMovers.length === 0 && (
              <Text style={styles.emptyHint}>
                {t('group.noTransportYet', {
                  defaultValue: 'Personne n\'a encore dit comment il y va',
                })}
              </Text>
            )}
          </View>
        )}

        {activeSubTab === 'gear' && (
          <View style={styles.tabContent}>
            {/* Le sac du groupe — shared gear as a tactile tile board
                (2026-07-09 redesign). Tile tap = contribute/edit; the last
                dashed tile adds. */}
            <View style={styles.gearSection}>
              <View style={styles.collapsibleHeader}>
                <Text style={styles.gearSecTitle}>
                  {t('group.gearSection.groupBag', { defaultValue: 'Le sac du groupe' })}
                </Text>
                {groupItems.length > 0 && (
                  <Text style={styles.transportCategoryCount}>· {groupItems.length}</Text>
                )}
              </View>
              {(groupItems.length > 0 || isActive) && (
                <View style={styles.tileBoard}>
                  {groupItems.map((g) => {
                    const total = g.bringers.reduce((s, b) => s + b.quantity, 0);
                    return (
                      <Pressable
                        key={g.name}
                        style={styles.gearTile}
                        onPress={() => isActive && onEditGearItem(g.name, true)}
                        disabled={!isActive}
                        hitSlop={4}
                      >
                        <Text style={styles.gearTileName} numberOfLines={2}>{g.name}</Text>
                        <View style={styles.gearTileFoot}>
                          <Text style={[styles.gearTileQty, total <= 1 && styles.gearTileQtyOne]}>×{total}</Text>
                          <View style={styles.gearTileAvatars}>
                            {g.bringers.slice(0, 4).map((b, i) => (
                              <View key={b.user_id} style={[styles.gearTileAvatar, i > 0 && styles.gearTileAvatarOverlap]}>
                                <UserAvatar size={20} name={b.display_name} avatarUrl={b.avatar_url} />
                              </View>
                            ))}
                            {g.bringers.length > 4 && (
                              <Text style={styles.gearTileMore}>+{g.bringers.length - 4}</Text>
                            )}
                          </View>
                        </View>
                      </Pressable>
                    );
                  })}
                  {isActive && (
                    <Pressable style={[styles.gearTile, styles.gearTileAdd]} onPress={onAddGear} hitSlop={4}>
                      <View style={styles.gearTileAddPlus}>
                        <Plus size={14} color="#FFFFFF" strokeWidth={3} />
                      </View>
                      <Text style={styles.gearTileAddText}>
                        {t('group.addGearShort', { defaultValue: 'Ajouter' })}
                      </Text>
                    </Pressable>
                  )}
                </View>
              )}
            </View>

            {/* Manquant — collaborative red tiles: "il manque X". Any
                participant adds/removes; declaring a matching shared
                contribution auto-clears (00303 trigger). Section absent
                when empty on inactive activities. */}
            {(missingItems.length > 0 || isActive) && (
              <View style={[styles.gearSection, styles.gearSectionSpacer]}>
                <View style={styles.collapsibleHeader}>
                  <Text style={styles.gearSecTitle}>
                    {t('group.gearSection.missing', { defaultValue: 'Manquant' })}
                  </Text>
                  {missingItems.length > 0 && (
                    <Text style={styles.transportCategoryCount}>· {missingItems.length}</Text>
                  )}
                </View>
                <View style={styles.tileBoard}>
                  {missingItems.map((m) => (
                    <View key={m.id} style={[styles.gearTile, styles.missTile]}>
                      {isActive && (
                        <Pressable style={styles.missRemove} onPress={() => removeMissing(m.name)} hitSlop={8}>
                          <X size={13} color={colors.textMuted} strokeWidth={2.4} />
                        </Pressable>
                      )}
                      <Text style={styles.gearTileName} numberOfLines={2}>
                        {m.name}
                        {m.quantity > 1 && <Text style={styles.missQty}>{'  ×' + m.quantity}</Text>}
                      </Text>
                      <View style={styles.gearTileFoot}>
                        {isActive ? (
                          <Pressable
                            style={styles.missBringBtn}
                            onPress={() => {
                              // Converge on the bag's canonical spelling when the
                              // same item already exists, so the contribution adds
                              // to the existing tile instead of forking a twin.
                              const canonical = groupItems.find(
                                (gi) => gi.name.trim().toLowerCase() === m.name.trim().toLowerCase(),
                              )?.name ?? m.name;
                              onEditGearItem(canonical, true);
                            }}
                            hitSlop={4}
                          >
                            <Text style={styles.missBringText}>
                              {t('group.iBringIt', { defaultValue: "Je l'apporte" })}
                            </Text>
                          </Pressable>
                        ) : <View />}
                      </View>
                    </View>
                  ))}
                  {isActive && (
                    <Pressable
                      style={[styles.gearTile, styles.gearTileAdd, styles.missAddTile]}
                      onPress={() => onReportMissing?.()}
                      hitSlop={4}
                    >
                      <View style={[styles.gearTileAddPlus, styles.missAddPlus]}>
                        <Plus size={14} color="#FFFFFF" strokeWidth={3} />
                      </View>
                      <Text style={styles.missAddText}>
                        {t('group.reportMissing', { defaultValue: 'Signaler un manque' })}
                      </Text>
                    </Pressable>
                  )}
                </View>
              </View>
            )}

            {/* Chacun son sac — personal gear, one glance-line per person. */}
            {(() => {
              const personal = bringers
                .map((b) => ({ ...b, items: b.items.filter((it) => !it.is_shared) }))
                .filter((b) => b.items.length > 0);
              if (personal.length === 0) return null;
              return (
                <View style={[styles.gearSection, styles.gearSectionSpacer]}>
                  <View style={styles.collapsibleHeader}>
                    <Text style={styles.gearSecTitle}>
                      {t('group.gearSection.ownBag', { defaultValue: 'Chacun son sac' })}
                    </Text>
                  </View>
                  <View style={styles.persList}>
                    {personal.map((b) => {
                      const isSelf = b.user_id === currentUserId;
                      return (
                        <Pressable
                          key={b.user_id}
                          style={styles.persLine}
                          onPress={() => router.push(`/(auth)/profile/${b.user_id}`)}
                          hitSlop={4}
                        >
                          <UserAvatar name={b.display_name} avatarUrl={b.avatar_url} size={30} />
                          <View style={styles.persNameWrap}>
                            <Text style={styles.persName} numberOfLines={1}>{b.display_name}</Text>
                            {isSelf && (
                              <Text style={styles.persToi}>{t('group.youTag', { defaultValue: 'Toi' })}</Text>
                            )}
                          </View>
                          <Text style={styles.persItems}>
                            {b.items.map((it) => (it.quantity > 1 ? `${it.name} ×${it.quantity}` : it.name)).join(' · ')}
                          </Text>
                        </Pressable>
                      );
                    })}
                  </View>
                </View>
              );
            })()}

            {groupItems.length === 0 && bringers.length === 0 && !isActive && (
              <Text style={styles.emptyHint}>
                {t('group.noGearYet', {
                  defaultValue: 'Personne n\'a encore listé de matériel',
                })}
              </Text>
            )}
          </View>
        )}

      </View>

    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  cardWrapper: { marginBottom: spacing.md },
  // Open section (2026-07-09): soft divider above separates it from the
  // "Tes préparatifs" section — same grammar as the Info tab.
  card: {
    backgroundColor: 'transparent',
    borderTopWidth: 1,
    borderTopColor: colors.line,
    marginTop: spacing.xs,
    paddingTop: spacing.md,
  },

  // Header band — surfaceAlt bg + bottom divider mark it as its own
  // zone, distinct from the card body. Mirrors my-outing-card's
  // header band so the two cards read as siblings.
  headerBand: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: spacing.sm,
  },
  cardTitle: {
    flex: 1,
    color: colors.textPrimary,
    fontSize: fontSizes.lg,
    fontWeight: '700',
    letterSpacing: -0.3,
  },
  headerRight: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
  },
  peopleCount: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '700',
    letterSpacing: 0.4,
  },

  // Tab band — surfaceAlt bg continues from the header band, with a
  // bottom divider that the active tab "punches through" via negative
  // margin to merge with the content area below.
  tabBand: {
    flexDirection: 'row',
    paddingTop: spacing.sm,
    paddingHorizontal: spacing.sm,
    gap: spacing.xs,
    backgroundColor: colors.surfaceAlt,
    borderBottomWidth: 1,
    borderBottomColor: colors.line,
  },
  folderTab: {
    flex: 1,
    paddingVertical: spacing.sm + 2,
    alignItems: 'center',
    borderTopLeftRadius: 4,
    borderTopRightRadius: 4,
    borderWidth: 1,
    borderColor: colors.line,
    borderBottomWidth: 0,
    backgroundColor: colors.surfaceAlt,
    marginBottom: -1,
  },
  folderTabActive: {
    backgroundColor: colors.surface,
  },
  folderTabLabel: {
    fontSize: fontSizes.xs + 1,
    fontWeight: '700',
    color: colors.textMuted,
    letterSpacing: 1.2,
    textTransform: 'uppercase',
  },
  folderTabLabelActive: {
    color: colors.textPrimary,
    fontWeight: '800',
  },

  // Active tab content area. Padding kept identical to the previous
  // value so existing rows don't reflow.
  tabContent: {
    paddingVertical: spacing.sm + 2,
    paddingHorizontal: spacing.md,
    gap: spacing.sm,
  },

  // Driver-side incoming-requests panel — sits above the Voitures
  // section in the Transport tab. Warning-tinted card to read as
  // "needs your action" without feeling alarming.
  incomingRequests: {
    gap: 6,
    paddingBottom: spacing.xs,
  },
  incomingRequestsLabel: {
    color: colors.warning,
    fontSize: fontSizes.xs + 1,
    fontWeight: '700',
    letterSpacing: 0.2,
  },
  incomingRequestCard: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingVertical: spacing.sm - 2,
    paddingHorizontal: spacing.sm,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.warning + '4D',
    backgroundColor: colors.warning + '12',
  },
  incomingRequestInfo: {
    flex: 1,
    gap: 2,
  },
  incomingRequestName: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '700',
    letterSpacing: -0.05,
  },
  incomingRequestMessage: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '400',
    fontStyle: 'italic',
  },
  incomingRequestActions: {
    flexDirection: 'row',
    gap: 6,
  },
  incomingAcceptBtn: {
    width: 32,
    height: 32,
    borderRadius: 999,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.cta + '20',
    borderWidth: 1,
    borderColor: colors.cta + '60',
  },
  incomingDeclineBtn: {
    width: 32,
    height: 32,
    borderRadius: 999,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.line,
    borderWidth: 1,
    borderColor: colors.lineStrong,
  },
  incomingActionDisabled: {
    opacity: 0.4,
  },

  // Driver card-pill — each driver gets a contained unit (border +
  // padding + radius) so they read as discrete action surfaces, not a
  // flat list of rows. Visually outranks the self-mover chips since
  // drivers are where the user takes action (reserving a seat).
  // Ride card (2026-07-09): lighter surface, softer radius, subtle lift —
  // the carpool reads as a journey card, not a grey pill.
  driverPill: {
    // Bleed past the tab's lg padding so the journey card breathes in
    // width (Scott 2026-07-10) — headers above keep the normal margin.
    marginHorizontal: -spacing.sm,
    backgroundColor: colors.surface,
    borderWidth: 1.5,
    borderColor: colors.line,
    borderRadius: 14,
    padding: spacing.sm + 5,
    gap: 6,
    shadowColor: '#000',
    shadowOpacity: 0.05,
    shadowRadius: 8,
    shadowOffset: { width: 0, height: 2 },
    elevation: 1,
  },
  // --- Redesigned carpool card: read it in one glance ---
  nc: {
    marginHorizontal: -spacing.sm,
    position: 'relative', overflow: 'hidden',
    backgroundColor: colors.surface,
    borderWidth: 1.5, borderColor: colors.line, borderRadius: 16,
    paddingVertical: spacing.sm + 5, paddingRight: spacing.sm + 5, paddingLeft: spacing.sm + 11,
    gap: 10,
    shadowColor: '#000', shadowOpacity: 0.05, shadowRadius: 8, shadowOffset: { width: 0, height: 2 }, elevation: 1,
  },
  ncStripe: { position: 'absolute', left: 0, top: 0, bottom: 0, width: 4, backgroundColor: colors.cta },
  ncStripeFull: { backgroundColor: colors.textMuted },
  ncTop: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 2 },
  ncNameWrap: { flex: 1, minWidth: 0, flexDirection: 'row', alignItems: 'center', gap: 6 },
  seatBadge: {
    flexDirection: 'row', alignItems: 'center', gap: 5,
    backgroundColor: colors.cta + '1F', borderRadius: 999,
    paddingHorizontal: 10, paddingVertical: 5,
  },
  seatBadgeFull: { backgroundColor: colors.error + '1A' },
  seatBadgeText: { color: colors.cta, fontSize: fontSizes.xs + 1, fontWeight: '800' },
  seatBadgeTextFull: { color: colors.error },
  journey: {
    flexDirection: 'row', alignItems: 'center', gap: 7,
    backgroundColor: colors.surfaceAlt, borderRadius: 10,
    paddingHorizontal: 11, paddingVertical: 8,
  },
  jFrom: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '800', flexShrink: 1 },
  jTime: { flexDirection: 'row', alignItems: 'center', gap: 4 },
  jTimePushed: { marginLeft: 'auto' },
  jTimeLabel: { color: colors.textMuted, fontSize: 10, fontWeight: '700', textTransform: 'uppercase', letterSpacing: 0.4 },
  jTimeText: { color: colors.textPrimary, fontSize: fontSizes.xs + 1, fontWeight: '800' },
  ncBot: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: spacing.sm },
  paxToggle: { flexDirection: 'row', alignItems: 'center', gap: 8, flexShrink: 1, minWidth: 0 },
  paxStack: { flexDirection: 'row' },
  paxAvatar: { borderRadius: 14, borderWidth: 2, borderColor: colors.surface },
  paxAvatarOverlap: { marginLeft: -9 },
  paxLbl: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, fontWeight: '700', flexShrink: 1 },
  routeRow: { flexDirection: 'row', alignItems: 'center', gap: 5, marginTop: 6, paddingLeft: 2 },
  routeDot: { width: 7, height: 7, borderRadius: 4, borderWidth: 2, borderColor: colors.textSecondary },
  routeDash: { width: 20, height: 0, borderTopWidth: 2, borderColor: colors.textSecondary, borderStyle: 'dashed', opacity: 0.55 },
  routeText: { color: colors.textPrimary, fontSize: fontSizes.xs + 1, fontWeight: '600', flexShrink: 1 },
  routeSep: { color: colors.textMuted, marginHorizontal: 2 },
  seatsRow: { flexDirection: 'row', alignItems: 'center', gap: 5, flex: 1, minWidth: 0 },
  seatFilled: { borderRadius: 11, overflow: 'hidden' },
  seatTaken: { width: 22, height: 22, borderRadius: 11, backgroundColor: colors.surfaceAlt },
  seatEmpty: {
    width: 22, height: 22, borderRadius: 11,
    borderWidth: 1.8, borderStyle: 'dashed', borderColor: colors.borderMuted,
  },
  seatOverflow: { color: colors.textMuted, fontSize: fontSizes.xs, fontWeight: '700' },
  seatsLabel: { color: colors.cta, fontSize: fontSizes.xs, fontWeight: '800', marginLeft: 4, flexShrink: 1 },
  seatsLabelFull: { color: colors.textMuted },
  pillBody: {
    gap: 6,
  },
  pillHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm + 2,
  },
  // Wraps the name + the inline collapsed meta. flex:1 lets it absorb
  // the row width; flexDirection inside is handled by driverNameRow so
  // name and meta items can wrap together.
  driverIdentity: {
    flex: 1,
    minWidth: 0,
  },
  inlineMetaItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 3,
    flexShrink: 1,
    minWidth: 0,
  },
  pillMetaRows: {
    paddingLeft: 44, // align with content under avatar
    gap: 2,
  },
  pillMetaRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
  },
  pillFooter: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    borderTopWidth: 1,
    borderTopColor: colors.line,
    marginTop: 2,
    paddingTop: spacing.xs + 2,
  },
  // Tier ring around the driver avatar — borderColor set inline based on
  // reliability score; transparent here so the layout stays stable when
  // a driver has no score yet (new user, no ring shown).
  avatarRing: {
    padding: 2,
    borderRadius: 20,
    borderWidth: 2,
    borderColor: 'transparent',
  },
  // Wraps the driver's display name + their inline peer-vouch chip
  // (icon + trait label). flexShrink on the name lets it ellipsize
  // first if space is tight; the chip stays visible since it's the
  // trust signal we're surfacing.
  driverNameRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  driverName: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '700',
    letterSpacing: -0.1,
    flexShrink: 1,
  },
  // "Toi" pill on self-driver rows — uses CTA tint to mirror the
  // ownership signal Mine's stamp uses for the empty state.
  youTag: {
    backgroundColor: colors.cta + '1F',
    borderRadius: 999,
    paddingHorizontal: 6,
    paddingVertical: 1,
  },
  youTagText: {
    color: colors.cta,
    fontSize: 9.5,
    fontWeight: '800',
    letterSpacing: 0.6,
    textTransform: 'uppercase',
  },

  // Free-seats info — merged into the Voitures section header
  // (inline count) + a sub-line for the cities list. Replaces the
  // standalone success-tinted banner that floated above the section.
  freeSeatsInline: {
    color: colors.cta,
    fontSize: 10,
    fontWeight: '800',
    letterSpacing: 0.6,
    textTransform: 'uppercase',
  },
  // Cities sub-line under the Voitures section header — "depuis :"
  // anchored on the left, cities cluster (icon + names) right-aligned.
  // Small icon-then-text pattern keeps the row scanable at a glance.
  freeSeatsFromRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: spacing.sm,
    marginTop: -2,
    marginBottom: 2,
  },
  freeSeatsFromLabel: {
    color: colors.textMuted,
    fontSize: fontSizes.xs,
    fontWeight: '600',
  },
  freeSeatsFromCities: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
    flexShrink: 1,
    minWidth: 0,
  },
  freeSeatsFromCitiesText: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '600',
    textAlign: 'right',
    flexShrink: 1,
    minWidth: 0,
  },

  // Transport sub-categories (Voitures / Vélo / À pied / Transports /
  // Autre). Each non-empty bucket gets its own caption header followed
  // by the cars' driver-rows or the self-movers' chip strip.
  transportCategory: {
    gap: 10,
  },
  transportCategoryHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
    marginTop: spacing.md,
  },
  transportCategoryLabel: {
    color: colors.textSecondary,
    fontSize: 11.5,
    fontWeight: '800',
    letterSpacing: 1,
    textTransform: 'uppercase',
  },
  transportCategoryCount: {
    color: colors.textSecondary,
    fontSize: 11,
    fontWeight: '600',
  },

  // Toggle row that fronts the passenger list — small caption +
  // count + chevron. Tappable, sits at the bottom of the driver pill
  // so the pill stays compact when collapsed.
  passengersToggleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingTop: 4,
    paddingHorizontal: 2,
  },
  passengersToggleText: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '700',
    letterSpacing: 0.3,
  },
  passengersSeeAll: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 2,
  },
  passengersSeeAllText: {
    color: colors.cta,
    fontSize: fontSizes.xs,
    fontWeight: '700',
  },
  bringerToggleText: {
    color: colors.cta,
    fontSize: fontSizes.xs,
    fontWeight: '700',
    marginRight: 4,
  },
  // Passengers under each driver — nested inside the pill. The driver
  // pill's containing border already signals "these belong together",
  // so no extra thread/border is needed; just inset spacing.
  passengersList: {
    marginTop: 6,
    paddingLeft: 10,
    gap: 8,
  },
  passengerBlock: {
    gap: 2,
  },
  passengerHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  passengerName: {
    color: colors.textPrimary,
    fontSize: fontSizes.xs + 1,
    fontWeight: '600',
    letterSpacing: -0.05,
    flex: 1,
    minWidth: 0,
  },
  passengerMetaRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    paddingLeft: 24, // align under the name (avatar 18 + gap 6)
  },
  passengerMetaText: {
    color: colors.textMuted,
    fontSize: fontSizes.xs,
    fontWeight: '500',
  },
  driverMetaText: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
  },
  seatsCount: {
    color: colors.textMuted,
    fontSize: fontSizes.xs,
    fontWeight: '700',
  },
  // Solid CTA — the one action on the card gets to pop.
  reserveBtn: {
    backgroundColor: colors.cta,
    borderRadius: 999,
    paddingHorizontal: spacing.md,
    paddingVertical: 7,
    shadowColor: colors.cta,
    shadowOpacity: 0.35,
    shadowRadius: 8,
    shadowOffset: { width: 0, height: 3 },
    elevation: 3,
  },
  reserveBtnText: {
    color: '#FFFFFF',
    fontSize: fontSizes.xs + 1,
    fontWeight: '800',
  },
  fullText: {
    color: colors.textMuted,
    fontSize: fontSizes.xs + 1,
    fontWeight: '500',
    fontStyle: 'italic',
  },
  statusPillSet: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 3,
    backgroundColor: colors.cta + '1F',
    borderRadius: 999,
    paddingHorizontal: 8,
    paddingVertical: 3,
  },
  statusPillPending: {
    backgroundColor: colors.surfaceAlt,
    borderRadius: 999,
    paddingHorizontal: 8,
    paddingVertical: 3,
  },
  statusPillText: {
    fontSize: fontSizes.xs,
    fontWeight: '700',
  },

  // Self-mover entries — info-only pills showing profile pic +
  // departure + time. Subtle border (lighter `line` token, not the
  // `lineStrong` used on driver pills) signals tappability without
  // competing with the driver pills which carry the action.
  selfMoversList: {
    gap: 8,
    marginTop: 4,
  },
  selfMoverRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingVertical: 6,
    paddingHorizontal: 8,
    backgroundColor: colors.surfaceAlt,
    borderWidth: 1,
    borderColor: colors.line,
    borderRadius: radius.md,
  },
  selfMoverInfo: {
    flex: 1,
    minWidth: 0,
  },
  selfMoverNameRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
  },
  selfMoverName: {
    color: colors.textPrimary,
    fontSize: fontSizes.xs + 1,
    fontWeight: '600',
    flexShrink: 1,
  },
  selfMoverMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    marginTop: 1,
  },
  selfMoverMetaText: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '500',
  },
  // Tile board (2026-07-09 gear redesign)
  gearSecTitle: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700', letterSpacing: -0.2 },
  tileBoard: { flexDirection: 'row', flexWrap: 'wrap', gap: 9, marginTop: spacing.xs },
  gearTile: {
    width: '48%',
    minHeight: 84,
    backgroundColor: colors.surface,
    borderWidth: 1.5,
    borderColor: colors.line,
    borderRadius: 16,
    padding: spacing.sm + 4,
    justifyContent: 'space-between',
  },
  gearTileName: { color: colors.textPrimary, fontSize: fontSizes.sm + 0.5, fontWeight: '700', lineHeight: 18 },
  gearTileFoot: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginTop: spacing.sm },
  gearTileQty: { color: colors.cta, fontSize: fontSizes.md - 1, fontWeight: '800' },
  gearTileQtyOne: { color: colors.textMuted, fontSize: fontSizes.xs + 1, fontWeight: '700' },
  gearTileAvatars: { flexDirection: 'row', alignItems: 'center' },
  gearTileAvatar: { borderRadius: radius.full, borderWidth: 1.8, borderColor: colors.surface },
  gearTileAvatarOverlap: { marginLeft: -7 },
  gearTileMore: { color: colors.textMuted, fontSize: fontSizes.xs, fontWeight: '700', marginLeft: 3 },
  gearTileAdd: {
    backgroundColor: 'transparent',
    borderStyle: 'dashed',
    borderColor: colors.borderMuted,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
  },
  gearTileAddPlus: {
    width: 22, height: 22, borderRadius: radius.full,
    backgroundColor: colors.cta, alignItems: 'center', justifyContent: 'center',
  },
  gearTileAddText: { color: colors.cta, fontSize: fontSizes.xs + 1, fontWeight: '800' },
  persList: { gap: spacing.sm + 1, marginTop: spacing.xs },
  persLine: { flexDirection: 'row', alignItems: 'center', gap: 9 },
  persNameWrap: { width: 64 },
  persName: { color: colors.textPrimary, fontSize: fontSizes.xs + 1.5, fontWeight: '700' },
  persToi: { color: colors.cta, fontSize: 10, fontWeight: '800', textTransform: 'uppercase', letterSpacing: 0.5 },
  persItems: { flex: 1, color: colors.textSecondary, fontSize: fontSizes.xs + 1, fontWeight: '600', lineHeight: 19 },
  // "Manquant" tiles — muted red, dashed; green CTA fixes them.
  missTile: { backgroundColor: '#C0553F0D', borderStyle: 'dashed', borderColor: '#C0553F66' },
  missQty: { color: '#C0553F', fontWeight: '800' },
  missRemove: { position: 'absolute', top: 6, right: 6, zIndex: 2, padding: 2 },
  missBringBtn: {
    backgroundColor: colors.cta,
    borderRadius: radius.full,
    paddingHorizontal: spacing.sm + 4,
    paddingVertical: 6,
    shadowColor: colors.cta,
    shadowOpacity: 0.3,
    shadowRadius: 6,
    shadowOffset: { width: 0, height: 2 },
    elevation: 2,
  },
  missBringText: { color: '#FFFFFF', fontSize: fontSizes.xs, fontWeight: '800' },
  missAddTile: { borderColor: '#C0553F55' },
  missAddPlus: { backgroundColor: '#C0553F' },
  missAddText: { color: '#C0553F', fontSize: fontSizes.xs + 1, fontWeight: '800' },
  emptyHint: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs + 1,
    textAlign: 'center',
    borderWidth: 1.5,
    borderStyle: 'dashed',
    borderColor: colors.line,
    borderRadius: radius.md,
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.md,
  },
  // Two-button gear-actions row at the top of the gear tab. Smaller
  // than the previous single CTA so both fit comfortably side-by-side.
  // Add-gear stays CTA-coloured (orange); add-missing uses warning
  // tone (slightly more amber) to differentiate without shouting.
  // Compact "+ Ajouter du matériel" chip pinned to the right edge of
  // the Inventaire commun header — replaces the older full-width CTA so
  // the inventory list keeps its vertical room.
  addGearChip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    paddingVertical: 3,
    paddingHorizontal: 8,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: colors.cta + '66',
    backgroundColor: colors.cta + '15',
  },
  addGearChipText: {
    color: colors.cta,
    fontSize: fontSizes.xs,
    fontWeight: '700',
  },

  // Matériel sub-sections (Inventaire / Qui apporte quoi). Gap-spaced
  // so each section reads as its own block under the same tab.
  gearSection: {
    gap: 6,
  },
  gearSectionSpacer: {
    marginTop: spacing.md - 2,
  },

  // Collapsible-section header — used by both Inventaire and the
  // per-bringer blocks. Pressable row with the section caption on the
  // left, optional metadata, then a chevron pinned to the right via
  // a flex spacer.
  collapsibleHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
    paddingVertical: 4,
  },
  collapsibleSpacer: {
    flex: 1,
  },

  // Per-bringer card-pill — mirrors the driver pill in the transport
  // tab so the gear tab reads with the same visual grammar. Each
  // bringer is a contained unit (surface bg, lineStrong border) with
  // a tappable header that toggles the items list nested inside.
  bringerBlock: {
    backgroundColor: colors.surface,
    borderWidth: 1.5,
    borderColor: colors.line,
    borderRadius: 14,
    padding: spacing.sm + 3,
    gap: 6,
  },
  bringerHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  bringerName: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '700',
    letterSpacing: -0.05,
    flexShrink: 1,
  },
  bringerCount: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '700',
  },
  // Inventaire commun list — each item is its own thin-bordered pill
  // with name + total qty + a +/- stepper that lets the user adjust
  // their personal contribution to that item without leaving the
  // tab. Compact padding to fit many items, line border (not the
  // heavier lineStrong used on bringer pills) since this is info /
  // quick-edit, not the primary action surface.
  inventoryList: {
    gap: 8,
  },
  inventoryItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingVertical: 6,
    paddingHorizontal: 8,
    backgroundColor: colors.surfaceAlt,
    borderWidth: 1,
    borderColor: colors.line,
    borderRadius: radius.sm,
  },
  inventoryItemName: {
    flex: 1,
    color: colors.textPrimary,
    fontSize: fontSizes.xs + 1,
    fontWeight: '500',
  },
  // Trailing pill cluster — one success-tinted pill per contributor on
  // a shared inventory row. Avatar + ×qty inline; pattern repeats per
  // bringer so a glance reveals who contributed how much.
  partyPillRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    flexShrink: 0,
  },
  partyPillSuccess: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    backgroundColor: colors.success + '1F',
    borderRadius: 999,
    paddingHorizontal: 4,
    paddingVertical: 2,
  },
  partyPillQtySuccess: {
    color: colors.success,
    fontSize: fontSizes.xs,
    fontWeight: '800',
  },
  // Bullet list — used for the per-bringer items list inside the
  // expanded "Qui apporte quoi" pills.
  bulletList: {
    gap: 2,
  },
  bringerItemsList: {
    gap: 4,
    paddingLeft: 30, // align under bringer's name (avatar 22 + gap 8)
  },

  bulletRow: {
    flexDirection: 'row',
    alignItems: 'baseline',
    gap: 6,
  },
  bullet: {
    fontSize: fontSizes.sm + 2,
    fontWeight: '800',
    lineHeight: 17,
  },
  bulletText: {
    color: colors.textPrimary,
    fontSize: fontSizes.xs + 1,
    fontWeight: '500',
    flex: 1,
    minWidth: 0,
  },
  // Right-aligned quantity caption — the one-glance metric for the
  // gear inventory. Matches Mine's gearListQty (success + sm + 700)
  // so "the group has this" reads with the same affirmative weight as
  // "I'm bringing this".
  itemQty: {
    color: colors.cta,
    fontSize: fontSizes.sm,
    fontWeight: '700',
    letterSpacing: 0.2,
    marginLeft: 6,
  },
});
