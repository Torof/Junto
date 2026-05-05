import { useMemo, useState } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useQuery } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { router } from 'expo-router';
import dayjs from 'dayjs';
import { Users, MapPin, Clock, Check, ChevronDown, Car, Bike, TrainFront, Footprints, HelpCircle, Package, Handshake, Shield, Plus, type LucideIcon } from 'lucide-react-native';
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
  currentUserId: string | null;
  isParticipant: boolean;
  activeSubTab: 'transport' | 'gear';
  onActiveSubTabChange: (tab: 'transport' | 'gear') => void;
  onReserveSeat: (driverId: string) => void;
  onAddGear: () => void;
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
  activeSubTab,
  onActiveSubTabChange,
  onReserveSeat,
  onAddGear,
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

  // Aggregate group inventory — every declared item, summed across
  // bringers, sorted alphabetically. Catalog comparison logic was
  // dropped on Scott's call: the gear surface is now a transparent
  // "what does the group have?" view, no missing/covered/quotas. If
  // the user wants to add something they go through Mine's "Ajouter
  // du matériel" path.
  const groupItems = useMemo(() => {
    const map = new Map<string, { name: string; total: number }>();
    gearDeclared.forEach((g) => {
      const existing = map.get(g.gear_name);
      if (existing) {
        existing.total += g.quantity;
      } else {
        map.set(g.gear_name, { name: g.gear_name, total: g.quantity });
      }
    });
    return Array.from(map.values()).sort((a, b) =>
      a.name.localeCompare(b.name, 'fr', { sensitivity: 'base' }),
    );
  }, [gearDeclared]);

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

  const hasAnyContent = drivers.length > 0 || selfMovers.length > 0 || gearDeclared.length > 0;
  if (!hasAnyContent) return null;

  return (
    <View style={styles.cardWrapper}>
      <View style={styles.card}>
        {/* Header row — title on the left, people count on the right.
            Pulled up here from the old band so the tab strip below
            can occupy a full prominent row of its own. */}
        <View style={styles.header}>
          <Text style={styles.cardTitle} numberOfLines={1}>
            {t('group.cardTitle', { defaultValue: 'Préparatifs de groupe' })}
          </Text>
          <View style={styles.headerRight}>
            <Users size={14} color={colors.textSecondary} strokeWidth={2.2} />
            <Text style={styles.peopleCount} numberOfLines={1}>
              {t('group.peopleCount', {
                count: participants.length,
                defaultValue: `${participants.length} personnes`,
              })}
            </Text>
          </View>
        </View>

        {/* Prominent tab strip — full-width, equal split, active tab
            marked with a CTA-coloured underline so the toggle is
            unmissable. Replaces the folder-tab metaphor that lived
            tucked into the old band. */}
        <View style={styles.tabStrip}>
          <Pressable
            onPress={() => onActiveSubTabChange('transport')}
            style={[styles.tab, activeSubTab === 'transport' && styles.tabActive]}
            hitSlop={4}
          >
            <Text style={[
              styles.tabLabel,
              activeSubTab === 'transport' && styles.tabLabelActive,
            ]}>
              {t('group.transport', { defaultValue: 'Transport' })}
            </Text>
          </Pressable>
          <Pressable
            onPress={() => onActiveSubTabChange('gear')}
            style={[styles.tab, activeSubTab === 'gear' && styles.tabActive]}
            hitSlop={4}
          >
            <Text style={[
              styles.tabLabel,
              activeSubTab === 'gear' && styles.tabLabelActive,
            ]}>
              {t('group.gear', { defaultValue: 'Matériel' })}
            </Text>
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
            {isParticipant && (
              <Pressable style={styles.addGearCta} onPress={onAddGear}>
                <Plus size={16} color={colors.cta} strokeWidth={2.5} />
                <Text style={styles.addGearCtaText}>
                  {t('group.addGear', { defaultValue: 'Ajouter du matériel' })}
                </Text>
              </Pressable>
            )}

            {gearDeclared.length === 0 && (
              <Text style={styles.emptyHint}>
                {t('group.recapEmpty', { defaultValue: 'Personne n\'a encore déclaré de matériel' })}
              </Text>
            )}

            {/* Section 1 — Inventaire. A flat bullet list of every item
                the group has declared, summed across bringers. No
                catalog comparison, no missing/covered split, no quotas
                — just a transparent "what does the group have?" view.
                Collapsible. */}
            {groupItems.length > 0 && (
              <View style={styles.gearSection}>
                <Pressable
                  style={styles.collapsibleHeader}
                  onPress={() => setInventaireExpanded((v) => !v)}
                  hitSlop={4}
                >
                  <Text style={styles.transportCategoryLabel}>
                    {t('group.gearSection.inventory', { defaultValue: 'Inventaire' })}
                  </Text>
                  <Text style={styles.transportCategoryCount}>· {groupItems.length}</Text>
                  <View style={styles.collapsibleSpacer} />
                  <ChevronDown
                    size={14}
                    color={colors.textMuted}
                    strokeWidth={2}
                    style={{ transform: [{ rotate: inventaireExpanded ? '180deg' : '0deg' }] }}
                  />
                </Pressable>

                {inventaireExpanded && (
                  <View style={styles.bulletList}>
                    {groupItems.map((g) => (
                      <View key={g.name} style={styles.bulletRow}>
                        <Text style={[styles.bullet, { color: colors.success }]}>•</Text>
                        <Text style={styles.bulletText} numberOfLines={1}>{g.name}</Text>
                        <Text style={styles.itemQty}>×{g.total}</Text>
                      </View>
                    ))}
                  </View>
                )}
              </View>
            )}

            {/* Section 2 — Qui apporte quoi. Per-bringer collapsible
                blocks. Same data as before, just no longer paired with
                a catalog-aware Inventaire above. */}
            {bringers.length > 0 && (
              <View style={[styles.gearSection, groupItems.length > 0 && styles.gearSectionSpacer]}>
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

  // Header row — title left, people count right. Mirrors my-outing-card's
  // header structure so the two cards read as siblings.
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.md,
    paddingTop: spacing.md - 2,
    paddingBottom: spacing.sm,
  },
  cardTitle: {
    flex: 1,
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    fontWeight: '700',
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

  // Prominent tab strip — full-width, 50/50 split, active tab gets a
  // CTA-coloured underline. Replaces the folder-tab metaphor that
  // tucked into the old surfaceAlt band.
  tabStrip: {
    flexDirection: 'row',
    borderBottomWidth: 1,
    borderBottomColor: colors.line,
  },
  tab: {
    flex: 1,
    paddingVertical: spacing.sm + 2,
    alignItems: 'center',
    borderBottomWidth: 2,
    borderBottomColor: 'transparent',
    marginBottom: -1,
  },
  tabActive: {
    borderBottomColor: colors.cta,
  },
  tabLabel: {
    fontSize: fontSizes.sm,
    fontWeight: '600',
    color: colors.textMuted,
    letterSpacing: 0.3,
  },
  tabLabelActive: {
    color: colors.textPrimary,
    fontWeight: '700',
  },

  // Active tab content area. Padding kept identical to the previous
  // value so existing rows don't reflow.
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
  addGearCta: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center',
    gap: spacing.xs,
    paddingVertical: spacing.sm + 2,
    paddingHorizontal: spacing.md,
    borderRadius: radius.md,
    borderWidth: 1, borderColor: colors.cta,
    backgroundColor: colors.cta + '15',
    marginBottom: spacing.md,
  },
  addGearCtaText: {
    color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700',
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
