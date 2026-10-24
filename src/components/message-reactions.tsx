import { useMemo, useState } from 'react';
import { View, Pressable, StyleSheet } from 'react-native';
import { AppText } from '@/components/app-text';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import type { MessageReaction } from '@/services/message-service';

// Emoji reactions, as WhatsApp (Scott 2026-10-24): one per person per message.
// Long-press → a bar of six + « + » for more; reactions hang under the bubble.
export const QUICK_REACTIONS = ['👍', '❤️', '😂', '😮', '🙌', '🔥'] as const;
const MORE_REACTIONS = [
  '😍', '🥰', '😎', '🤩', '😅', '🤣', '😢', '😭', '😡', '🤔', '🙏', '👏',
  '💪', '🤙', '👌', '✌️', '🎉', '💯', '⛰️', '🏔️', '🧗', '🚴', '🏄', '🪂',
  '☀️', '❄️', '🌧️', '⚡', '🥾', '🍻', '😴', '🤞',
] as const;

interface PillsProps {
  reactions: MessageReaction[];
  currentUser: string | null;
  align: 'left' | 'right';
  onToggle: (emoji: string) => void;
}

// Grouped by emoji, most-used first; mine is outlined, a tap on a pill sets
// (or removes) that emoji as mine.
export function ReactionPills({ reactions, currentUser, align, onToggle }: PillsProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const groups = useMemo(() => {
    const by = new Map<string, { count: number; mine: boolean }>();
    for (const r of reactions) {
      const g = by.get(r.emoji) ?? { count: 0, mine: false };
      g.count += 1;
      if (r.user_id === currentUser) g.mine = true;
      by.set(r.emoji, g);
    }
    return [...by.entries()].sort((a, b) => b[1].count - a[1].count);
  }, [reactions, currentUser]);

  return (
    <View style={[styles.pills, align === 'right' ? styles.pillsRight : styles.pillsLeft]}>
      {groups.map(([emoji, g]) => (
        <Pressable
          key={emoji}
          onPress={() => onToggle(emoji)}
          hitSlop={4}
          style={[styles.pill, g.mine && styles.pillMine]}
        >
          <AppText style={styles.pillEmoji}>{emoji}</AppText>
          {g.count > 1 && <AppText style={styles.pillCount}>{g.count}</AppText>}
        </Pressable>
      ))}
    </View>
  );
}

interface BarProps {
  mine: string | null;
  onPick: (emoji: string) => void;
}

export function ReactionBar({ mine, onPick }: BarProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const [more, setMore] = useState(false);

  return (
    <View style={styles.barWrap}>
      <View style={styles.bar}>
        {QUICK_REACTIONS.map((e) => (
          <Pressable key={e} onPress={() => onPick(e)} hitSlop={2} style={[styles.barItem, mine === e && styles.barItemMine]}>
            <AppText style={styles.barEmoji}>{e}</AppText>
          </Pressable>
        ))}
        <Pressable onPress={() => setMore((v) => !v)} hitSlop={2} style={[styles.barPlus, more && styles.barPlusOpen]}>
          <AppText style={styles.barPlusText}>{more ? '−' : '+'}</AppText>
        </Pressable>
      </View>
      {more && (
        <View style={styles.grid}>
          {MORE_REACTIONS.map((e) => (
            <Pressable key={e} onPress={() => onPick(e)} style={[styles.gridItem, mine === e && styles.barItemMine]}>
              <AppText style={styles.barEmoji}>{e}</AppText>
            </Pressable>
          ))}
        </View>
      )}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  // Hangs on the bubble's lower edge, overlapping it a little.
  pills: { flexDirection: 'row', flexWrap: 'wrap', gap: 4, marginTop: -8, zIndex: 2 },
  pillsLeft: { alignSelf: 'flex-start', marginLeft: 10 },
  pillsRight: { alignSelf: 'flex-end', marginRight: 10 },
  pill: {
    flexDirection: 'row', alignItems: 'center', gap: 2,
    backgroundColor: colors.background, borderRadius: radius.full,
    paddingHorizontal: 6, paddingVertical: 2,
    borderWidth: 1, borderColor: colors.background,
    ...shadows.card,
  },
  pillMine: { borderColor: colors.cta },
  pillEmoji: { fontSize: fontSizes.xs + 1 },
  pillCount: { fontSize: fontSizes.xs - 1, fontWeight: '700', color: colors.textSecondary },
  barWrap: { marginBottom: spacing.sm },
  bar: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    backgroundColor: colors.surfaceAlt, borderRadius: radius.full,
    paddingHorizontal: spacing.sm, paddingVertical: 6,
  },
  barItem: { width: 40, height: 40, borderRadius: 20, alignItems: 'center', justifyContent: 'center' },
  barItemMine: { backgroundColor: colors.background },
  barEmoji: { fontSize: 24 },
  barPlus: {
    width: 34, height: 34, borderRadius: 17, alignItems: 'center', justifyContent: 'center',
    backgroundColor: colors.background,
  },
  barPlusOpen: { backgroundColor: colors.lineStrong },
  barPlusText: { fontSize: fontSizes.lg, fontWeight: '700', color: colors.textSecondary },
  grid: { flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'center', marginTop: spacing.sm },
  gridItem: { width: 44, height: 44, borderRadius: 22, alignItems: 'center', justifyContent: 'center' },
});
