import { useMemo } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useQuery } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
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
  Minus,
  type LucideIcon,
} from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { spacing, fontSizes, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { transportService } from '@/services/transport-service';
import { gearService } from '@/services/gear-service';

interface Props {
  activityId: string;
  sportKey: string;
  currentUserId: string | null;
  isParticipant: boolean;
  onEditTransport: () => void;
  onMaterialTap: () => void;
}

const CAR_TYPES = ['car', 'carpool'] as const;

type StampState = 'set' | 'pending' | 'todo' | 'neutral';

interface StampDef {
  caption: string;
  Icon: LucideIcon;
  content: string;
  state: StampState;
}

const COLOR_AMBER = '#E8A33D';

// Mine — your personal status panel for this outing. No activity identity
// (the screen header carries that already), no group state — this is a
// strict me-card. Two stamps: TRANSPORT (what mode/role I've taken) and
// MATÉRIEL (what I'm contributing). Each stamp's visual fills in as the
// state moves from "à régler" → "set"; PRÊT seal earns its place when
// transport is sorted (gear is optional, doesn't gate readiness).
//
// Tap behavior:
//   TRANSPORT stamp → opens the existing transport editor sheet.
//   MATÉRIEL stamp → if you've already declared something, opens that
//     first item's sheet so you can edit it; if you haven't, it expands
//     the dense gear view (handler in the parent) so you can pick.
export function MyOutingCard({
  activityId,
  sportKey,
  currentUserId,
  isParticipant,
  onEditTransport,
  onMaterialTap,
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

  const transportStamp = useMemo<StampDef>(() => {
    const empty: StampDef = {
      caption: t('myOuting.stamp.transport', { defaultValue: 'Transport' }),
      Icon: Compass,
      content: t('myOuting.stamp.toSettle', { defaultValue: 'À régler' }),
      state: 'todo',
    };
    if (!currentUserId) return empty;

    const myTransport = transports.find((p) => p.user_id === currentUserId);
    const myAcceptedSeat = seatAssignments.find((r) => r.requester_id === currentUserId);
    const myPending = pendingRequests.find((r) => r.requester_id === currentUserId);

    if (myPending) {
      const driver = transports.find((p) => p.user_id === myPending.driver_id);
      return {
        caption: t('myOuting.stamp.transport', { defaultValue: 'Transport' }),
        Icon: Clock,
        content: t('myOuting.stamp.transportPending', {
          driver: driver?.display_name ?? '?',
          defaultValue: `En attente · ${driver?.display_name ?? '?'}`,
        }),
        state: 'pending',
      };
    }

    if (myTransport && (CAR_TYPES as readonly string[]).includes(myTransport.transport_type ?? '')) {
      const from = myTransport.transport_from_name?.trim();
      const seats = myTransport.transport_seats ?? 0;
      return {
        caption: t('myOuting.stamp.transport', { defaultValue: 'Transport' }),
        Icon: Car,
        content: from
          ? t('myOuting.stamp.transportDriverFrom', {
              from,
              defaultValue: `Conduis · ${from}`,
            })
          : t('myOuting.stamp.transportDriver', { defaultValue: 'Conduis' }),
        state: 'set',
        // seats info is shown as a sub-line in render below — kept on the
        // stamp def implicitly via the role kind. We render seat count via
        // a small stamp footer when state === 'set' for drivers.
        ...(seats > 0 ? { seats } : {}),
      } as StampDef & { seats?: number };
    }

    if (myAcceptedSeat) {
      const driver = transports.find((p) => p.user_id === myAcceptedSeat.driver_id);
      return {
        caption: t('myOuting.stamp.transport', { defaultValue: 'Transport' }),
        Icon: Users,
        content: t('myOuting.stamp.transportPassenger', {
          driver: driver?.display_name ?? '?',
          defaultValue: `Passager · ${driver?.display_name ?? '?'}`,
        }),
        state: 'set',
      };
    }

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
        caption: t('myOuting.stamp.transport', { defaultValue: 'Transport' }),
        Icon,
        content: t(`myOuting.stamp.mode.${myTransport.transport_type}`, {
          defaultValue: myTransport.transport_type,
        }),
        state: 'set',
      };
    }

    return empty;
  }, [transports, seatAssignments, pendingRequests, currentUserId, t]);

  const myGearItems = useMemo(() => {
    if (!currentUserId) return [];
    return gearDeclared
      .filter((g) => g.user_id === currentUserId)
      .map((g) => ({ name: g.gear_name, quantity: g.quantity }));
  }, [gearDeclared, currentUserId]);

  const materialStamp = useMemo<StampDef>(() => {
    if (myGearItems.length === 0) {
      return {
        caption: t('myOuting.stamp.material', { defaultValue: 'Matériel' }),
        Icon: Backpack,
        content: t('myOuting.stamp.materialNothing', { defaultValue: 'Rien à apporter' }),
        state: 'neutral',
      };
    }
    // Compose the content string: up to two item names, then "+N more".
    const labels = myGearItems.map((g) => (g.quantity > 1 ? `${g.name} ×${g.quantity}` : g.name));
    let content: string;
    if (labels.length === 1) {
      content = labels[0]!;
    } else if (labels.length === 2) {
      content = labels.join(' · ');
    } else {
      content = `${labels[0]!} · ${labels[1]!} +${labels.length - 2}`;
    }
    return {
      caption: t('myOuting.stamp.material', { defaultValue: 'Matériel' }),
      Icon: Backpack,
      content,
      state: 'set',
    };
  }, [myGearItems, t]);

  // PRÊT logic — transport is the only required leg. Gear stays optional;
  // a passenger who isn't bringing anything shouldn't feel "not ready".
  const isReady = transportStamp.state === 'set';

  if (!isParticipant) return null;

  return (
    <View style={styles.cardWrapper}>
      <View style={styles.card}>
        <View style={styles.header}>
          <Text style={styles.caption}>
            {t('myOuting.caption', { defaultValue: 'Ton rôle' })}
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

        <View style={styles.stampsRow}>
          <Stamp
            stamp={transportStamp}
            seatsHint={
              transportStamp.state === 'set' && (transportStamp as StampDef & { seats?: number }).seats
                ? t('myOuting.stamp.seatsFree', {
                    count: (transportStamp as StampDef & { seats?: number }).seats!,
                    defaultValue: `${(transportStamp as StampDef & { seats?: number }).seats} place${(transportStamp as StampDef & { seats?: number }).seats! > 1 ? 's' : ''} libre${(transportStamp as StampDef & { seats?: number }).seats! > 1 ? 's' : ''}`,
                  })
                : null
            }
            onPress={onEditTransport}
            colors={colors}
            styles={styles}
          />
          <Stamp
            stamp={materialStamp}
            seatsHint={null}
            onPress={onMaterialTap}
            colors={colors}
            styles={styles}
          />
        </View>
      </View>
    </View>
  );
}

