import { useMemo, useState } from 'react';
import { View, Text, Pressable, Modal, StyleSheet, TextInput } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { Check, Search, X } from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { useMapStore } from '@/store/map-store';
import { useSports } from '@/hooks/use-sports';
import { getSportIcon } from '@/constants/sport-icons';
import { KeyboardAwareScrollView } from '@/components/keyboard-aware-scroll-view';

// Shared multi-select sport picker, bound to useMapStore.filters.sportKeys.
// Used by drawer-filter-bar and filter-sheet so the modal stays one piece.

interface Props {
  visible: boolean;
  onClose: () => void;
  useStore?: typeof useMapStore;
}

export function SportPickerSheet({ visible, onClose, useStore = useMapStore }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const filters = useStore((s) => s.filters);
  const toggleSportFilter = useStore((s) => s.toggleSportFilter);
  const [query, setQuery] = useState('');

  const { data: sports } = useSports();

  // Sort by translated name (alphabetical in user's locale).
  const sortedSports = useMemo(() => {
    if (!sports) return [];
    return [...sports].sort((a, b) => {
      const aName = t(`sports.${a.key}`, { defaultValue: a.key });
      const bName = t(`sports.${b.key}`, { defaultValue: b.key });
      return aName.localeCompare(bName);
    });
  }, [sports, t]);

  const visibleSports = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return sortedSports;
    return sortedSports.filter((s) =>
      t(`sports.${s.key}`, { defaultValue: s.key }).toLowerCase().includes(q),
    );
  }, [sortedSports, query, t]);

  return (
    <Modal visible={visible} animationType="slide" onRequestClose={onClose}>
      <SafeAreaView style={styles.screen} edges={['top', 'bottom']}>
        <View style={styles.header}>
          <Text style={styles.sheetTitle}>{t('map.sportLabel')}</Text>
          <Pressable onPress={onClose} hitSlop={10} accessibilityLabel={t('common.close', { defaultValue: 'Fermer' })}>
            <X size={24} color={colors.textPrimary} strokeWidth={2.2} />
          </Pressable>
        </View>

        <View style={styles.searchBar}>
          <Search size={18} color={colors.textSecondary} strokeWidth={2.2} />
          <TextInput
            style={styles.searchInput}
            value={query}
            onChangeText={setQuery}
            placeholder={t('map.searchSport', { defaultValue: 'Rechercher un sport' })}
            placeholderTextColor={colors.textSecondary}
            autoCorrect={false}
            autoCapitalize="none"
            autoFocus
          />
        </View>

        <KeyboardAwareScrollView style={styles.list} contentContainerStyle={styles.listContent} showsVerticalScrollIndicator={false}>
          {visibleSports.map((s) => {
            const isSelected = filters.sportKeys.includes(s.key);
            return (
              <Pressable
                key={s.key}
                style={styles.row}
                onPress={() => toggleSportFilter(s.key)}
              >
                <Text style={styles.rowEmoji}>{getSportIcon(s.key)}</Text>
                <Text style={[styles.rowLabel, isSelected && styles.rowLabelActive]} numberOfLines={1}>
                  {t(`sports.${s.key}`, { defaultValue: s.key })}
                </Text>
                {isSelected && <Check size={18} color={colors.cta} strokeWidth={2.4} />}
              </Pressable>
            );
          })}
        </KeyboardAwareScrollView>
      </SafeAreaView>
    </Modal>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.background },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.md,
    paddingBottom: spacing.sm,
  },
  sheetTitle: {
    color: colors.textPrimary,
    fontSize: fontSizes.lg,
    fontWeight: 'bold',
  },
  searchBar: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.md,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    marginHorizontal: spacing.lg,
    marginBottom: spacing.sm,
  },
  searchInput: {
    flex: 1,
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    padding: 0,
  },
  list: { flex: 1 },
  listContent: { paddingHorizontal: spacing.lg, paddingBottom: spacing.md },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    paddingVertical: spacing.sm + 2,
    paddingHorizontal: spacing.xs,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderMuted,
  },
  rowEmoji: {
    fontSize: 20,
    width: 28,
    textAlign: 'center',
  },
  rowLabel: {
    flex: 1,
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    fontWeight: '500',
  },
  rowLabelActive: {
    color: colors.cta,
    fontWeight: '700',
  },
});
