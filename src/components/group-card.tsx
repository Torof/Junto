import { useMemo } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useQuery } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { router } from 'expo-router';
import dayjs from 'dayjs';
import { Users, MapPin, Clock, Plus, Check, ChevronRight, Bike, TrainFront, Footprints, HelpCircle, Package, Handshake, Shield, type LucideIcon } from 'lucide-react-native';
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
  onReserveSeat: (driverId: string) => void;
  onClaimGearItem: (itemName: string) => void;
  onToggleDetails: () => void;
  showDetailsActive: boolean;
}

const CAR_TYPES = ['car', 'carpool'] as const;

const MODE_ICONS: Record<string, typeof Bike> = {
  bike: Bike,
  on_foot: Footprints,
  public_transport: TrainFront,
  other: HelpCircle,
};

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
  onReserveSeat,
  onClaimGearItem,
  onToggleDetails,
  showDetailsActive,
}: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

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

  // Drivers offering rides — exclude the current user's own car (it's
  // already represented in Mine). Sort by departure time ascending so
  // the earliest meet-up surfaces first.
  const drivers = useMemo(() => {
    const acceptedByDriver = new Map<string, number>();
    seatAssignments.forEach((r) =>
      acceptedByDriver.set(r.driver_id, (acceptedByDriver.get(r.driver_id) ?? 0) + 1),
    );
    return transports
      .filter((p) => {
        if (p.user_id === currentUserId) return false;
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
  }, [transports, seatAssignments, currentUserId]);

  // Self-going modes (bike / foot / public / other) — small one-line
  // chips so the user knows who's coming under their own steam.
  const selfMovers = useMemo(() => {
    return transports.filter((p) => {
      if (p.user_id === currentUserId) return false;
      if (!p.transport_type) return false;
      return !(CAR_TYPES as readonly string[]).includes(p.transport_type);
    });
  }, [transports, currentUserId]);

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
        <View style={styles.band}>
          <View style={styles.bandIconWrap}>
            <Users size={14} color={colors.textSecondary} strokeWidth={2.2} />
          </View>
          <View style={{ flex: 1, minWidth: 0 }}>
            <Text style={styles.bandTitle}>
              {t('group.title', { defaultValue: 'Le groupe' })}
            </Text>
            <Text style={styles.bandMeta}>
              {t('group.peopleCount', {
                count: participants.length,
                defaultValue: `${participants.length} personnes`,
              })}
            </Text>
          </View>
        </View>

        {(drivers.length > 0 || selfMovers.length > 0) && (
          <View style={styles.section}>
            <Text style={styles.sectionLabel}>
              {t('group.transport', { defaultValue: 'Transport' })}
            </Text>

            {drivers.map((d) => {
              const isMyDriver = myAcceptedSeat?.driver_id === d.user_id;
              const isPendingFromMe = myPending?.driver_id === d.user_id;
              const isFull = d.free === 0;
              const score = reliabilityById.get(d.user_id) ?? null;
              const ringColor = score !== null ? ringColorFor(score) : null;
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
                      {(() => {
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
                  </View>
                  <View style={styles.seatsCluster}>
                    {(d.transport_from_name || d.transport_departs_at) && (
                      <Text style={styles.seatsCount}>
                        {d.accepted}/{d.capacity}
                      </Text>
                    )}
                    {isMyDriver ? (
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

            {selfMovers.length > 0 && (
              <View style={styles.selfMoversRow}>
                {selfMovers.map((p) => {
                  const Icon = MODE_ICONS[p.transport_type ?? 'other'] ?? HelpCircle;
                  return (
                    <View key={p.user_id} style={styles.selfChip}>
                      <Icon size={11} color={colors.textMuted} strokeWidth={2} />
                      <Text style={styles.selfChipText} numberOfLines={1}>
                        {p.display_name}
                      </Text>
                    </View>
                  );
                })}
              </View>
            )}

            {drivers.length === 0 && selfMovers.length === 0 && (
              <Text style={styles.emptyHint}>
                {t('group.noTransportYet', {
                  defaultValue: 'Personne n\'a encore dit comment il y va',
                })}
              </Text>
            )}
          </View>
        )}

        {hasGear && (
          <View style={[styles.section, styles.sectionTopBorder, { borderTopColor: colors.line }]}>
            <View style={styles.gearHeader}>
              <Text style={styles.sectionLabel}>
                {t('group.gear', { defaultValue: 'Matériel commun' })}
              </Text>
              <Text style={styles.gearProgress}>
                {coveredItems.length}/{coveredItems.length + missingItems.length}
              </Text>
            </View>

            {coveredItems.length > 0 && (
              <View style={styles.coveredChipsRow}>
                {coveredItems.map((c) => (
                  <View key={c.name} style={styles.coveredChip}>
                    <Check size={10} color={colors.success} strokeWidth={3} />
                    <Text style={styles.coveredChipText} numberOfLines={1}>
                      {c.name}
                      {c.have > c.required ? ` ×${c.have}` : ''}
                    </Text>
                  </View>
                ))}
              </View>
            )}

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

            {missingItems.length === 0 && coveredItems.length > 0 && (
              <Text style={styles.allCoveredHint}>
                {t('group.allGearCovered', { defaultValue: 'Tout est prévu côté matos' })}
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

  band: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.md,
    backgroundColor: colors.surfaceAlt,
    borderBottomWidth: 1,
    borderBottomColor: colors.line,
  },
  bandIconWrap: {
    width: 24,
    height: 24,
    borderRadius: 8,
    backgroundColor: colors.surface,
    alignItems: 'center',
    justifyContent: 'center',
  },
  bandTitle: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '700',
    letterSpacing: -0.1,
  },
  bandMeta: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '500',
    marginTop: 1,
  },

  section: {
    paddingVertical: spacing.sm + 2,
    paddingHorizontal: spacing.md,
    gap: spacing.sm,
  },
  sectionTopBorder: {
    borderTopWidth: 1,
  },
  sectionLabel: {
    color: colors.textMuted,
    fontSize: 9.5,
    fontWeight: '700',
    letterSpacing: 1.5,
    textTransform: 'uppercase',
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
  coveredChipsRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 6,
  },
  coveredChip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    backgroundColor: colors.success + '14',
    borderRadius: 6,
    paddingHorizontal: 7,
    paddingVertical: 3,
  },
  coveredChipText: {
    color: colors.textPrimary,
    fontSize: fontSizes.xs + 1,
    fontWeight: '500',
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