interface StampProps {
  stamp: StampDef;
  seatsHint: string | null;
  onPress: () => void;
  colors: AppColors;
  styles: ReturnType<typeof createStyles>;
}

function Stamp({ stamp, seatsHint, onPress, colors, styles }: StampProps) {
  // Visual coding by state. "set" reads as filled-and-done (success green),
  // "pending" and "todo" pull attention with amber, "neutral" stays muted
  // (the matériel "rien à apporter" case shouldn't ping for action).
  const accent =
    stamp.state === 'set' ? colors.success
    : stamp.state === 'pending' || stamp.state === 'todo' ? COLOR_AMBER
    : colors.textMuted;

  const isFilledLook = stamp.state === 'set' || stamp.state === 'pending';
  const dashedBorder = stamp.state === 'todo' || stamp.state === 'neutral';

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

      <Text
        style={[
          styles.stampContent,
          stamp.state === 'todo' || stamp.state === 'neutral'
            ? { color: colors.textSecondary }
            : { color: colors.textPrimary },
        ]}
        numberOfLines={2}
      >
        {stamp.content}
      </Text>

      {seatsHint && (
        <Text style={styles.stampSubHint} numberOfLines={1}>
          {seatsHint}
        </Text>
      )}

      <View style={styles.stampMarkRow}>
        {stamp.state === 'set' && <Check size={14} color={accent} strokeWidth={3} />}
        {stamp.state === 'pending' && <Clock size={14} color={accent} strokeWidth={2.4} />}
        {stamp.state === 'todo' && (
          <View style={[styles.stampDottedDot, { borderColor: accent }]} />
        )}
        {stamp.state === 'neutral' && <Minus size={14} color={colors.textMuted} strokeWidth={2.4} />}
      </View>
    </Pressable>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  cardWrapper: { marginBottom: spacing.md },
  card: {
    backgroundColor: colors.surface,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.line,
    paddingVertical: spacing.md - 2,
    paddingHorizontal: spacing.md,
  },

  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: spacing.sm + 2,
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
  stampSubHint: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '500',
    marginTop: 3,
  },
  stampMarkRow: {
    marginTop: 'auto',
    paddingTop: 6,
    flexDirection: 'row',
    justifyContent: 'flex-end',
    alignItems: 'center',
  },
  stampDottedDot: {
    width: 12,
    height: 12,
    borderRadius: 6,
    borderWidth: 1.5,
    borderStyle: 'dashed',
    backgroundColor: 'transparent',
  },
});
