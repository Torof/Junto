import { useMemo, useState } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { router } from 'expo-router';
import dayjs from 'dayjs';
import * as Burnt from 'burnt';
import { Users, MapPin, Clock, Check, ChevronDown, Car, Bike, TrainFront, Footprints, HelpCircle, Plus, X, type LucideIcon } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { spacing, fontSizes, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { transportService } from '@/services/transport-service';
import { gearService } from '@/services/gear-service';
import { participationService } from '@/services/participation-service';
import { UserAvatar } from './user-avatar';
import { ringColorFor } from './profile-hero';
import { supabase } from '@/services/supabase';

interface Props {
  activityId: string;
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

const CAR_TYPES = ['car', 'carpool'] as const;


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
    const map = new Map<string, { name: string; bringers: InventoryBringer[] }>();
    gearDeclared.forEach((g) => {
      if (!g.is_shared) return;
      const entry = map.get(g.gear_name);
      const bringer: InventoryBringer = {
        user_id: g.user_id,
        display_name: g.display_name,
        avatar_url: g.avatar_url,
        quantity: g.quantity,
      };
      if (entry) entry.bringers.push(bringer);
      else map.set(g.gear_name, { name: g.gear_name, bringers: [bringer] });
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
      Burnt.toast({ title: t('transport.seatAccepted', { defaultValue: 'Place confirmée' }), preset: 'done' });
      if (conversationId) {
        router.push(`/(auth)/conversation/${conversationId}`);
      }
    } catch {
      Burnt.toast({ title: t('auth.unknownError') });
    } finally {
      setPendingActionId(null);
    }
  };

  const handleDeclineIncoming = async (requestId: string) => {
    setPendingActionId(requestId);
    try {
      await transportService.declineSeatRequest(requestId);
      await queryClient.invalidateQueries({ queryKey: ['seat-requests', activityId] });
    } catch {
      Burnt.toast({ title: t('auth.unknownError') });
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
                          <Check size={16} color={colors.success} strokeWidth={3} />
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
                  <Car size={12} color={colors.textSecondary} strokeWidth={2.4} />
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
                {totalFreeSeats > 0 && departureCities.length > 0 && (
                  <View style={styles.freeSeatsFromRow}>
                    <Text style={styles.freeSeatsFromLabel}>
                      {t('group.freeSeatsFromLabel', { defaultValue: 'depuis :' })}
                    </Text>
                    <View style={styles.freeSeatsFromCities}>
                      <MapPin size={11} color={colors.textSecondary} strokeWidth={2.2} />
                      <Text style={styles.freeSeatsFromCitiesText} numberOfLines={2}>
                        {departureCities.join(', ')}
                      </Text>
                    </View>
                  </View>
                )}
                {drivers.map((d) => {
              const isSelf = d.user_id === currentUserId;
              const isMyDriver = myAcceptedSeat?.driver_id === d.user_id;
              const isPendingFromMe = myPending?.driver_id === d.user_id;
              const isFull = d.free === 0;
              const score = reliabilityById.get(d.user_id) ?? null;
              const ringColor = score !== null ? ringColorFor(score) : null;
              const driverPassengers = passengersByDriver.get(d.user_id) ?? [];
              const isExpanded = true;
              const hasMeta = Boolean(d.transport_from_name || d.transport_departs_at);
              return (
                <View key={d.user_id} style={styles.driverPill}>
                  {/* Pill body — tap to expand/collapse. Avatar / status
                      pill / reserve / passengers keep their own handlers
                      via stopPropagation on their own press events. */}
                  <View style={styles.pillBody}>
                    <View style={styles.pillHeader}>
                      <Pressable
                        style={[
                          styles.avatarRing,
                          ringColor && { borderColor: ringColor },
                        ]}
                        onPress={(e) => { e.stopPropagation(); router.push(`/(auth)/profile/${d.user_id}`); }}
                        hitSlop={4}
                      >
                        <UserAvatar
                          name={d.display_name}
                          avatarUrl={d.avatar_url}
                          size={32}
                          confirmedPresent={d.confirmed_present === true}
                        />
                      </Pressable>
                      <View style={styles.driverIdentity}>
                        <View style={styles.driverNameRow}>
                          <Text style={styles.driverName} numberOfLines={1}>
                            {isExpanded
                              ? d.display_name
                              : d.display_name.length > 7
                                ? `${d.display_name.slice(0, 7)}…`
                                : d.display_name}
                          </Text>
                          {isSelf && (
                            <View style={styles.youTag}>
                              <Text style={styles.youTagText}>{t('group.youTag', { defaultValue: 'Toi' })}</Text>
                            </View>
                          )}
                          {/* Collapsed: only the city is shown inline.
                              Time moves to its own row below when the
                              pill is expanded. */}
                          {!isExpanded && d.transport_from_name && (
                            <View style={styles.inlineMetaItem}>
                              <MapPin size={11} color={colors.textSecondary} strokeWidth={2.2} />
                              <Text style={styles.driverMetaText} numberOfLines={1}>
                                {d.transport_from_name}
                              </Text>
                            </View>
                          )}
                        </View>
                      </View>
                      {!isSelf && isMyDriver && (
                        <View style={styles.statusPillSet}>
                          <Check size={10} color={colors.success} strokeWidth={3} />
                          <Text style={[styles.statusPillText, { color: colors.success }]}>
                            {t('group.youAreAboard', { defaultValue: 'À bord' })}
                          </Text>
                        </View>
                      )}
                      {!isSelf && isPendingFromMe && (
                        <View style={styles.statusPillPending}>
                          <Text style={[styles.statusPillText, { color: colors.textMuted }]}>
                            {t('group.pendingRequest', { defaultValue: 'En attente' })}
                          </Text>
                        </View>
                      )}
                    </View>

                    {/* Meta on its own rows under the avatar, full-length text. */}
                    {isExpanded && hasMeta && (
                      <View style={styles.pillMetaRows}>
                        {d.transport_from_name && (
                          <View style={styles.pillMetaRow}>
                            <MapPin size={11} color={colors.textSecondary} strokeWidth={2.2} />
                            <Text style={styles.driverMetaText}>
                              {d.transport_from_name}
                            </Text>
                          </View>
                        )}
                        {d.transport_departs_at && (
                          <View style={styles.pillMetaRow}>
                            <Clock size={11} color={colors.textSecondary} strokeWidth={2.2} />
                            <Text style={styles.driverMetaText}>
                              {dayjs(d.transport_departs_at).format('H[h]mm')}
                            </Text>
                          </View>
                        )}
                      </View>
                    )}
                  </View>

                  {/* Pill footer — seats count on the left, action CTA
                      on the right (Reserve / Complet). Hidden for self
                      and for users with an existing relationship (the
                      status pill in the header carries that). */}
                  <View style={styles.pillFooter}>
                    <Text style={styles.seatsCount}>
                      {d.accepted}/
                      <Text style={d.free > 0 ? { color: colors.success } : undefined}>
                        {d.capacity}
                      </Text>
                      {' '}{t('group.seatsLabel', { defaultValue: 'places' })}
                    </Text>
                    {!isSelf && !isMyDriver && !isPendingFromMe && (
                      isFull ? (
                        <Text style={styles.fullText}>
                          {t('group.full', { defaultValue: 'Complet' })}
                        </Text>
                      ) : canReserve ? (
                        <Pressable
                          style={styles.reserveBtn}
                          onPress={(e) => { e.stopPropagation(); onReserveSeat(d.user_id); }}
                          hitSlop={4}
                        >
                          <Text style={styles.reserveBtnText}>
                            {t('group.reserve', { defaultValue: 'Réserver' })}
                          </Text>
                        </Pressable>
                      ) : null
                    )}
                  </View>

                  {/* Passengers — collapsed by default behind a labelled
                      "Voir tous…" button. Each block is 2 lines (avatar +
                      name on top, pickup meta beneath). Tap a block → that
                      passenger's profile. */}
                  {driverPassengers.length > 0 && (() => {
                    const expanded = expandedPassengersByDriver.has(d.user_id);
                    return (
                      <>
                        <Pressable
                          style={styles.passengersToggleRow}
                          onPress={(e) => { e.stopPropagation(); togglePassengersForDriver(d.user_id); }}
                          hitSlop={4}
                        >
                          <Text style={styles.passengersToggleText}>
                            {t('group.passengersCount', {
                              count: driverPassengers.length,
                              defaultValue: driverPassengers.length === 1 ? '1 passager' : `${driverPassengers.length} passagers`,
                            })}
                          </Text>
                          <View style={styles.passengersSeeAll}>
                            <Text style={styles.passengersSeeAllText}>
                              {expanded
                                ? t('group.seeLess', { defaultValue: 'Voir moins' })
                                : t('group.seeAllPassengers', { defaultValue: 'Voir tous…' })}
                            </Text>
                            <ChevronDown
                              size={13}
                              color={colors.cta}
                              strokeWidth={2.4}
                              style={{ transform: [{ rotate: expanded ? '180deg' : '0deg' }] }}
                            />
                          </View>
                        </Pressable>
                        {expanded && (
                          <View style={styles.passengersList}>
                            {driverPassengers.map((p) => (
                              <Pressable
                                key={p.id}
                                onPress={() => router.push(`/(auth)/profile/${p.requester_id}`)}
                                style={styles.passengerBlock}
                                hitSlop={4}
                              >
                                <View style={styles.passengerHeader}>
                                  <UserAvatar
                                    name={p.display_name}
                                    avatarUrl={p.avatar_url}
                                    size={18}
                                  />
                                  <Text style={styles.passengerName} numberOfLines={1}>
                                    {p.display_name}
                                  </Text>
                                </View>
                                {(p.pickup_from || p.requested_pickup_at) && (
                                  <View style={styles.passengerMetaRow}>
                                    {p.pickup_from && (
                                      <>
                                        <MapPin size={10} color={colors.textMuted} strokeWidth={2.2} />
                                        <Text style={styles.passengerMetaText} numberOfLines={1}>
                                          {p.pickup_from}
                                        </Text>
                                      </>
                                    )}
                                    {p.pickup_from && p.requested_pickup_at && (
                                      <Text style={styles.passengerMetaText}>·</Text>
                                    )}
                                    {p.requested_pickup_at && (
                                      <>
                                        <Clock size={10} color={colors.textMuted} strokeWidth={2.2} />
                                        <Text style={styles.passengerMetaText}>
                                          {dayjs(p.requested_pickup_at).format('H[h]mm')}
                                        </Text>
                                      </>
                                    )}
                                  </View>
                                )}
                              </Pressable>
                            ))}
                          </View>
                        )}
                      </>
                    );
                  })()}
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
                    <Icon size={11} color={colors.textSecondary} strokeWidth={2.4} />
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
            {/* Section 1 — Inventaire commun (shared gear only). Always
                expanded; the "+ Ajouter" affordance lives in the header
                so the section reads as a single unit and the list isn't
                pushed down by a separate CTA. The chip + per-item tap
                are gated on isActive so terminated activities read as
                read-only history. */}
            <View style={styles.gearSection}>
              <View style={styles.collapsibleHeader}>
                <Text style={styles.transportCategoryLabel}>
                  {t('group.gearSection.inventory', { defaultValue: 'Inventaire' })}
                </Text>
                <Text style={styles.transportCategoryCount}>· {groupItems.length}</Text>
                <View style={styles.collapsibleSpacer} />
                {isActive && (
                  <Pressable
                    style={styles.addGearChip}
                    onPress={onAddGear}
                    hitSlop={6}
                  >
                    <Plus size={12} color={colors.cta} strokeWidth={2.5} />
                    <Text style={styles.addGearChipText}>
                      {t('group.addGearShort', { defaultValue: 'Ajouter' })}
                    </Text>
                  </Pressable>
                )}
              </View>

              {groupItems.length > 0 && (
                <View style={styles.inventoryList}>
                  {groupItems.map((g) => (
                    <Pressable
                      key={g.name}
                      style={styles.inventoryItem}
                      onPress={() => isActive && onEditGearItem(g.name, true)}
                      disabled={!isActive}
                      hitSlop={4}
                    >
                      <Plus size={14} color={colors.cta} strokeWidth={2.5} />
                      <Text style={styles.inventoryItemName} numberOfLines={1}>
                        {g.name}
                      </Text>
                      <View style={styles.partyPillRow}>
                        {g.bringers.map((b) => (
                          <View key={b.user_id} style={styles.partyPillSuccess}>
                            <UserAvatar
                              size={18}
                              name={b.display_name}
                              avatarUrl={b.avatar_url}
                            />
                            <Text style={styles.partyPillQtySuccess}>×{b.quantity}</Text>
                          </View>
                        ))}
                      </View>
                    </Pressable>
                  ))}
                </View>
              )}
            </View>

            {/* Section 2 — Qui apporte quoi. Per-bringer collapsible
                blocks. Same data as before, just no longer paired with
                a catalog-aware Inventaire above. */}
            {bringers.length > 0 && (
              <View style={[styles.gearSection, groupItems.length > 0 && styles.gearSectionSpacer]}>
                <View style={styles.transportCategoryHeader}>
                  <Text style={styles.transportCategoryLabel}>
                    {t('group.gearSection.recap', { defaultValue: 'Inventaire individuel' })}
                  </Text>
                  <Text style={styles.transportCategoryCount}>· {bringers.length}</Text>
                </View>

                {bringers.map((b) => {
                  const isSelf = b.user_id === currentUserId;
                  const isExpanded = expandedBringers.has(b.user_id);
                  return (
                    <View key={b.user_id} style={styles.bringerBlock}>
                      <Pressable
                        style={styles.bringerHeader}
                        onPress={() => toggleBringer(b.user_id)}
                        hitSlop={4}
                      >
                        <Pressable
                          onPress={() => router.push(`/(auth)/profile/${b.user_id}`)}
                          hitSlop={4}
                        >
                          <UserAvatar
                            name={b.display_name}
                            avatarUrl={b.avatar_url}
                            size={22}
                          />
                        </Pressable>
                        <Text style={styles.bringerName} numberOfLines={1}>
                          {b.display_name}
                        </Text>
                        {isSelf && (
                          <View style={styles.youTag}>
                            <Text style={styles.youTagText}>
                              {t('group.youTag', { defaultValue: 'Toi' })}
                            </Text>
                          </View>
                        )}
                        <Text style={styles.bringerCount}>
                          · {b.items.length}
                        </Text>
                        <View style={styles.collapsibleSpacer} />
                        <ChevronDown
                          size={13}
                          color={colors.textMuted}
                          strokeWidth={2}
                          style={{ transform: [{ rotate: isExpanded ? '180deg' : '0deg' }] }}
                        />
                      </Pressable>
                      {isExpanded && (
                        <View style={styles.bringerItemsList}>
                          {b.items.map((it) => (
                            <View key={it.name} style={styles.bulletRow}>
                              <Text style={[styles.bullet, { color: colors.success }]}>•</Text>
                              <Text style={styles.bulletText} numberOfLines={1}>{it.name}</Text>
                              <Text style={styles.itemQty}>×{it.quantity}</Text>
                            </View>
                          ))}
                        </View>
                      )}
                    </View>
                  );
                })}
              </View>
            )}

            {groupItems.length === 0 && bringers.length === 0 && (
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
  card: {
    backgroundColor: colors.surface,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.line,
    overflow: 'hidden',
  },

  // Header band — surfaceAlt bg + bottom divider mark it as its own
  // zone, distinct from the card body. Mirrors my-outing-card's
  // header band so the two cards read as siblings.
  headerBand: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm + 2,
    backgroundColor: colors.surfaceAlt,
    borderBottomWidth: 1,
    borderBottomColor: colors.line,
  },
  cardTitle: {
    flex: 1,
    color: colors.textPrimary,
    fontSize: fontSizes.xs + 1,
    fontWeight: '800',
    letterSpacing: 1.4,
    textTransform: 'uppercase',
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
    textTransform: 'uppercase',
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
    backgroundColor: colors.success + '20',
    borderWidth: 1,
    borderColor: colors.success + '60',
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
  driverPill: {
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.lineStrong,
    borderRadius: radius.md,
    padding: spacing.sm + 2,
    gap: 6,
  },
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
    color: colors.success,
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
    gap: 6,
  },
  transportCategoryHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
    marginTop: 4,
  },
  transportCategoryLabel: {
    color: colors.textSecondary,
    fontSize: 11,
    fontWeight: '800',
    letterSpacing: 1.2,
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
  reserveBtn: {
    backgroundColor: colors.cta + '14',
    borderRadius: 999,
    paddingHorizontal: 10,
    paddingVertical: 4,
  },
  reserveBtnText: {
    color: colors.cta,
    fontSize: fontSizes.xs + 1,
    fontWeight: '700',
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
    backgroundColor: colors.success + '1F',
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
    gap: 6,
    marginTop: 4,
  },
  selfMoverRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingVertical: 6,
    paddingHorizontal: 8,
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
  emptyHint: {
    color: colors.textMuted,
    fontSize: fontSizes.xs + 1,
    fontStyle: 'italic',
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
    borderWidth: 1,
    borderColor: colors.lineStrong,
    borderRadius: radius.md,
    padding: spacing.sm + 2,
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
    gap: 4,
  },
  inventoryItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingVertical: 4,
    paddingHorizontal: 8,
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
    color: colors.success,
    fontSize: fontSizes.sm,
    fontWeight: '700',
    letterSpacing: 0.2,
    marginLeft: 6,
  },
});
