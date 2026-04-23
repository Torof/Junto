import { useState, useMemo } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet, Modal, Alert } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import DateTimePicker from '@react-native-community/datetimepicker';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import * as Burnt from 'burnt';
import { Radar, Trash2 } from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import { useMapStore, type LevelTier, type VisibilityFilter } from '@/store/map-store';
import { SportDropdown } from './sport-dropdown';
import { alertService } from '@/services/alert-service';
import type { AppColors } from '@/constants/colors';

const QUICK_OPTIONS = ['all', 'today'] as const;
const LEVEL_TIERS: { tier: LevelTier; key: string }[] = [
  { tier: 'Débutant', key: 'beginner' },
  { tier: 'Intermédiaire', key: 'intermediate' },
  { tier: 'Avancé', key: 'advanced' },
  { tier: 'Expert', key: 'expert' },
];
const VISIBILITIES: { key: VisibilityFilter; i18n: string }[] = [
  { key: 'public', i18n: 'public' },
  { key: 'approval', i18n: 'approval' },
];

type TabKey = 'filters' | 'alerts';

interface FilterSheetProps {
  visible: boolean;
  onClose: () => void;
}

export function FilterSheet({ visible, onClose }: FilterSheetProps) {
  const { t, i18n } = useTranslation();
  const colors = useColors();
  const router = useRouter();
  const {
    filters,
    toggleSportFilter,
    setDateMode,
    setSpecificDate,
    setDateRange,
    toggleLevelTier,
    toggleVisibility,
    resetFilters,
  } = useMapStore();
  const [showDatePicker, setShowDatePicker] = useState(false);
  const [showRangeFrom, setShowRangeFrom] = useState(false);
  const [showRangeTo, setShowRangeTo] = useState(false);
  const [tab, setTab] = useState<TabKey>('filters');
  const styles = useMemo(() => createStyles(colors), [colors]);

  return (
    <Modal visible={visible} animationType="slide" transparent>
      <Pressable style={styles.backdrop} onPress={onClose}>
        <Pressable style={styles.sheet} onPress={() => {}}>
          <View style={styles.handle} />

          <View style={styles.tabBar}>
            <Pressable
              style={[styles.tab, tab === 'filters' && styles.tabActive]}
              onPress={() => setTab('filters')}
            >
              <Text style={[styles.tabText, tab === 'filters' && styles.tabTextActive]}>
                {t('map.tabs.filters')}
              </Text>
            </Pressable>
            <Pressable
              style={[styles.tab, tab === 'alerts' && styles.tabActive]}
              onPress={() => setTab('alerts')}
            >
              <Text style={[styles.tabText, tab === 'alerts' && styles.tabTextActive]}>
                {t('map.tabs.alerts')}
              </Text>
            </Pressable>
          </View>

          {tab === 'filters' ? (
            <FiltersTab
              filters={filters}
              toggleSportFilter={toggleSportFilter}
              setDateMode={setDateMode}
              setSpecificDate={setSpecificDate}
              setDateRange={setDateRange}
              toggleLevelTier={toggleLevelTier}
              toggleVisibility={toggleVisibility}
              resetFilters={resetFilters}
              showDatePicker={showDatePicker}
              setShowDatePicker={setShowDatePicker}
              showRangeFrom={showRangeFrom}
              setShowRangeFrom={setShowRangeFrom}
              showRangeTo={showRangeTo}
              setShowRangeTo={setShowRangeTo}
              onClose={onClose}
              t={t}
              lang={i18n.language}
              styles={styles}
            />
          ) : (
            <AlertsTab
              onNewAlert={() => { onClose(); router.push('/(auth)/create-alert'); }}
              t={t}
              styles={styles}
              colors={colors}
            />
          )}
        </Pressable>
      </Pressable>
    </Modal>
  );
}

// ============================================================================
// Filters tab
// ============================================================================

interface FiltersTabProps {
  filters: ReturnType<typeof useMapStore.getState>['filters'];
  toggleSportFilter: (k: string) => void;
  setDateMode: (m: 'all' | 'today' | 'week' | 'date' | 'range') => void;
  setSpecificDate: (d: string) => void;
  setDateRange: (f: string, t: string) => void;
  toggleLevelTier: (tier: LevelTier) => void;
  toggleVisibility: (v: VisibilityFilter) => void;
  resetFilters: () => void;
  showDatePicker: boolean;
  setShowDatePicker: (v: boolean) => void;
  showRangeFrom: boolean;
  setShowRangeFrom: (v: boolean) => void;
  showRangeTo: boolean;
  setShowRangeTo: (v: boolean) => void;
  onClose: () => void;
  t: (k: string, opts?: Record<string, unknown>) => string;
  lang: string;
  styles: ReturnType<typeof createStyles>;
}

