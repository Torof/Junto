import { useState, useMemo } from 'react';
import { View, Text, Pressable, StyleSheet, TextInput, Modal } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { Search, X, Check } from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useSports } from '@/hooks/use-sports';
import { getSportIcon } from '@/constants/sport-icons';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { KeyboardAwareScrollView } from '@/components/keyboard-aware-scroll-view';

interface SportDropdownProps {
  selected: string | string[];
  onSelect: (key: string) => void;
  multiSelect?: boolean;
  label?: string;
}

export function SportDropdown({ selected, onSelect, multiSelect = false, label }: SportDropdownProps) {
  const { t, i18n } = useTranslation();
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const { data: sports } = useSports();

  const sortedSports = [...(sports ?? [])].sort((a, b) =>
    t(`sports.${a.key}`, { defaultValue: a.key }).localeCompare(t(`sports.${b.key}`, { defaultValue: b.key }), i18n.language)
  );

  const visibleSports = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return sortedSports;
    return sortedSports.filter((s) =>
      t(`sports.${s.key}`, { defaultValue: s.key }).toLowerCase().includes(q),
    );
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sortedSports, query, t]);

  const closeSheet = () => {
    setOpen(false);
    setQuery('');
  };

  const selectedArray = Array.isArray(selected) ? selected : selected ? [selected] : [];
  const selectedCount = selectedArray.length;

  const displayLabel = selectedCount === 0
    ? label ?? t('sportDropdown.select')
    : selectedCount === 1
      ? t(`sports.${selectedArray[0]}`, { defaultValue: selectedArray[0] })
      : `${selectedCount} ${t('sportDropdown.selected')}`;

  const handleSelect = (key: string) => {
    onSelect(key);
    if (!multiSelect) closeSheet();
  };

  return (
    <>
      <Pressable style={[styles.trigger, selectedCount > 0 && styles.triggerActive]} onPress={() => setOpen(true)}>
        <Text style={[styles.triggerText, selectedCount > 0 && styles.triggerTextActive]}>{displayLabel}</Text>
        <Text style={styles.arrow}>▼</Text>
      </Pressable>

      {/* Full-screen top-anchored search: field pinned at the top, results fill
          the band above the keyboard (KeyboardAwareScrollView spacer). The old
          bottom sheet hid the results behind the IME. Multi-select applies live;
          the close X is "done". */}
      <Modal visible={open} animationType="slide" onRequestClose={closeSheet}>
        <SafeAreaView style={styles.screen} edges={['top', 'bottom']}>
          <View style={styles.header}>
            <Text style={styles.title}>{label ?? t('sportDropdown.select')}</Text>
            <Pressable onPress={closeSheet} hitSlop={10} accessibilityLabel={t('common.close', { defaultValue: 'Fermer' })}>
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
            {visibleSports.map((sport) => {
              const isSelected = selectedArray.includes(sport.key);
              return (
                <Pressable
                  key={sport.id}
                  style={[styles.item, isSelected && styles.itemSelected]}
                  onPress={() => handleSelect(sport.key)}
                >
                  <Text style={styles.itemIcon}>{getSportIcon(sport.key)}</Text>
                  <Text style={[styles.itemText, isSelected && styles.itemTextSelected]}>
                    {t(`sports.${sport.key}`, sport.key)}
                  </Text>
                  {isSelected && <Check size={18} color={colors.cta} strokeWidth={2.6} />}
                </Pressable>
              );
            })}
          </KeyboardAwareScrollView>
        </SafeAreaView>
      </Modal>
    </>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  trigger: {
    flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
    backgroundColor: colors.surface, borderRadius: radius.md,
    paddingHorizontal: spacing.md, paddingVertical: spacing.md,
  },
  triggerActive: { borderWidth: 1, borderColor: colors.cta },
  triggerText: { color: colors.textSecondary, fontSize: fontSizes.sm },
  triggerTextActive: { color: colors.textPrimary, fontWeight: 'bold' },
  arrow: { color: colors.textSecondary, fontSize: fontSizes.xs },

  screen: { flex: 1, backgroundColor: colors.background },
  header: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: spacing.lg, paddingTop: spacing.md, paddingBottom: spacing.sm,
  },
  title: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold' },
  searchBar: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm,
    borderWidth: 1, borderColor: colors.borderMuted, borderRadius: radius.md,
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
    marginHorizontal: spacing.lg, marginBottom: spacing.sm,
  },
  searchInput: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.md, padding: 0 },
  list: { flex: 1 },
  listContent: { paddingHorizontal: spacing.lg, paddingBottom: spacing.md },
  item: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.md,
    paddingVertical: spacing.md, paddingHorizontal: spacing.md,
    borderRadius: radius.md, marginBottom: spacing.xs,
  },
  itemSelected: { backgroundColor: colors.cta + '20' },
  itemIcon: { fontSize: 20, width: 28 },
  itemText: { color: colors.textPrimary, fontSize: fontSizes.md, flex: 1 },
  itemTextSelected: { color: colors.cta, fontWeight: 'bold' },
});
