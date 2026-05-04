import { useMemo } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useQuery } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import {
  Car,
  Users,
  Backpack,
  AlertCircle,
  Check,
  Plus,
  Bike,
  TrainFront,
  Footprints,
  HelpCircle,
  Compass,
  ChevronRight,
} from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { spacing, fontSizes, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { transportService } from '@/services/transport-service';
import { gearService } from '@/services/gear-service';
import { sportCategoryColor } from '@/utils/sport-category-color';

interface Props {
  activityId: string;
  sportKey: string;
  sportIcon: string;
  sportCategory: string | null;
  startsAt: string;
  meetingPointName: string | null;
  fallbackTitle: string;
  currentUserId: string | null;
  isParticipant: boolean;
  onEditTransport: () => void;
  onEditGearItem: (itemName: string) => void;
  onToggleDetails: () => void;
  showDetailsActive: boolean;
}

const CAR_TYPES = ['car', 'carpool'] as const;

// One unified card replacing the previous verdict + role + needs trio.
// Carries the user's role for THIS outing (transport + gear) plus, when
// present, a single quiet pending block for what's still left to figure
// out together. The card itself is the synthesis — top band tells you
// which outing it is, body tells you what you're doing for it, optional
// bottom row tells you what's still up.
//
// Coordination voice, not marketplace: the pending block phrases gaps as
// "Manque la corde dans le matos commun · J'apporte", not as a listing.
export function MyOutingCard({
  activityId,
  sportKey,
  sportIcon,
  sportCategory,
  startsAt,
  meetingPointName,
  fallbackTitle,
  currentUserId,
  isParticipant,
  onEditTransport,
  onEditGearItem,
  onToggleDetails,
  showDetailsActive,
}: Props) {
  const { t, i18n } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  // The accent the top band borrows. Falls back to CTA orange for unknown
  // categories so the card still feels intentional even on edge sports.
  const accent = useMemo(
    () => sportCategoryColor(sportCategory, colors.cta),
    [sportCategory, colors.cta],
  );

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

  const role = useMemo(() => {
    if (!currentUserId) return null;
    const myTransport = transports.find((p) => p.user_id === currentUserId);
    const myAcceptedSeat = seatAssignments.find((r) => r.requester_id === currentUserId);
    const myPending = pendingRequests.find((r) => r.requester_id === currentUserId);

    // Pending — waiting on a driver's reply. Treated as a "your role
    // is in motion" state, not "set", so no PRÊT seal yet.
    if (myPending) {
      const driver = transports.find((p) => p.user_id === myPending.driver_id);
      return {
        kind: 'pending' as const,
        Icon: Users,
        sentence: t('myOuting.role.pending', {
          driver: driver?.display_name ?? '?',
          defaultValue: `Tu attends la réponse de ${driver?.display_name ?? '?'} pour la place`,
        }),
        sub: null as string | null,
      };
    }

    // Driver — having car/carpool with explicit seats wins over passenger
    // status if both somehow exist (data oddity), since being a driver
    // is the more committed role.
    if (myTransport && (CAR_TYPES as readonly string[]).includes(myTransport.transport_type ?? '')) {
      const seats = myTransport.transport_seats ?? 0;
      const from = myTransport.transport_from_name?.trim() ?? null;
      let sentence: string;
      let sub: string | null = null;
      if (from) {
        sentence = t('myOuting.role.drivingFrom', {
          from,
          defaultValue: `Tu conduis depuis ${from}`,
        });
      } else {
        sentence = t('myOuting.role.driving', { defaultValue: 'Tu conduis' });
      }
      if (seats > 0) {
        sub = t('myOuting.role.seatsFree', {
          count: seats,
          defaultValue: `${seats} place${seats > 1 ? 's' : ''} libre${seats > 1 ? 's' : ''} dans la voiture`,
        });
      }
      return { kind: 'driver' as const, Icon: Car, sentence, sub };
    }

    // Passenger — accepted seat with another driver.
    if (myAcceptedSeat) {
      const driver = transports.find((p) => p.user_id === myAcceptedSeat.driver_id);
      return {
        kind: 'passenger' as const,
        Icon: Users,
        sentence: t('myOuting.role.passenger', {
          driver: driver?.display_name ?? '?',
          defaultValue: `Tu es passager avec ${driver?.display_name ?? '?'}`,
        }),
        sub: myAcceptedSeat.pickup_from
          ? t('myOuting.role.passengerPickup', {
              from: myAcceptedSeat.pickup_from,
              defaultValue: `Récupéré à ${myAcceptedSeat.pickup_from}`,
            })
          : null,
      };
    }

    // Other declared modes — bike, foot, public, other.
    if (myTransport?.transport_type) {
      const Icon =
        myTransport.transport_type === 'bike'
          ? Bike
          : myTransport.transport_type === 'on_foot'
            ? Footprints
            : myTransport.transport_type === 'public_transport'
              ? TrainFront
              : HelpCircle;
      return {
        kind: 'self' as const,
        Icon,
        sentence: t(`myOuting.role.mode.${myTransport.transport_type}`, {
          defaultValue: `Tu y vas en ${myTransport.transport_type}`,
        }),
        sub: null,
      };
    }

    // Empty — no transport declared. The CTA-tinted state directs the
    // user to the primary action; this is also what Scott was missing
    // when the previous layout buried the entry point.
    return {
      kind: 'empty' as const,
      Icon: Compass,
      sentence: t('myOuting.role.empty', { defaultValue: 'Dis comment tu y vas' }),
      sub: null,
    };
  }, [transports, seatAssignments, pendingRequests, currentUserId, t]);

  const myGearItems = useMemo(() => {
    if (!currentUserId) return [];
    return gearDeclared
      .filter((g) => g.user_id === currentUserId)
      .map((g) => ({ name: g.gear_name, quantity: g.quantity }));
  }, [gearDeclared, currentUserId]);

  // Shared safety gaps — same logic the previous verdict used. Per-person
  // items deferred to the future "I have my own" state.
  const sharedSafetyMissing = useMemo(() => {
    const declaredByName = new Map<string, number>();
    gearDeclared.forEach((g) =>
      declaredByName.set(g.gear_name, (declaredByName.get(g.gear_name) ?? 0) + g.quantity),
    );
    return gearCatalog.filter((c) => {
      if (c.category_key !== 'safety') return false;
      if (c.per_person) return false;
      const required = c.shared_recommended_qty ?? 1;
      const have = declaredByName.get(c.name_key) ?? 0;
      return have < required;
    });
  }, [gearDeclared, gearCatalog]);

  const isReady = useMemo(() => {
    if (!role) return false;
    return (
      (role.kind === 'driver' || role.kind === 'passenger' || role.kind === 'self') &&
      sharedSafetyMissing.length === 0
    );
  }, [role, sharedSafetyMissing]);

  if (!isParticipant || !role) return null;

  const dateLabel = dayjs(startsAt).locale(i18n.language === 'fr' ? 'fr' : 'en').format(
    i18n.language === 'fr' ? 'D MMM' : 'MMM D',
  );
  const sportLabel = t(`sports.${sportKey}`, { defaultValue: sportKey });
  const placeLabel = meetingPointName?.trim() || fallbackTitle;

  return (
    <View style={styles.cardWrapper}>
      <View style={[styles.card, { borderColor: accent + '4D' }]}>
        {/* Top band — sport identity + date + meeting point. The thin
            tinted band is the card's "passport" — same tinting language
            we use on the small sport pill in the activity header, so
            family read carries. */}
        <View style={[styles.band, { backgroundColor: accent + '1F' }]}>
          <Text style={styles.bandIcon}>{sportIcon}</Text>
          <View style={{ flex: 1, minWidth: 0 }}>
            <Text style={[styles.bandSport, { color: accent }]} numberOfLines={1}>
              {sportLabel}
            </Text>
            <Text style={styles.bandMeta} numberOfLines={1}>
              {dateLabel}
              {placeLabel ? ` · ${placeLabel}` : ''}
            </Text>
          </View>
          {isReady && (
            <View style={[styles.readySeal, { borderColor: colors.success }]}>
              <Check size={11} color={colors.success} strokeWidth={3} />
              <Text style={[styles.readySealText, { color: colors.success }]}>
                {t('myOuting.ready', { defaultValue: 'Prêt' })}
              </Text>
            </View>
          )}
        </View>

        <View style={styles.body}>
          {/* Role row — single sentence + optional sub. Tappable: opens
              transport editor whatever the state. The empty state uses
              the CTA color to read as "primary action here". */}
          <Pressable style={styles.roleRow} onPress={onEditTransport} hitSlop={4}>
            <View
              style={[
                styles.roleIconWrap,
                {
                  backgroundColor:
                    role.kind === 'empty' ? colors.cta + '1F' : accent + '14',
                },
              ]}
            >
              <role.Icon
                size={16}
                color={role.kind === 'empty' ? colors.cta : accent}
                strokeWidth={2.2}
              />
            </View>
            <View style={{ flex: 1, minWidth: 0 }}>
              <Text
                style={[
                  styles.roleSentence,
                  role.kind === 'empty' && { color: colors.cta },
                ]}
                numberOfLines={2}
              >
                {role.sentence}
              </Text>
              {role.sub && (
                <Text style={styles.roleSub} numberOfLines={1}>
                  {role.sub}
                </Text>
              )}
            </View>
            <ChevronRight size={14} color={colors.textMuted} strokeWidth={2} />
          </Pressable>

          {myGearItems.length > 0 && (
            <View style={styles.gearRow}>
              <View style={[styles.roleIconWrap, { backgroundColor: accent + '14' }]}>
                <Backpack size={14} color={accent} strokeWidth={2.2} />
              </View>
              <View style={{ flex: 1 }}>
                <Text style={styles.gearLabel}>
                  {t('myOuting.bringingLabel', { defaultValue: 'Tu apportes' })}
                </Text>
                <View style={styles.gearChipsRow}>
                  {myGearItems.map((g) => (
                    <Pressable
                      key={g.name}
                      style={styles.gearChip}
                      onPress={() => onEditGearItem(g.name)}
                      hitSlop={4}
                    >
                      <Text style={styles.gearChipName} numberOfLines={1}>
                        {g.name}
                        {g.quantity > 1 ? ` ×${g.quantity}` : ''}
                      </Text>
                    </Pressable>
                  ))}
                </View>
              </View>
            </View>
          )}
        </View>

        {/* Pending zone — only when there's an actual gap to fill.
            Phrased as collective coordination ("dans le matos commun"),
            not a listing. Limit to one item at a time so the card stays
            calm; if there are several, surface the most critical (safety
            is the only category we list here, sorted by display order). */}
        {sharedSafetyMissing.length > 0 && (
          <Pressable
            style={[styles.pendingRow, { borderTopColor: colors.line }]}
            onPress={() => onEditGearItem(sharedSafetyMissing[0]!.name_key)}
            hitSlop={4}
          >
            <AlertCircle size={14} color={colors.error} strokeWidth={2.2} />
            <Text style={styles.pendingText} numberOfLines={2}>
              {sharedSafetyMissing.length === 1
                ? t('myOuting.pendingOne', {
                    item: sharedSafetyMissing[0]!.name_key,
                    defaultValue: `Manque ${sharedSafetyMissing[0]!.name_key} dans le matos commun`,
                  })
                : t('myOuting.pendingMany', {
                    count: sharedSafetyMissing.length,
                    defaultValue: `${sharedSafetyMissing.length} équipements de sécurité à apporter`,
                  })}
            </Text>
            <View style={[styles.claimBtn, { backgroundColor: colors.cta + '14' }]}>
              <Plus size={11} color={colors.cta} strokeWidth={2.6} />
              <Text style={[styles.claimText, { color: colors.cta }]}>
                {t('myOuting.bringIt', { defaultValue: "J'apporte" })}
              </Text>
            </View>
          </Pressable>
        )}

        {/* Power-user escape hatch — opens the existing TransportSection
            + GearSection dense lists. Most users should never need it. */}
        <Pressable
          style={[styles.detailsRow, { borderTopColor: colors.line }]}
          onPress={onToggleDetails}
          hitSlop={4}
        >
          <Text style={styles.detailsText}>
            {showDetailsActive
              ? t('myOuting.hideDetails', { defaultValue: 'Masquer les détails' })
              : t('myOuting.showDetails', { defaultValue: 'Voir tous les détails' })}
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
    overflow: 'hidden',
  },

  // Top band
  band: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.md,
  },
  bandIcon: { fontSize: 22, lineHeight: 24 },
  bandSport: {
    fontSize: fontSizes.sm,
    fontWeight: '800',
    letterSpacing: -0.2,
    textTransform: 'capitalize',
  },
  bandMeta: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '500',
    marginTop: 1,
  },
  readySeal: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    borderWidth: 1.5,
    borderRadius: 999,
    paddingHorizontal: 8,
    paddingVertical: 2,
  },
  readySealText: {
    fontSize: 9.5,
    fontWeight: '800',
    letterSpacing: 1,
    textTransform: 'uppercase',
  },

  // Body
  body: {
    paddingVertical: spacing.md - 2,
    paddingHorizontal: spacing.md,
    gap: spacing.sm + 2,
  },
  roleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  roleIconWrap: {
    width: 28,
    height: 28,
    borderRadius: 9,
    alignItems: 'center',
    justifyContent: 'center',
  },
  roleSentence: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm + 1,
    fontWeight: '600',
    lineHeight: 20,
    letterSpacing: -0.1,
  },
  roleSub: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs + 1,
    fontWeight: '500',
    marginTop: 1,
  },

  // Gear chips
  gearRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: spacing.sm,
  },
  gearLabel: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '500',
    marginBottom: 4,
  },
  gearChipsRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 6,
  },
  gearChip: {
    backgroundColor: colors.surfaceAlt,
    borderRadius: 6,
    paddingHorizontal: 8,
    paddingVertical: 4,
  },
  gearChipName: {
    color: colors.textPrimary,
    fontSize: fontSizes.xs + 1,
    fontWeight: '500',
  },

  // Pending zone
  pendingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    paddingVertical: spacing.sm + 2,
    paddingHorizontal: spacing.md,
    borderTopWidth: 1,
  },
  pendingText: {
    flex: 1,
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '500',
    lineHeight: 18,
  },
  claimBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 3,
    borderRadius: 999,
    paddingHorizontal: 10,
    paddingVertical: 4,
  },
  claimText: {
    fontSize: fontSizes.xs + 1,
    fontWeight: '700',
  },

  // Details escape hatch
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