function FiltersTab({
  filters, toggleSportFilter, setDateMode, setSpecificDate, setDateRange,
  toggleLevelTier, toggleVisibility, resetFilters,
  showDatePicker, setShowDatePicker, showRangeFrom, setShowRangeFrom, showRangeTo, setShowRangeTo,
  onClose, t, lang, styles,
}: FiltersTabProps) {
  return (
    <>
      <View style={styles.header}>
        <Pressable onPress={() => { resetFilters(); }}>
          <Text style={styles.reset}>{t('map.resetFilters')}</Text>
        </Pressable>
      </View>

      <ScrollView
        style={{ flexGrow: 0 }}
        contentContainerStyle={{ paddingBottom: spacing.md }}
        keyboardShouldPersistTaps="handled"
      >
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
                ? dayjs(filters.specificDate).locale(lang).format('D MMM')
                : t('map.date.pickDate')}
            </Text>
          </Pressable>
          <Pressable
            style={[styles.chip, filters.dateMode === 'range' && styles.chipActive]}
            onPress={() => setShowRangeFrom(true)}
          >
            <Text style={[styles.chipText, filters.dateMode === 'range' && styles.chipTextActive]}>
              {filters.dateMode === 'range' && filters.rangeFrom && filters.rangeTo
                ? `${dayjs(filters.rangeFrom).locale(lang).format('D MMM')} → ${dayjs(filters.rangeTo).locale(lang).format('D MMM')}`
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

        <Text style={styles.sectionTitle}>{t('map.levelLabel')}</Text>
        <View style={styles.chipRow}>
          {LEVEL_TIERS.map(({ tier, key }) => {
            const active = filters.levelTiers.includes(tier);
            return (
              <Pressable
                key={tier}
                style={[styles.chip, active && styles.chipActive]}
                onPress={() => toggleLevelTier(tier)}
              >
                <Text style={[styles.chipText, active && styles.chipTextActive]}>
                  {t(`map.levelTier.${key}`)}
                </Text>
              </Pressable>
            );
          })}
        </View>

        <Text style={styles.sectionTitle}>{t('map.visibilityLabel')}</Text>
        <View style={styles.chipRow}>
          {VISIBILITIES.map(({ key, i18n: i18nKey }) => {
            const active = filters.visibilities.includes(key);
            return (
              <Pressable
                key={key}
                style={[styles.chip, active && styles.chipActive]}
                onPress={() => toggleVisibility(key)}
              >
                <Text style={[styles.chipText, active && styles.chipTextActive]}>
                  {t(`map.visibility.${i18nKey}`)}
                </Text>
              </Pressable>
            );
          })}
        </View>
      </ScrollView>

      <Pressable style={styles.applyButton} onPress={onClose}>
        <Text style={styles.applyText}>{t('map.apply')}</Text>
      </Pressable>
    </>
  );
}

// ============================================================================
// Alerts tab
// ============================================================================

interface AlertsTabProps {
  onNewAlert: () => void;
  t: (k: string, opts?: Record<string, unknown>) => string;
  styles: ReturnType<typeof createStyles>;
  colors: AppColors;
}

