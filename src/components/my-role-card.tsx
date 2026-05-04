import { useMemo } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useQuery } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { Car, Users, Backpack, ChevronRight } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { spacing, fontSizes, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { transportService } from '@/services/transport-service';
import { gearService } from '@/services/gear-service';

interface Props {
  activityId: string;
  currentUserId: string | null;
  isParticipant: boolean;
  onEditTransport: () => void;
  onEditGearItem: (itemName: string) => void;
}

const CAR_TYPES = ['car', 'carpool'] as const;

// Step 2 of the organization remodel: a single card showing what the
// current user has committed to across both transport and gear. Replaces
// the need to scan two separate sections to know "what am I doing for
// this activity?"
//
// Display-only on the line level; tapping a line opens the existing
// editor (TransportSection's editor sheet for transport, GearSection's
// item sheet for a specific gear contribution). Imperative handles on
// those sections do the open — no sub-tab navigation required.
export function MyRoleCard({
  activityId,
  currentUserId,
  isParticipant,
  onEditTransport,
  onEditGearItem,
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
  const { data: gearDeclared = [] } = useQuery({
    queryKey: ['activity-gear', activityId],
    queryFn: () => gearService.getForActivity(activityId),
    enabled: isParticipant,
  });

  const transportLine = useMemo(() => {
    if (!currentUserId) return null;
    const myTransport = transports.find((p) => p.user_id === currentUserId);
    const myAcceptedSeat = seatAssignments.find((r) => r.requester_id === currentUserId);

    // Driver — having transport_type 'car' or 'carpool' takes priority,
    // even if you also have an accepted seat (data oddity, but driver wins).
    if (myTransport && (CAR_TYPES as readonly string[]).includes(myTransport.transport_type ?? '')) {
      const seats = myTransport.transport_seats ?? 0;
      const from = myTransport.transport_from_name?.trim();
      if (from && seats > 0) {
        return t('myRole.drivingFromWithSeats', {
          from,
          count: seats,
          defaultValue: `Tu conduis depuis ${from} · ${seats} place${seats > 1 ? 's' : ''} libre${seats > 1 ? 's' : ''}`,
        });
      }
      if (from) {
        return t('myRole.drivingFrom', { from, defaultValue: `Tu conduis depuis ${from}` });
      }
      if (seats > 0) {
        return t('myRole.drivingWithSeats', {
          count: seats,
          defaultValue: `Tu conduis · ${seats} place${seats > 1 ? 's' : ''} libre${seats > 1 ? 's' : ''}`,
        });
      }
      return t('myRole.driving', { defaultValue: 'Tu conduis' });
    }

    // Passenger — accepted seat with another driver
    if (myAcceptedSeat) {
      const driver = transports.find((p) => p.user_id === myAcceptedSeat.driver_id);
      const driverName = driver?.display_name ?? '?';
      return t('myRole.passenger', {
        driver: driverName,
        defaultValue: `Tu es passager avec ${driverName}`,
      });
    }

    // Other declared modes
    if (myTransport?.transport_type) {
      const key = `myRole.mode.${myTransport.transport_type}`;
      return t(key, { defaultValue: `Tu y vas en ${myTransport.transport_type}` });
    }

    return null;
  }, [transports, seatAssignments, currentUserId, t]);

  const myGearItems = useMemo(() => {
    if (!currentUserId) return [];
    return gearDeclared
      .filter((g) => g.user_id === currentUserId)
      .map((g) => ({ name: g.gear_name, quantity: g.quantity }));
  }, [gearDeclared, currentUserId]);

  if (!isParticipant) return null;

  // Hide entirely when the user hasn't done anything yet — the verdict
  // already says "Il reste à dire comment tu y vas". An empty role card
  // beneath that would be noise.
  const hasAnyRole = transportLine !== null || myGearItems.length > 0;
  if (!hasAnyRole) return null;

  return (
    <View style={styles.card}>
      <Text style={styles.caption}>{t('myRole.caption', { defaultValue: 'Ton rôle' })}</Text>

      {transportLine && (
        <Pressable style={styles.row} onPress={onEditTransport} hitSlop={4}>
          <View style={styles.iconWrap}>
            {seatAssignments.some((r) => r.requester_id === currentUserId) ? (
              <Users size={14} color={colors.cta} strokeWidth={2.2} />
            ) : (
              <Car size={14} color={colors.cta} strokeWidth={2.2} />
            )}
          </View>
          <Text style={styles.rowText} numberOfLines={2}>{transportLine}</Text>
          <ChevronRight size={14} color={colors.textMuted} strokeWidth={2} />
        </Pressable>
      )}

      {myGearItems.length > 0 && (
        <View style={styles.gearRow}>
          <View style={styles.iconWrap}>
            <Backpack size={14} color={colors.cta} strokeWidth={2.2} />
          </View>
          <View style={styles.gearItemsWrap}>
            <Text style={styles.gearLabel}>
              {t('myRole.bringingLabel', { defaultValue: 'Tu apportes' })}
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
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  card: {
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.line,
    paddingVertical: spacing.sm + 2,
    paddingHorizontal: spacing.sm + 4,
    marginBottom: spacing.md,
    gap: spacing.sm,
  },
  caption: {
    color: colors.textMuted,
    fontSize: 9.5,
    fontWeight: '700',
    letterSpacing: 1.5,
    textTransform: 'uppercase',
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  iconWrap: {
    width: 24,
    height: 24,
    borderRadius: 8,
    backgroundColor: colors.cta + '14',
    alignItems: 'center',
    justifyContent: 'center',
  },
  rowText: {
    flex: 1,
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '500',
    lineHeight: 19,
  },
  gearRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: spacing.sm,
  },
  gearItemsWrap: {
    flex: 1,
    gap: 4,
  },
  gearLabel: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '500',
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
});
