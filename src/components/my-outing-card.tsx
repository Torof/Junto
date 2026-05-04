import { useMemo, useState } from 'react';
import { View, Text, Pressable, Modal, ScrollView, StyleSheet } from 'react-native';
import { useQuery } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
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
  Minus,
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
export function MyOutingCard({
  activityId,
  startsAt,
  status,
  currentUserId,
  isParticipant,
  onEditTransport,
  onEditGearItem,
  onAddMaterial,
}: Props) {
  const { t, i18n } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const [showMyGear, setShowMyGear] = useState(false);

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

  // Caption — countdown / status. Computed against the user's local day
  // boundary so a 22h activity tonight reads "AUJOURD'HUI" right up to
  // midnight, then "EN COURS" once status flips.
  const captionText = useMemo(() => {
    if (status === 'in_progress') {
      return t('myOuting.captionInProgress', { defaultValue: 'En cours' });
    }
    const days = dayjs(startsAt).startOf('day').diff(dayjs().startOf('day'), 'day');
    if (days < 0) {
      return t('myOuting.captionPast', { defaultValue: 'Terminée' });
    }
    if (days === 0) {
      return t('myOuting.captionToday', { defaultValue: "Aujourd'hui" });
    }
    if (days === 1) {
      return t('myOuting.captionTomorrow', { defaultValue: 'Demain' });
    }
    if (days <= 30) {
      return t('myOuting.captionInDays', {
        count: days,
        defaultValue: `Dans ${days} jours`,
      });
    }
    // Far-future activities — just a short date so the caption doesn't
    // grow ridiculous ("Dans 87 jours" reads as nag, not reminder).
    return dayjs(startsAt)
      .locale(i18n.language === 'fr' ? 'fr' : 'en')
      .format(i18n.language === 'fr' ? 'D MMM' : 'MMM D');
  }, [startsAt, status, t, i18n.language]);

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
    // For the driver case, count the seats already taken by accepted
    // requesters — that's the user's passenger headcount.
    const myPassengerCount = seatAssignments.filter((r) => r.driver_id === currentUserId).length;

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
      const subRows: StampSubRow[] = [];
      if (from) {
        subRows.push({ Icon: MapPin, text: from });
      }
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
        caption: t('myOuting.stamp.transport', { defaultValue: 'Transport' }),
        Icon: Car,
        content: t('myOuting.stamp.transportDriver', { defaultValue: 'Conduis' }),
        state: 'set',
        subRows,
      };
    }

    if (myAcceptedSeat) {
      const driver = transports.find((p) => p.user_id === myAcceptedSeat.driver_id);
      const subRows: StampSubRow[] = [];
      if (myAcceptedSeat.pickup_from) {
        subRows.push({ Icon: MapPin, text: myAcceptedSeat.pickup_from });
      }
      return {
        caption: t('myOuting.stamp.transport', { defaultValue: 'Transport' }),
        Icon: Users,
        content: t('myOuting.stamp.transportPassenger', {
          driver: driver?.display_name ?? '?',
          defaultValue: `Passager · ${driver?.display_name ?? '?'}`,
        }),
        state: 'set',
        subRows: subRows.length > 0 ? subRows : undefined,
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
      caption: t('myOuting.stamp.material', { defaultValue: 'Matériel' }),
      Icon: Backpack,
      content: '',
      state: 'set',
      itemsList: visible,
      overflowCount: overflowCount > 0 ? overflowCount : undefined,
    };
  }, [myGearItems, t]);

  const isReady = transportStamp.state === 'set';

  if (!isParticipant) return null;

  return (
    <View style={styles.cardWrapper}>
      <View style={styles.card}>
        <View style={styles.header}>
          <Text style={styles.caption}>{captionText}</Text>
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
            onPress={onEditTransport}
            colors={colors}
            styles={styles}
            t={t}
          />
          <Stamp
            stamp={materialStamp}
            onPress={() => setShowMyGear(true)}
            colors={colors}
            styles={styles}
            t={t}
          />
        </View>
      </View>

      {/* Mon matériel sheet — full list of what I bring, each row tappable
          to edit, plus "Ajouter" to bring something new. The matériel
          stamp truncates at 2 lines; this sheet is where the rest lives. */}
      <Modal
        visible={showMyGear}
        animationType="slide"
        transparent
        onRequestClose={() => setShowMyGear(false)}
      >
        <Pressable style={styles.backdrop} onPress={() => setShowMyGear(false)}>
          <Pressable style={styles.sheet} onPress={(e) => e.stopPropagation()}>
            <View style={styles.handle} />
            <Text style={styles.sheetTitle}>
              {t('myOuting.gearListTitle', { defaultValue: 'Mon matériel' })}
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
                      setShowMyGear(false);
                      onEditGearItem(g.name);
                    }}
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
          </Pressable>
        </Pressable>
      </Modal>
    </View>
  );
}

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
  stampDottedDot: {
    width: 12,
    height: 12,
    borderRadius: 6,
    borderWidth: 1.5,
    borderStyle: 'dashed',
    backgroundColor: 'transparent',
  },

  // My-gear sheet (modal)
  backdrop: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.55)',
    justifyContent: 'flex-end',
  },
  sheet: {
    backgroundColor: colors.background,
    borderTopLeftRadius: radius.lg,
    borderTopRightRadius: radius.lg,
    padding: spacing.lg,
    paddingBottom: spacing.xl + 16,
    maxHeight: '70%',
  },
  handle: {
    width: 40,
    height: 4,
    borderRadius: 2,
    backgroundColor: colors.textSecondary,
    alignSelf: 'center',
    marginBottom: spacing.lg,
    opacity: 0.4,
  },
  sheetTitle: {
    color: colors.textPrimary,
    fontSize: fontSizes.lg,
    fontWeight: 'bold',
    marginBottom: spacing.md,
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
