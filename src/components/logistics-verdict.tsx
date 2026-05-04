import { useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { useQuery } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { Check, Clock, AlertCircle } from 'lucide-react-native';
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
}

type Tone = 'green' | 'amber' | 'red';

const COLOR_AMBER = '#E8A33D';
const COLOR_RED = '#E5524E';

// Step 1 of the organization remodel: a one-line, user-perspective verdict
// at the top of the Organisation tab. Synthesizes the existing transport +
// gear data into "you're set / one thing left / something's wrong" framed
// as a sentence a friend would say, not a dashboard.
//
// Read-only — no DB changes. Queries reuse the same keys as TransportSection
// + GearSection so TanStack dedupes the network calls.
export function LogisticsVerdict({ activityId, sportKey, currentUserId, isParticipant }: Props) {
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

  const verdict = useMemo(() => {
    if (!isParticipant || !currentUserId) return null;

    // Shared safety gaps only. Per-person safety items (helmet, harness)
    // are deferred to step 4 with the explicit "I have my own" state —
    // surfacing them here would panic-fire even when everyone brings
    // their own. Cf. the gear friction inventory.
    const declaredByName = new Map<string, number>();
    gearDeclared.forEach((g) =>
      declaredByName.set(g.gear_name, (declaredByName.get(g.gear_name) ?? 0) + g.quantity),
    );
    const missingSafety = gearCatalog.filter((c) => {
      if (c.category_key !== 'safety') return false;
      if (c.per_person) return false;
      const required = c.shared_recommended_qty ?? 1;
      const have = declaredByName.get(c.name_key) ?? 0;
      return have < required;
    });

    const myTransport = transports.find((p) => p.user_id === currentUserId);
    const myAcceptedSeat = seatAssignments.find((r) => r.requester_id === currentUserId);
    const myPendingSeat = pendingRequests.find((r) => r.requester_id === currentUserId);
    const driverForPending = myPendingSeat
      ? transports.find((p) => p.user_id === myPendingSeat.driver_id)
      : null;

    // Red — shared safety gear missing. The strongest signal; trumps
    // transport state because a missing rope means the activity itself
    // can't go ahead, regardless of who's driving.
    if (missingSafety.length > 0) {
      const names = missingSafety.map((m) => m.name_key);
      let sentence: string;
      if (names.length === 1) {
        sentence = t('logisticsVerdict.missingOne', {
          item: names[0],
          defaultValue: `Manque dans le matos commun : ${names[0]}`,
        });
      } else if (names.length === 2) {
        sentence = t('logisticsVerdict.missingTwo', {
          item1: names[0],
          item2: names[1],
          defaultValue: `Manque dans le matos commun : ${names[0]}, ${names[1]}`,
        });
      } else {
        sentence = t('logisticsVerdict.missingMany', {
          count: names.length,
          defaultValue: `${names.length} équipements de sécurité à apporter`,
        });
      }
      return { tone: 'red' as Tone, sentence };
    }

    // Amber — waiting on someone else (driver hasn't replied yet).
    if (myPendingSeat && driverForPending) {
      return {
        tone: 'amber' as Tone,
        sentence: t('logisticsVerdict.pendingSeat', {
          driver: driverForPending.display_name,
          defaultValue: `En attente de la réponse de ${driverForPending.display_name} pour la place`,
        }),
      };
    }

    // Amber — no transport declared and not riding with anyone.
    if (!myTransport && !myAcceptedSeat) {
      return {
        tone: 'amber' as Tone,
        sentence: t('logisticsVerdict.noTransportYet', {
          defaultValue: 'Il reste à dire comment tu y vas',
        }),
      };
    }

    // Green — transport sorted (declared own or accepted as passenger),
    // safety gear covered. Other gear gaps don't downgrade the verdict
    // by design: missing energy bars shouldn't make the activity feel
    // unready.
    return {
      tone: 'green' as Tone,
      sentence: t('logisticsVerdict.ready', { defaultValue: 'Tu es prêt' }),
    };
  }, [
    isParticipant,
    currentUserId,
    transports,
    seatAssignments,
    pendingRequests,
    gearDeclared,
    gearCatalog,
    t,
  ]);

  if (!verdict) return null;

  const accent =
    verdict.tone === 'green' ? colors.success
    : verdict.tone === 'amber' ? COLOR_AMBER
    : COLOR_RED;
  const Icon = verdict.tone === 'green' ? Check : verdict.tone === 'amber' ? Clock : AlertCircle;

  return (
    <View style={[styles.card, { borderLeftColor: accent }]}>
      <View style={[styles.iconBox, { backgroundColor: accent + '1F' }]}>
        <Icon size={14} color={accent} strokeWidth={2.4} />
      </View>
      <Text style={styles.sentence}>{verdict.sentence}</Text>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  card: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    borderLeftWidth: 3,
    borderTopWidth: 1,
    borderRightWidth: 1,
    borderBottomWidth: 1,
    borderTopColor: colors.line,
    borderRightColor: colors.line,
    borderBottomColor: colors.line,
    paddingVertical: spacing.sm + 2,
    paddingHorizontal: spacing.sm + 4,
    marginBottom: spacing.md,
  },
  iconBox: {
    width: 26,
    height: 26,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  sentence: {
    flex: 1,
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '500',
    lineHeight: 19,
  },
});
