import { useMemo, useState, type ReactNode } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { ChevronDown } from 'lucide-react-native';
import { fontSizes, spacing } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';

interface Props {
  title: string;
  // Short summary of the current selection, shown on the collapsed header
  // (e.g. "3 sports", "50 km", "Cette semaine"). null → nothing.
  summary?: string | null;
  defaultExpanded?: boolean;
  // Bottom divider line (default true). Set false when the section sits inside
  // its own bordered container (e.g. the "Ta dispo" panel).
  bordered?: boolean;
  // Render the chevron inside a round tinted button (default false), matching
  // the Discovery partner cards' details toggle.
  chevronBoxed?: boolean;
  children: ReactNode;
}

// A filter section: tappable header with a chevron that expands/collapses the
// body. Collapsed by default; the header shows a summary of the current choice.
export function CollapsibleSection({ title, summary, defaultExpanded = false, bordered = true, chevronBoxed = false, children }: Props) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const [expanded, setExpanded] = useState(defaultExpanded);

  return (
    <View style={[styles.section, !bordered && { borderBottomWidth: 0 }]}>
      <Pressable style={styles.header} onPress={() => setExpanded((e) => !e)}>
        <Text style={styles.title}>{title}</Text>
        <View style={styles.right}>
          {!expanded && !!summary && <Text style={styles.summary} numberOfLines={1}>{summary}</Text>}
          <View style={[chevronBoxed && styles.chevBtn, { transform: [{ rotate: expanded ? '180deg' : '0deg' }] }]}>
            <ChevronDown size={18} color={chevronBoxed ? colors.cta : colors.textSecondary} strokeWidth={chevronBoxed ? 2.6 : 2.4} />
          </View>
        </View>
      </Pressable>
      {expanded && <View style={styles.body}>{children}</View>}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  section: { borderBottomWidth: 1, borderBottomColor: colors.borderMuted },
  header: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingVertical: spacing.md,
  },
  title: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  right: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, flexShrink: 1, minWidth: 0 },
  summary: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '600', flexShrink: 1 },
  body: { paddingBottom: spacing.md },
  chevBtn: { width: 26, height: 26, borderRadius: 13, backgroundColor: colors.cta + '1A', borderWidth: 1, borderColor: colors.cta + '40', alignItems: 'center', justifyContent: 'center' },
});