function AlertsTab({ onNewAlert, t, styles, colors }: AlertsTabProps) {
  const queryClient = useQueryClient();
  const { data: alerts, isLoading } = useQuery({
    queryKey: ['activity-alerts'],
    queryFn: () => alertService.getAll(),
  });

  const handleDelete = (alertId: string) => {
    Alert.alert(
      t('map.alerts.deleteConfirm'),
      t('map.alerts.deleteConfirmText'),
      [
        { text: t('map.alerts.deleteConfirmCancel'), style: 'cancel' },
        {
          text: t('map.alerts.deleteConfirmOk'),
          style: 'destructive',
          onPress: async () => {
            try {
              await alertService.delete(alertId);
              await queryClient.invalidateQueries({ queryKey: ['activity-alerts'] });
              Burnt.toast({ title: t('map.alerts.deleted'), preset: 'done' });
            } catch {
              Burnt.toast({ title: t('auth.unknownError') });
            }
          },
        },
      ],
    );
  };

  return (
    <ScrollView
      style={{ flexGrow: 0 }}
      contentContainerStyle={{ paddingBottom: spacing.md }}
      keyboardShouldPersistTaps="handled"
    >
      {isLoading ? null : !alerts || alerts.length === 0 ? (
        <Text style={styles.emptyText}>{t('map.alerts.none')}</Text>
      ) : (
        alerts.map((a) => (
          <View key={a.id} style={styles.alertRow}>
            <View style={styles.alertIconBox}>
              <Radar size={18} color={colors.cta} strokeWidth={2.2} />
            </View>
            <View style={{ flex: 1, minWidth: 0 }}>
              <Text style={styles.alertSport} numberOfLines={1}>
                {a.sport_key ? t(`sports.${a.sport_key}`, { defaultValue: a.sport_key }) : t('map.alerts.allSports')}
              </Text>
              <Text style={styles.alertMeta}>
                {t('map.alerts.radius', { km: a.radius_km })}
                {a.levels && a.levels.length > 0 ? ` · ${a.levels.join(', ')}` : ''}
              </Text>
            </View>
            <Pressable onPress={() => handleDelete(a.id)} hitSlop={8} style={styles.alertDeleteBtn}>
              <Trash2 size={18} color={colors.error} strokeWidth={2} />
            </Pressable>
          </View>
        ))
      )}

      <Pressable style={styles.newAlertBtn} onPress={onNewAlert}>
        <Text style={styles.newAlertText}>{t('map.alerts.new')}</Text>
      </Pressable>
    </ScrollView>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: colors.overlay, justifyContent: 'flex-end' },
  sheet: {
    backgroundColor: colors.background, borderTopLeftRadius: radius.lg, borderTopRightRadius: radius.lg,
    padding: spacing.lg, paddingBottom: spacing.xl + 16, maxHeight: '85%',
  },
  handle: { width: 40, height: 4, borderRadius: 2, backgroundColor: colors.textSecondary, alignSelf: 'center', marginBottom: spacing.md, opacity: 0.4 },

  tabBar: {
    flexDirection: 'row',
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    padding: 4,
    marginBottom: spacing.md,
    gap: 4,
  },
  tab: {
    flex: 1, alignItems: 'center', justifyContent: 'center',
    paddingVertical: spacing.sm + 2, borderRadius: radius.sm,
  },
  tabActive: { backgroundColor: colors.surfaceAlt },
  tabText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600' },
  tabTextActive: { color: colors.textPrimary },

  header: { flexDirection: 'row', justifyContent: 'flex-end', marginBottom: spacing.sm },
  reset: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '600' },
  sectionTitle: { color: colors.textSecondary, fontSize: fontSizes.xs, textTransform: 'uppercase', letterSpacing: 1, marginBottom: spacing.sm, marginTop: spacing.sm },
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm, marginBottom: spacing.md },
  chip: { backgroundColor: colors.surface, borderRadius: radius.full, paddingHorizontal: spacing.md, paddingVertical: spacing.sm },
  chipActive: { backgroundColor: colors.cta },
  chipText: { color: colors.textSecondary, fontSize: fontSizes.sm },
  chipTextActive: { color: colors.textPrimary, fontWeight: 'bold' },

  applyButton: { backgroundColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.md },
  applyText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },

  emptyText: {
    color: colors.textSecondary, fontSize: fontSizes.sm, fontStyle: 'italic',
    textAlign: 'center', paddingVertical: spacing.lg,
  },

  alertRow: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm,
    backgroundColor: colors.surface, borderRadius: radius.md,
    borderWidth: 1, borderColor: colors.line,
    paddingHorizontal: spacing.sm + 2, paddingVertical: spacing.sm,
    marginBottom: spacing.xs,
  },
  alertIconBox: {
    width: 36, height: 36, borderRadius: radius.sm,
    backgroundColor: colors.cta + '26',
    alignItems: 'center', justifyContent: 'center',
  },
  alertSport: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },
  alertMeta: { color: colors.textMuted, fontSize: fontSizes.xs, marginTop: 2 },
  alertDeleteBtn: {
    width: 36, height: 36, alignItems: 'center', justifyContent: 'center',
  },

  newAlertBtn: {
    marginTop: spacing.md,
    paddingVertical: spacing.sm + 2,
    borderRadius: radius.md,
    borderWidth: 1, borderStyle: 'dashed', borderColor: colors.cta,
    alignItems: 'center',
  },
  newAlertText: { color: colors.cta, fontSize: fontSizes.sm + 1, fontWeight: '700' },
});
