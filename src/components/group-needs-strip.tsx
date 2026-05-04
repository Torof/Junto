import { useMemo } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useQuery } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { Plus } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { spacing, fontSizes, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { gearService } from '@/services/gear-service';

interface Props {
  activityId: string;
  sportKey: string;
  isParticipant: boolean;
  onClaimGearItem: (itemName: string) => void;
}

interface Need {
  itemName: string;
  category: 'safety' | 'technical' | 'water' | 'personal';
  required: number;
  have: number;
}

// Step 3 of the organization remodel: a calm "what's left to figure out"
// strip — only what's missing, never what's covered. Hidden entirely
// when the group is set, so the absence of this strip is itself the
// reassurance.
//
// Coordination voice, not marketplace: "À apporter par quelqu'un",
// not "Demande de matériel". One-tap claim per item; tapping "J'apporte"
// opens the existing per-item gear sheet for that exact item via the
// imperative handle on GearSection.
//
// Step 1+ scope: shared catalog gaps only. Per-person items deferred to
// step 4 when "I have my own" lands.
export function GroupNeedsStrip({
  activityId,
  sportKey,
  isParticipant,
  onClaimGearItem,
}: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

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

  const needs = useMemo<Need[]>(() => {
    if (!isParticipant) return [];
    const declaredByName = new Map<string, number>();
    gearDeclared.forEach((g) =>
      declaredByName.set(g.gear_name, (declaredByName.get(g.gear_name) ?? 0) + g.quantity),
    );
    return gearCatalog
      .filter((c) => !c.per_person)
      .map((c) => {
        const required = c.shared_recommended_qty ?? 1;
        const have = declaredByName.get(c.name_key) ?? 0;
        return have < required
          ? {
              itemName: c.name_key,
              category: c.category_key,
              required,
              have,
            }
          : null;
      })
      .filter((n): n is Need => n !== null)
      // Safety first — same priority logic as the verdict.
      .sort((a, b) => {
        if (a.category === 'safety' && b.category !== 'safety') return -1;
        if (b.category === 'safety' && a.category !== 'safety') return 1;
        return 0;
      });
  }, [gearDeclared, gearCatalog, isParticipant]);

  if (!isParticipant) return null;
  if (needs.length === 0) return null;

  return (
    <View style={styles.card}>
      <Text style={styles.caption}>
        {t('groupNeeds.caption', { defaultValue: 'À régler ensemble' })}
      </Text>
      {needs.map((n) => (
        <Pressable
          key={n.itemName}
          style={styles.row}
          onPress={() => onClaimGearItem(n.itemName)}
          hitSlop={4}
        >
          <View
            style={[
              styles.dot,
              { backgroundColor: n.category === 'safety' ? colors.error : colors.textMuted },
            ]}
          />
          <Text style={styles.itemName} numberOfLines={1}>
            {n.itemName}
            {n.required > 1 ? ` ×${n.required}` : ''}
          </Text>
          <View style={styles.claimBtn}>
            <Plus size={11} color={colors.cta} strokeWidth={2.6} />
            <Text style={styles.claimText}>
              {t('groupNeeds.bringIt', { defaultValue: "J'apporte" })}
            </Text>
          </View>
        </Pressable>
      ))}
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
    paddingVertical: 4,
  },
  dot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  itemName: {
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
});
