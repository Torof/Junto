import { useState, useMemo } from 'react';
import { View, Text, Pressable, ScrollView, Modal, StyleSheet, TextInput } from 'react-native';
import { useQuery } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { Search } from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { supabase } from '@/services/supabase';
import { getSportIcon } from '@/constants/sport-icons';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';

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

  const { data: sports } = useQuery({
    queryKey: ['sports'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('sports')
        .select('id, key, display_order')
        .order('display_order');
      if (error) throw error;
      return data;
    },
  });

  // Sort sports alphabetically by translated name
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

      <Modal visible={open} animationType="slide" transparent>
        <Pressable style={styles.backdrop} onPress={closeSheet}>
          <Pressable style={styles.sheet} onPress={() => {}}>
            <View style={styles.handle} />
            <Text style={styles.title}>{label ?? t('sportDropdown.select')}</Text>

            <View style={styles.searchBar}>
              <Search size={16} color={colors.textSecondary} strokeWidth={2.2} />
              <TextInput
                style={styles.searchInput}
                value={query}
                onChangeText={setQuery}
                placeholder={t('map.searchSport', { defaultValue: 'Rechercher un sport' })}
                placeholderTextColor={colors.textSecondary}
                autoCorrect={false}
                autoCapitalize="none"
              />
            </View>

            <ScrollView style={styles.list} showsVerticalScrollIndicator={false} keyboardShouldPersistTaps="handled">
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
                    {isSelected && <Text style={styles.check}>✓</Text>}
                  </Pressable>
                );
              })}
            </ScrollView>

            {multiSelect && (
              <Pressable style={styles.doneButton} onPress={closeSheet}>
                <Text style={styles.doneText}>{t('map.apply')}</Text>
              </Pressable>
            )}
          </Pressable>
        </Pressable>
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
  backdrop: { flex: 1, backgroundColor: colors.overlay, justifyContent: 'flex-end' },
  sheet: {
    backgroundColor: colors.background, borderTopLeftRadius: radius.lg, borderTopRightRadius: radius.lg,
    padding: spacing.lg, paddingBottom: spacing.xl + 16, maxHeight: '70%',
  },
  handle: { width: 40, height: 4, borderRadius: 2, backgroundColor: colors.textSecondary, alignSelf: 'center', marginBottom: spacing.lg, opacity: 0.4 },
  title: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold', marginBottom: spacing.md },
  searchBar: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm,
    borderWidth: 1, borderColor: colors.borderMuted, borderRadius: radius.sm,
    paddingHorizontal: spacing.sm + 2, paddingVertical: spacing.xs + 2, marginBottom: spacing.sm,
  },
  searchInput: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.md, padding: 0 },
  list: { maxHeight: 400 },
  item: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.md,
    paddingVertical: spacing.md, paddingHorizontal: spacing.md,
    borderRadius: radius.md, marginBottom: spacing.xs,
  },
  itemSelected: { backgroundColor: colors.cta + '20' },
  itemIcon: { fontSize: 20, width: 28 },
  itemText: { color: colors.textPrimary, fontSize: fontSizes.md, flex: 1 },
  itemTextSelected: { color: colors.cta, fontWeight: 'bold' },
  check: { color: colors.cta, fontSize: 18, fontWeight: 'bold' },
  doneButton: {
    backgroundColor: colors.cta, borderRadius: radius.md,
    paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.md,
  },
  doneText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
});
