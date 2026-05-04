import { useMemo, useState } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useQuery } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { router } from 'expo-router';
import dayjs from 'dayjs';
import { Users, MapPin, Clock, Plus, Check, ChevronRight, ChevronDown, Car, Bike, TrainFront, Footprints, HelpCircle, Package, Handshake, Shield, type LucideIcon } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { spacing, fontSizes, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { transportService } from '@/services/transport-service';
import { gearService } from '@/services/gear-service';
import { participationService } from '@/services/participation-service';
import { badgeService } from '@/services/badge-service';
import { UserAvatar } from './user-avatar';
import { ringColorFor } from './profile-hero';
import { supabase } from '@/services/supabase';

// Icon for each positive peer-vouch trait. Shown inline next to driver
// names so the trust signal reaches the decision point ("ride with this
// stranger?"). Same mapping as badge-display.tsx — kept inline rather
// than imported to keep this file self-contained.
const VOUCH_ICONS: Record<string, LucideIcon> = {
  punctual: Clock,
  prepared: Package,
  conciliant: Handshake,
  prudent: Shield,
};

interface Props {
  activityId: string;
  sportKey: string;
  currentUserId: string | null;
  isParticipant: boolean;
  // Active sub-section is owned by the parent so the in-card folder
  // tabs and the "Voir tous les détails" dense expansion stay in sync —
  // tapping a tab in the card sets the same state the dense view uses.
  activeSubTab: 'transport' | 'gear';
  onActiveSubTabChange: (tab: 'transport' | 'gear') => void;
  onReserveSeat: (driverId: string) => void;
  onClaimGearItem: (itemName: string) => void;
  onToggleDetails: () => void;
  showDetailsActive: boolean;
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
  sportKey,
  currentUserId,
  isParticipant,
  activeSubTab,
  onActiveSubTabChange,
  onReserveSeat,
  onClaimGearItem,
  onToggleDetails,
  showDetailsActive,
}: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  // Collapse state for the Matériel sub-sections. Inventaire opens by
  // default (it's the action surface — claim missing items, see the
  // covered list); the bringer recaps stay closed by default since
  // they're info-shaped and only useful when the user is curious
  // about a specific person's contribution.
  const [inventaireExpanded, setInventaireExpanded] = useState(true);
  const [expandedBringers, setExpandedBringers] = useState<Set<string>>(new Set());
  const toggleBringer = (userId: string) => {
    setExpandedBringers((prev) => {
      const next = new Set(prev);
      if (next.has(userId)) next.delete(userId);
      else next.add(userId);
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
  const { data: gearCatalog = [] } = useQuery({
    queryKey: ['gear-catalog', sportKey],
    queryFn: () => gearService.getCatalog(sportKey),
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
  const transportUserIdsKey = transports.map((p) => p.user_id).sort().join(',');
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

  // Top positive peer-vouch per driver — surfaced as an inline chip next
  // to their name. Batch RPC (mig 00174) returns at most one row per
  // user, threshold-gated at 5 votes. Stale cache fine; vouches change
  // slowly compared to transport state.
  const { data: topVouches = [] } = useQuery({
    queryKey: ['top-vouched-badges', transportUserIdsKey],
    queryFn: () => badgeService.getTopVouchedBadges(transports.map((p) => p.user_id)),
    enabled: isParticipant && transports.length > 0,
    staleTime: 5 * 60_000,
  });
  const vouchById = useMemo(() => {
    const map = new Map<string, { badge_key: string; vote_count: number }>();
    topVouches.forEach((v) => map.set(v.user_id, { badge_key: v.badge_key, vote_count: v.vote_count }));
    return map;
  }, [topVouches]);

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

  // Gear coverage — group view of the catalog. Per-person items deferred
  // until step 4 brings the explicit "I have my own" state.
  const { coveredItems, missingItems } = useMemo(() => {
    const declaredByName = new Map<string, number>();
    gearDeclared.forEach((g) =>
      declaredByName.set(g.gear_name, (declaredByName.get(g.gear_name) ?? 0) + g.quantity),
    );
    const covered: { name: string; have: number; required: number; isSafety: boolean }[] = [];
    const missing: { name: string; required: number; isSafety: boolean }[] = [];
    gearCatalog
      .filter((c) => !c.per_person)
      .forEach((c) => {
        const required = c.shared_recommended_qty ?? 1;
        const have = declaredByName.get(c.name_key) ?? 0;
        if (have >= required) {
          covered.push({ name: c.name_key, have, required, isSafety: c.category_key === 'safety' });
        } else {
          missing.push({ name: c.name_key, required, isSafety: c.category_key === 'safety' });
        }
      });
    // Safety first within missing — same priority as the verdict logic.
    missing.sort((a, b) => (a.isSafety === b.isSafety ? 0 : a.isSafety ? -1 : 1));
    return { coveredItems: covered, missingItems: missing };
  }, [gearDeclared, gearCatalog]);

  // Critical gap signal — when a SAFETY catalog item is missing in
  // the shared pool, the activity itself can't safely go ahead. We
  // surface this on the inactive Matériel mini-tab so the
  // Transport-default doesn't bury a deal-breaker behind a tap.
  const hasMissingSafety = useMemo(
    () => missingItems.some((m) => m.isSafety),
    [missingItems],
  );

  // Total catalog count drives the "X/Y prêt" header subtitle on the
  // Inventaire section. (Progress bar removed — the count + the
  // missing-items rows together tell the same readiness story.)
  const totalCatalog = coveredItems.length + missingItems.length;

  // "Qui apporte quoi" recap — group declared gear by user_id,
  // sorted by contribution count descending so heavy contributors
  // anchor the top. Includes self (with TOI tag at render time)
  // for confirmation that their commitment is registered.
  const bringers = useMemo(() => {
    const map = new Map<string, {
      user_id: string;
      display_name: string;
      avatar_url: string | null;
      items: { name: string; quantity: number }[];
    }>();
    gearDeclared.forEach((g) => {
      const existing = map.get(g.user_id);
      if (existing) {
        existing.items.push({ name: g.gear_name, quantity: g.quantity });
      } else {
        map.set(g.user_id, {
          user_id: g.user_id,
          display_name: g.display_name,
          avatar_url: g.avatar_url,
          items: [{ name: g.gear_name, quantity: g.quantity }],
        });
      }
    });
    return Array.from(map.values()).sort((a, b) => b.items.length - a.items.length);
  }, [gearDeclared]);

  // Whether the current user is allowed to request a seat right now —
  // mirrors TransportSection's existing rule so the affordance behaves
  // consistently with the dense view.
  const canReserve = useMemo(() => {
    if (!currentUserId) return false;
    const myTransport = transports.find((p) => p.user_id === currentUserId);
    const isMyselfDriver =
      myTransport && (CAR_TYPES as readonly string[]).includes(myTransport.transport_type ?? '');
    const myAcceptedSeat = seatAssignments.find((r) => r.requester_id === currentUserId);
    return !isMyselfDriver && !myAcceptedSeat;
  }, [transports, seatAssignments, currentUserId]);

  const myAcceptedSeat = seatAssignments.find((r) => r.requester_id === currentUserId);
  const myPending = pendingRequests.find((r) => r.requester_id === currentUserId);

  if (!isParticipant) return null;

  const hasGear = gearCatalog.length > 0;
  const hasAnyContent = drivers.length > 0 || selfMovers.length > 0 || hasGear;
  if (!hasAnyContent) return null;

  return (
    <View style={styles.cardWrapper}>
      <View style={styles.card}>
        {/* Header band — single row carrying the icon + people count
            on the left and folder-shaped tabs flush against the bottom
            edge on the right. Active tab has surface bg matching the
            content area below, so the tab visually "lifts" out of the
            surfaceAlt band and merges with the content (the file-folder
            metaphor). Inactive tab stays on the band, looking tucked. */}
        <View style={styles.band}>
          <View style={styles.bandIconWrap}>
            <Users size={14} color={colors.textSecondary} strokeWidth={2.2} />
          </View>
          <Text style={styles.bandPeopleCount} numberOfLines={1}>
            {t('group.peopleCount', {
              count: participants.length,
              defaultValue: `${participants.length} personnes`,
            })}
          </Text>
          <Pressable
            onPress={() => onActiveSubTabChange('transport')}
            style={[styles.folderTab, activeSubTab === 'transport' && styles.folderTabActive]}
            hitSlop={4}
          >
            <Text style={[
              styles.folderTabText,
              activeSubTab === 'transport' && styles.folderTabTextActive,
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
              styles.folderTabText,
              activeSubTab === 'gear' && styles.folderTabTextActive,
            ]}>
              {t('group.gear', { defaultValue: 'Matériel' })}
            </Text>
            {hasMissingSafety && activeSubTab !== 'gear' && (
              <View style={[styles.folderTabUrgentDot, { backgroundColor: colors.error }]} />
            )}
          </Pressable>
        </View>

        {activeSubTab === 'transport' && (
          <View style={styles.tabContent}>
            {/* Free-seats banner — at-a-glance answer to "is there a ride
                available, and from where?". Hidden when no driver has
                free seats so the surface stays calm in that case. */}
            {totalFreeSeats > 0 && (
              <View style={styles.freeSeatsBanner}>
                <Text style={styles.freeSeatsCount}>
                  {t('group.freeSeatsCount', {
                    count: totalFreeSeats,
                    defaultValue: totalFreeSeats === 1 ? '1 place libre' : `${totalFreeSeats} places libres`,
                  })}
                </Text>
                {departureCities.length > 0 && (
                  <Text style={styles.freeSeatsFrom} numberOfLines={2}>
                    {t('group.freeSeatsFrom', {
                      cities: departureCities.join(' · '),
                      defaultValue: `depuis ${departureCities.join(' · ')}`,
                    })}
                  </Text>
                )}
              </View>
            )}

            {drivers.length > 0 && (
              <View style={styles.transportCategory}>
                <View style={styles.transportCategoryHeader}>
                  <Car size={11} color={colors.textSecondary} strokeWidth={2.4} />
                  <Text style={styles.transportCategoryLabel}>
                    {t('group.transportCategory.car', { defaultValue: 'Voitures' })}
                  </Text>
                  <Text style={styles.transportCategoryCount}>· {drivers.length}</Text>
                </View>
                {drivers.map((d) => {
              const isSelf = d.user_id === currentUserId;
              const isMyDriver = myAcceptedSeat?.driver_id === d.user_id;
              const isPendingFromMe = myPending?.driver_id === d.user_id;
              const isFull = d.free === 0;
              const score = reliabilityById.get(d.user_id) ?? null;
              const ringColor = score !== null ? ringColorFor(score) : null;
              const driverPassengers = passengersByDriver.get(d.user_id) ?? [];
              return (
                <View key={d.user_id} style={styles.driverRow}>
                  <Pressable
                    style={[
                      styles.avatarRing,
                      ringColor && { borderColor: ringColor },
                    ]}
                    onPress={() => router.push(`/(auth)/profile/${d.user_id}`)}
                    hitSlop={4}
                  >
                    <UserAvatar
                      name={d.display_name}
                      avatarUrl={d.avatar_url}
                      size={32}
                      confirmedPresent={d.confirmed_present === true}
                    />
                  </Pressable>
                  <View style={{ flex: 1, minWidth: 0 }}>
                    <View style={styles.driverNameRow}>
                      <Text style={styles.driverName} numberOfLines={1}>
                        {d.display_name}
                      </Text>
                      {isSelf && (
                        <View style={styles.youTag}>
                          <Text style={styles.youTagText}>{t('group.youTag', { defaultValue: 'Toi' })}</Text>
                        </View>
                      )}
                      {!isSelf && (() => {
                        const vouch = vouchById.get(d.user_id);
                        if (!vouch) return null;
                        const Icon = VOUCH_ICONS[vouch.badge_key];
                        if (!Icon) return null;
                        const label = t(`badges.${vouch.badge_key}`, { defaultValue: vouch.badge_key });
                        return (
                          <>
                            <Text style={styles.vouchSep}>·</Text>
                            <Icon size={11} color={colors.success} strokeWidth={2.4} />
                            <Text style={styles.vouchLabel} numberOfLines={1}>{label}</Text>
                          </>
                        );
                      })()}
                    </View>
                    <View style={styles.driverMeta}>
                      {d.transport_from_name && (
                        <>
                          <MapPin size={11} color={colors.textSecondary} strokeWidth={2.2} />
                          <Text style={styles.driverMetaText} numberOfLines={1}>
                            {d.transport_from_name}
                          </Text>
                        </>
                      )}
                      {d.transport_from_name && d.transport_departs_at && (
                        <Text style={styles.driverMetaSep}> · </Text>
                      )}
                      {d.transport_departs_at && (
                        <>
                          <Clock size={11} color={colors.textSecondary} strokeWidth={2.2} />
                          <Text style={styles.driverMetaText}>
                            {dayjs(d.transport_departs_at).format('H[h]mm')}
                          </Text>
                        </>
                      )}
                      {!d.transport_from_name && !d.transport_departs_at && (
                        <Text style={styles.driverMetaText}>
                          {d.accepted}/{d.capacity} {t('group.seatsLabel', { defaultValue: 'places' })}
                        </Text>
                      )}
                    </View>
                    {/* Passengers — clearly nested under the driver via
                        a left-border "thread". Each entry is a 2-line
                        block: avatar + name on top, pickup place + time
                        on a sub-line beneath. The size + weight + color
                        contrast vs the driver's row keeps the hierarchy
                        unambiguous. Tap → that passenger's profile. */}
                    {driverPassengers.length > 0 && (
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
                  </View>
                  <View style={styles.seatsCluster}>
                    {(d.transport_from_name || d.transport_departs_at) && (
                      <Text style={styles.seatsCount}>
                        {d.accepted}/{d.capacity}
                      </Text>
                    )}
                    {isSelf ? (
                      // Self-driver shows no action pill — they manage
                      // via Mine's transport stamp. The "Toi" tag above
                      // already marks the row.
                      null
                    ) : isMyDriver ? (
                      <View style={styles.statusPillSet}>
                        <Check size={10} color={colors.success} strokeWidth={3} />
                        <Text style={[styles.statusPillText, { color: colors.success }]}>
                          {t('group.youAreAboard', { defaultValue: 'À bord' })}
                        </Text>
                      </View>
                    ) : isPendingFromMe ? (
                      <View style={styles.statusPillPending}>
                        <Text style={[styles.statusPillText, { color: colors.textMuted }]}>
                          {t('group.pendingRequest', { defaultValue: 'En attente' })}
                        </Text>
                      </View>
                    ) : isFull ? (
                      <Text style={styles.fullText}>
                        {t('group.full', { defaultValue: 'Complet' })}
                      </Text>
                    ) : canReserve ? (
                      <Pressable
                        style={styles.reserveBtn}
                        onPress={() => onReserveSeat(d.user_id)}
                        hitSlop={4}
                      >
                        <Text style={styles.reserveBtnText}>
                          {t('group.reserve', { defaultValue: 'Réserver' })}
                        </Text>
                      </Pressable>
                    ) : null}
                  </View>
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
                  <View style={styles.selfMoversRow}>
                    {list.map((p) => {
                      const isSelf = p.user_id === currentUserId;
                      return (
                        <View key={p.user_id} style={[styles.selfChip, isSelf && styles.selfChipSelf]}>
                          <Text style={[styles.selfChipText, isSelf && { color: colors.cta }]} numberOfLines={1}>
                            {isSelf ? t('group.youTag', { defaultValue: 'Toi' }) : p.display_name}
                          </Text>
                        </View>
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
            {!hasGear && bringers.length === 0 && (
              <Text style={styles.emptyHint}>
                {t('group.noGearForSport', { defaultValue: 'Pas de matériel commun pour ce sport' })}
              </Text>
            )}

            {/* Section 1 — Inventaire. Collapsible: header is tappable
                (chevron rotates), content shows missing-items rows +
                covered chips when expanded. Header subtitle "X/Y prêt"
                gives readiness at a glance even when collapsed. */}
            {hasGear && (
              <View style={styles.gearSection}>
                <Pressable
                  style={styles.collapsibleHeader}
                  onPress={() => setInventaireExpanded((v) => !v)}
                  hitSlop={4}
                >
                  <Text style={styles.transportCategoryLabel}>
                    {t('group.gearSection.inventory', { defaultValue: 'Inventaire' })}
                  </Text>
                  <Text style={styles.transportCategoryCount}>
                    · {t('group.progressLabel', {
                      covered: coveredItems.length,
                      total: totalCatalog,
                      defaultValue: `${coveredItems.length}/${totalCatalog} prêt`,
                    })}
                  </Text>
                  <View style={styles.collapsibleSpacer} />
                  <ChevronDown
                    size={14}
                    color={colors.textMuted}
                    strokeWidth={2}
                    style={{ transform: [{ rotate: inventaireExpanded ? '180deg' : '0deg' }] }}
                  />
                </Pressable>

                {inventaireExpanded && (
                  <>
                    {missingItems.map((m) => (
                      <Pressable
                        key={m.name}
                        style={styles.missingRow}
                        onPress={() => onClaimGearItem(m.name)}
                        hitSlop={4}
                      >
                        <View
                          style={[
                            styles.missingDot,
                            { backgroundColor: m.isSafety ? colors.error : colors.textMuted },
                          ]}
                        />
                        <Text style={styles.missingText} numberOfLines={1}>
                          {m.name}
                          {m.required > 1 ? ` ×${m.required}` : ''}
                        </Text>
                        <View style={styles.claimBtn}>
                          <Plus size={11} color={colors.cta} strokeWidth={2.6} />
                          <Text style={styles.claimText}>
                            {t('group.bringIt', { defaultValue: "J'apporte" })}
                          </Text>
                        </View>
                      </Pressable>
                    ))}

                    {coveredItems.length > 0 && (
                      <View style={styles.bulletList}>
                        {coveredItems.map((c) => (
                          <View key={c.name} style={styles.bulletRow}>
                            <Text style={[styles.bullet, { color: colors.success }]}>•</Text>
                            <Text style={styles.bulletText} numberOfLines={1}>
                              {c.name}
                              {c.have > c.required ? ` ×${c.have}` : ''}
                            </Text>
                          </View>
                        ))}
                      </View>
                    )}

                    {missingItems.length === 0 && coveredItems.length > 0 && (
                      <Text style={styles.allCoveredHint}>
                        {t('group.allGearCovered', { defaultValue: 'Tout est prévu côté matos' })}
                      </Text>
                    )}
                  </>
                )}
              </View>
            )}

            {/* Section 2 — Qui apporte quoi. Per-bringer block: avatar
                (tappable → profile) + name + their items as chips. Self
                gets the TOI tag for consistency with Transport's
                self-driver row. Sorted heaviest contributors first. */}
            {bringers.length > 0 && (
              <View style={[styles.gearSection, hasGear && styles.gearSectionSpacer]}>
                <View style={styles.transportCategoryHeader}>
                  <Text style={styles.transportCategoryLabel}>
                    {t('group.gearSection.recap', { defaultValue: 'Qui apporte quoi' })}
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
                              <Text style={styles.bulletText} numberOfLines={1}>
                                {it.name}
                                {it.quantity > 1 ? ` ×${it.quantity}` : ''}
                              </Text>
                            </View>
                          ))}
                        </View>
                      )}
                    </View>
                  );
                })}
              </View>
            )}

            {hasGear && bringers.length === 0 && (
              <Text style={[styles.emptyHint, { marginTop: spacing.sm }]}>
                {t('group.recapEmpty', { defaultValue: 'Personne n\'apporte encore de matériel' })}
              </Text>
            )}
          </View>
        )}

        <Pressable
          style={[styles.detailsRow, { borderTopColor: colors.line }]}
          onPress={onToggleDetails}
          hitSlop={4}
        >
          <Text style={styles.detailsText}>
            {showDetailsActive
              ? t('group.hideDetails', { defaultValue: 'Masquer les détails' })
              : t('group.showDetails', { defaultValue: 'Voir tous les détails' })}
          </Text>
          <ChevronRight
            size={12}
            color={colors.textMuted}
            strokeWidth={2}
            style={{ transform: [{ rotate: showDetailsActive ? '90deg' : '0deg' }] }}
          />
        </Pressable>
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

  // Band — single row, icon + people-count on the left, folder tabs
  // flush against the bottom on the right. NO borderBottom (the active
  // tab "tucks into" the content below; a separator line would break
  // the merge effect). The band's surfaceAlt bg is what the inactive
  // tab sits on; the active tab uses surface bg matching the content.
  band: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    gap: spacing.sm,
    paddingTop: 8,
    paddingHorizontal: spacing.sm + 2,
    backgroundColor: colors.surfaceAlt,
  },
  bandIconWrap: {
    width: 22,
    height: 22,
    borderRadius: 8,
    backgroundColor: colors.surface,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 6,
  },
  bandPeopleCount: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '700',
    letterSpacing: 0.4,
    flex: 1,
    minWidth: 0,
    paddingBottom: 8,
  },

  // Folder-shape tabs — sit at the bottom of the band, with rounded
  // top corners only. The active tab's bg matches the content area
  // below so the two visually merge into a single open folder. The
  // marginBottom: -1 lets the active tab's bottom edge tuck into the
  // content area, sealing any seam at the band/content boundary.
  folderTab: {
    paddingHorizontal: 12,
    paddingTop: 6,
    paddingBottom: 6,
    borderTopLeftRadius: radius.md,
    borderTopRightRadius: radius.md,
    backgroundColor: 'transparent',
    marginBottom: -1,
  },
  folderTabActive: {
    backgroundColor: colors.surface,
  },
  folderTabText: {
    fontSize: 11,
    fontWeight: '700',
    color: colors.textMuted,
    letterSpacing: -0.05,
  },
  folderTabTextActive: {
    color: colors.textPrimary,
  },
  folderTabUrgentDot: {
    position: 'absolute',
    top: -2,
    right: 2,
    width: 8,
    height: 8,
    borderRadius: 4,
    borderWidth: 1.5,
    borderColor: colors.surfaceAlt,
  },

  // Active tab content area — bg matches active folder tab so they
  // read as one continuous panel. Padding mirrors the previous section
  // values so existing rows don't reflow.
  tabContent: {
    paddingVertical: spacing.sm + 2,
    paddingHorizontal: spacing.md,
    gap: spacing.sm,
  },

  driverRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm + 2,
    paddingVertical: 2,
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
    gap: 4,
  },
  driverName: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '700',
    letterSpacing: -0.1,
    flexShrink: 1,
  },
  vouchSep: {
    color: colors.textMuted,
    fontSize: fontSizes.xs,
  },
  vouchLabel: {
    color: colors.success,
    fontSize: fontSizes.xs,
    fontWeight: '700',
    letterSpacing: -0.05,
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

  // Free-seats banner — pinned at the top of the Transport tab. Subtle
  // success-tinted bg + bold count + smaller "from cities" sub-line.
  // Only shown when at least one driver has free seats; otherwise the
  // surface stays calm.
  freeSeatsBanner: {
    backgroundColor: colors.success + '14',
    borderRadius: radius.sm,
    paddingVertical: 8,
    paddingHorizontal: 12,
    marginBottom: 4,
  },
  freeSeatsCount: {
    color: colors.success,
    fontSize: fontSizes.sm,
    fontWeight: '800',
    letterSpacing: -0.05,
  },
  freeSeatsFrom: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '500',
    marginTop: 2,
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
    color: colors.textMuted,
    fontSize: 10,
    fontWeight: '800',
    letterSpacing: 1.2,
    textTransform: 'uppercase',
  },
  transportCategoryCount: {
    color: colors.textMuted,
    fontSize: 10,
    fontWeight: '600',
  },

  // Passengers under each driver row — clearly nested via a vertical
  // "thread" border on the left. Each entry is a 2-line block (avatar
  // + name on top, pickup meta below) with smaller avatars / weights
  // / muted meta-text so the hierarchy vs the driver's full row is
  // unambiguous: driver = primary, passengers = secondary children.
  passengersList: {
    marginTop: 8,
    paddingLeft: 10,
    borderLeftWidth: 2,
    borderLeftColor: colors.line,
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
  driverMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 3,
    marginTop: 1,
  },
  driverMetaText: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
  },
  driverMetaSep: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
  },
  seatsCluster: {
    alignItems: 'flex-end',
    gap: 4,
  },
  seatsCount: {
    color: colors.textMuted,
    fontSize: 10,
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

  selfMoversRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 6,
    marginTop: 2,
  },
  selfChip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    backgroundColor: colors.surfaceAlt,
    borderRadius: 6,
    paddingHorizontal: 7,
    paddingVertical: 3,
  },
  // Same chip but with CTA accent border so the user spots their own
  // entry at a glance among the other self-movers.
  selfChipSelf: {
    backgroundColor: colors.cta + '1F',
    borderWidth: 1,
    borderColor: colors.cta + '4D',
  },
  selfChipText: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '500',
  },
  emptyHint: {
    color: colors.textMuted,
    fontSize: fontSizes.xs + 1,
    fontStyle: 'italic',
  },

  gearHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  gearProgress: {
    color: colors.textSecondary,
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

  // Recap — per-bringer block: avatar + name (+ TOI tag) on top,
  // chips listing their items below, indented under the name.
  bringerBlock: {
    gap: 5,
    paddingVertical: 4,
  },
  bringerHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  bringerName: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '600',
    letterSpacing: -0.05,
    flexShrink: 1,
  },
  bringerCount: {
    color: colors.textMuted,
    fontSize: fontSizes.xs,
    fontWeight: '600',
  },
  // Bullet list — single shared style for the covered-items list under
  // Inventaire and the per-bringer items list under the recap. One item
  // per row, success-green bullet (the "covered" / "brought" semantic
  // is the same in both contexts).
  bulletList: {
    gap: 2,
  },
  bringerItemsList: {
    gap: 2,
    paddingLeft: 28, // align under bringer's name (avatar 22 + gap 6)
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
  missingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    paddingVertical: 4,
  },
  missingDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  missingText: {
    flex: 1,
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '500',
  },
  claimBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 3,
    backgroundColor: colors.cta + '14',
    borderRadius: 999,
    paddingHorizontal: 10,
    paddingVertical: 4,
  },
  claimText: {
    color: colors.cta,
    fontSize: fontSizes.xs + 1,
    fontWeight: '700',
  },
  allCoveredHint: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs + 1,
    fontStyle: 'italic',
  },

  detailsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 4,
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.md,
    borderTopWidth: 1,
  },
  detailsText: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs + 1,
    fontWeight: '600',
    letterSpacing: 0.2,
  },
});
