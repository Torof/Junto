import { useState, useMemo } from 'react';
import { View, Text, Pressable, StyleSheet, Modal } from 'react-native';
import { useTranslation } from 'react-i18next';
import DateTimePicker from '@react-native-community/datetimepicker';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import { useMapStore } from '@/store/map-store';
import { SportDropdown } from './sport-dropdown';
import type { AppColors } from '@/constants/colors';

const QUICK_OPTIONS = ['all', 'today'] as const;

interface FilterSheetProps {
  visible: boolean;
  onClose: () => void;
}

export function FilterSheet({ visible, onClose }: FilterSheetProps) {
  const { t, i18n } = useTranslation();
  const colors = useColors();
  const { filters, toggleSportFilter, setDateMode, setSpecificDate, setDateRange, resetFilters } = useMapStore();
  const [showDatePicker, setShowDatePicker] = useState(false);
  const [showRangeFrom, setShowRangeFrom] = useState(false);
  const [showRangeTo, setShowRangeTo] = useState(false);
  const styles = useMemo(() => createStyles(colors), [colors]);

  return (
    <Modal visible={visible} animationType="slide" transparent>
      <Pressable style={styles.backdrop} onPress={onClose}>
        <Pressable style={styles.sheet} onPress={() => {}}>
          <View style={styles.handle} />

          <View style={styles.header}>
            <Text style={styles.title}>{t('map.filters')}</Text>
            <Pressable onPress={() => { resetFilters(); onClose(); }}>
              <Text style={styles.reset}>{t('map.resetFilters')}</Text>
            </Pressable>
          </View>

          <Text style={styles.sectionTitle}>{t('map.dateLabel')}</Text>
          <View style={styles.chipRow}>
            {QUICK_OPTIONS.map((option) => (
              <Pressable
                key={option}
                style={[styles.chip, filters.dateMode === option && styles.chipActive]}
                onPress={() => setDateMode(option)}
              >
                <Text style={[styles.chipText, filters.dateMode === option && styles.chipTextActive]}>
                  {t(`map.date.${option}`)}
                </Text>
              </Pressable>
            ))}
            <Pressable
              style={[styles.chip, filters.dateMode === 'date' && styles.chipActive]}
              onPress={() => setShowDatePicker(true)}
            >
              <Text style={[styles.chipText, filters.dateMode === 'date' && styles.chipTextActive]}>
                {filters.dateMode === 'date' && filters.specificDate
                  ? dayjs(filters.specificDate).locale(i18n.language).format('D MMM')
                  : t('map.date.pickDate')}
              </Text>
            </Pressable>
            <Pressable
              style={[styles.chip, filters.dateMode === 'range' && styles.chipActive]}
              onPress={() => setShowRangeFrom(true)}
            >
              <Text style={[styles.chipText, filters.dateMode === 'range' && styles.chipTextActive]}>
                {filters.dateMode === 'range' && filters.rangeFrom && filters.rangeTo
                  ? `${dayjs(filters.rangeFrom).locale(i18n.language).format('D MMM')} → ${dayjs(filters.rangeTo).locale(i18n.language).format('D MMM')}`
                  : t('map.date.pickRange')}
              </Text>
            </Pressable>
          </View>

          {showDatePicker && (
            <DateTimePicker
              value={filters.specificDate ? new Date(filters.specificDate) : new Date()}
              mode="date"
              minimumDate={new Date()}
              onChange={(_e, date) => {
                setShowDatePicker(false);
                if (date) setSpecificDate(date.toISOString());
              }}
            />
          )}

          {showRangeFrom && (
            <DateTimePicker
              value={filters.rangeFrom ? new Date(filters.rangeFrom) : new Date()}
              mode="date"
              minimumDate={new Date()}
              onChange={(_e, date) => {
                setShowRangeFrom(false);
                if (date) {
                  setDateRange(date.toISOString(), filters.rangeTo ?? dayjs(date).add(7, 'day').toISOString());
                  setShowRangeTo(true);
                }
              }}
            />
          )}

          {showRangeTo && (
            <DateTimePicker
              value={filters.rangeTo ? new Date(filters.rangeTo) : dayjs().add(7, 'day').toDate()}
              mode="date"
              minimumDate={filters.rangeFrom ? new Date(filters.rangeFrom) : new Date()}
              onChange={(_e, date) => {
                setShowRangeTo(false);
                if (date) setDateRange(filters.rangeFrom ?? new Date().toISOString(), date.toISOString());
              }}
            />
          )}

          <Text style={styles.sectionTitle}>{t('map.sportLabel')}</Text>
          <SportDropdown
            selected={filters.sportKeys}
            onSelect={toggleSportFilter}
            multiSelect
            label={t('map.sportLabel')}
          />

          <Pressable style={styles.applyButton} onPress={onClose}>
            <Text style={styles.applyText}>{t('map.apply')}</Text>
          </Pressable>
        </Pressable>
      </Pressable>
    </Modal>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: colors.overlay, justifyContent: 'flex-end' },
  sheet: {
    backgroundColor: colors.background, borderTopLeftRadius: radius.lg, borderTopRightRadius: radius.lg,
    padding: spacing.lg, paddingBottom: spacing.xl + 16, maxHeight: '70%',
  },
  handle: { width: 40, height: 4, borderRadius: 2, backgroundColor: colors.textSecondary, alignSelf: 'center', marginBottom: spacing.lg, opacity: 0.4 },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: spacing.lg },
  title: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold' },
  reset: { color: colors.cta, fontSize: fontSizes.sm },
  sectionTitle: { color: colors.textSecondary, fontSize: fontSizes.xs, textTransform: 'uppercase', marginBottom: spacing.sm, marginTop: spacing.sm },
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm, marginBottom: spacing.md },
  chip: { backgroundColor: colors.surface, borderRadius: radius.full, paddingHorizontal: spacing.md, paddingVertical: spacing.sm },
  chipActive: { backgroundColor: colors.cta },
  chipText: { color: colors.textSecondary, fontSize: fontSizes.sm },
  chipTextActive: { color: colors.textPrimary, fontWeight: 'bold' },
  applyButton: { backgroundColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.lg },
  applyText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
});
