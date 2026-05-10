import { useState, useMemo } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet, Modal, Alert } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import DateTimePicker from '@react-native-community/datetimepicker';
import Slider from '@react-native-community/slider';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import * as Burnt from 'burnt';
import { Radar, Trash2, X, ChevronDown } from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import { useMapStore, type LevelTier } from '@/store/map-store';
import { SportPickerSheet } from './sport-picker-sheet';
import { LevelPickerSheet } from './level-picker-sheet';
import { alertService } from '@/services/alert-service';
import type { AppColors } from '@/constants/colors';

const LEVEL_KEY: Record<LevelTier, string> = {
  Débutant: 'beginner',
  Intermédiaire: 'intermediate',
  Avancé: 'advanced',
  Expert: 'expert',
};

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
    setDateRange,
    toggleLevelTier,
    setRadiusKm,
    resetFilters,
  } = useMapStore();
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
              setDateRange={setDateRange}
              toggleLevelTier={toggleLevelTier}
              setRadiusKm={setRadiusKm}
              resetFilters={resetFilters}
              showRangeFrom={showRangeFrom}
              setShowRangeFrom={setShowRangeFrom}
              showRangeTo={showRangeTo}
              setShowRangeTo={setShowRangeTo}
              onClose={onClose}
              t={t}
              lang={i18n.language}
              styles={styles}
              colors={colors}
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
  setDateRange: (f: string, t: string) => void;
  toggleLevelTier: (tier: LevelTier) => void;
  setRadiusKm: (km: number | null) => void;
  resetFilters: () => void;
  showRangeFrom: boolean;
  setShowRangeFrom: (v: boolean) => void;
  showRangeTo: boolean;
  setShowRangeTo: (v: boolean) => void;
  onClose: () => void;
  t: (k: string, opts?: Record<string, unknown>) => string;
  lang: string;
  styles: ReturnType<typeof createStyles>;
  colors: AppColors;
}

function FiltersTab({
  filters, toggleSportFilter, setDateMode, setDateRange,
  toggleLevelTier, setRadiusKm, resetFilters,
  showRangeFrom, setShowRangeFrom, showRangeTo, setShowRangeTo,
  onClose, t, lang, styles, colors,
}: FiltersTabProps) {
  const [showSport, setShowSport] = useState(false);
  const [showLevel, setShowLevel] = useState(false);

  const activePills: { id: string; label: string; clear: () => void }[] = [];

  filters.sportKeys.forEach((key) => {
    activePills.push({
      id: `sport-${key}`,
      label: t(`sports.${key}`, { defaultValue: key }),
      clear: () => toggleSportFilter(key),
    });
  });

  if (filters.dateMode !== 'all') {
    let dateLabel = '';
    if (filters.dateMode === 'today') dateLabel = t('map.date.today');
    else if (filters.dateMode === 'week') dateLabel = t('map.date.week');
    else if (filters.dateMode === 'date' && filters.specificDate) {
      dateLabel = dayjs(filters.specificDate).locale(lang).format('D MMM');
    } else if (filters.dateMode === 'range' && filters.rangeFrom && filters.rangeTo) {
      dateLabel = `${dayjs(filters.rangeFrom).locale(lang).format('D MMM')} → ${dayjs(filters.rangeTo).locale(lang).format('D MMM')}`;
    }
    if (dateLabel) {
      activePills.push({ id: 'date', label: dateLabel, clear: () => setDateMode('all') });
    }
  }

  filters.levelTiers.forEach((tier) => {
    activePills.push({ id: `level-${tier}`, label: tier, clear: () => toggleLevelTier(tier) });
  });

  if (filters.radiusKm !== null) {
    activePills.push({
      id: 'radius',
      label: `${filters.radiusKm} km`,
      clear: () => setRadiusKm(null),
    });
  }

  const sportActive = filters.sportKeys.length > 0;
  const sportLabel = !sportActive
    ? t('map.sportLabel')
    : filters.sportKeys.length === 1
      ? t(`sports.${filters.sportKeys[0]}`, { defaultValue: filters.sportKeys[0] ?? '' })
      : `${t('map.sportLabel')} · ${filters.sportKeys.length}`;

  const levelActive = filters.levelTiers.length > 0;
  const levelLabel = !levelActive
    ? t('map.levelLabel')
    : filters.levelTiers.length === 1
      ? t(`map.levelTier.${LEVEL_KEY[filters.levelTiers[0]!]}`)
      : `${t('map.levelLabel')} · ${filters.levelTiers.length}`;

  return (
    <>
      <View style={styles.header}>
        <Pressable onPress={() => { resetFilters(); }}>
          <Text style={styles.reset}>{t('map.resetFilters')}</Text>
        </Pressable>
      </View>

      {activePills.length > 0 && (
        <View style={styles.activePillsWrap}>
          {activePills.map((pill) => (
            <View key={pill.id} style={styles.activePill}>
              <Text style={styles.activePillLabel} numberOfLines={1}>{pill.label}</Text>
              <Pressable onPress={pill.clear} hitSlop={6} style={styles.activePillClear}>
                <X size={12} color={colors.textPrimary} strokeWidth={2.4} />
              </Pressable>
            </View>
          ))}
        </View>
      )}

      <ScrollView
        style={{ flexGrow: 0 }}
        contentContainerStyle={{ paddingBottom: spacing.md }}
        keyboardShouldPersistTaps="handled"
      >
        {/* Radius — first selection element */}
        <View style={styles.radiusHeader}>
          <Text style={styles.sectionTitle}>{t('map.radiusLabel')}</Text>
          <Text style={styles.radiusValue}>
            {filters.radiusKm !== null ? `${filters.radiusKm} km` : t('map.radiusOff')}
          </Text>
        </View>
        <Slider
          minimumValue={0}
          maximumValue={200}
          step={5}
          value={filters.radiusKm ?? 0}
          onValueChange={(v) => setRadiusKm(v === 0 ? null : v)}
          minimumTrackTintColor={colors.cta}
          maximumTrackTintColor={colors.borderMuted}
          thumbTintColor={colors.cta}
        />
        <View style={styles.sliderBounds}>
          <Text style={styles.sliderBoundText}>{t('map.radiusOff')}</Text>
          <Text style={styles.sliderBoundText}>200 km</Text>
        </View>

        {/* Période + Sport + Niveau on one line. Each opens its own
            picker. The period chip uses a range picker that also covers
            single-day selection (pick same day twice). */}
        <View style={styles.chipRow}>
          <Pressable
            style={[styles.chip, filters.dateMode === 'range' && styles.chipActive]}
            onPress={() => setShowRangeFrom(true)}
          >
            <Text style={[styles.chipText, filters.dateMode === 'range' && styles.chipTextActive]}>
              {filters.dateMode === 'range' && filters.rangeFrom && filters.rangeTo
                ? (dayjs(filters.rangeFrom).isSame(filters.rangeTo, 'day')
                    ? dayjs(filters.rangeFrom).locale(lang).format('D MMM')
                    : `${dayjs(filters.rangeFrom).locale(lang).format('D MMM')} → ${dayjs(filters.rangeTo).locale(lang).format('D MMM')}`)
                : t('map.date.pickRange')}
            </Text>
            <ChevronDown size={12} color={filters.dateMode === 'range' ? '#FFFFFF' : colors.textSecondary} strokeWidth={2.4} />
          </Pressable>
          <Pressable
            style={[styles.chip, sportActive && styles.chipActive]}
            onPress={() => setShowSport(true)}
          >
            <Text style={[styles.chipText, sportActive && styles.chipTextActive]} numberOfLines={1}>
              {sportLabel}
            </Text>
            <ChevronDown size={12} color={sportActive ? '#FFFFFF' : colors.textSecondary} strokeWidth={2.4} />
          </Pressable>
          <Pressable
            style={[styles.chip, levelActive && styles.chipActive]}
            onPress={() => setShowLevel(true)}
          >
            <Text style={[styles.chipText, levelActive && styles.chipTextActive]} numberOfLines={1}>
              {levelLabel}
            </Text>
            <ChevronDown size={12} color={levelActive ? '#FFFFFF' : colors.textSecondary} strokeWidth={2.4} />
          </Pressable>
        </View>

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

      </ScrollView>

      <SportPickerSheet visible={showSport} onClose={() => setShowSport(false)} />
      <LevelPickerSheet visible={showLevel} onClose={() => setShowLevel(false)} />

      <View style={styles.applyContainer}>
        <Pressable style={styles.applyButton} onPress={onClose}>
          <Text style={styles.applyText}>{t('map.apply')}</Text>
        </Pressable>
      </View>
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
            <View style={styles.alertIcon}>
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
    padding: spacing.md, paddingBottom: spacing.xl + 16, maxHeight: '85%',
  },
  handle: { width: 40, height: 4, borderRadius: 2, backgroundColor: colors.textSecondary, alignSelf: 'center', marginBottom: spacing.md, opacity: 0.4 },

  tabBar: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    marginBottom: spacing.md,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderMuted,
  },
  tab: {
    paddingVertical: spacing.sm,
    borderBottomWidth: 2,
    borderBottomColor: 'transparent',
  },
  tabActive: { borderBottomColor: colors.borderStrong },
  tabText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '500' },
  tabTextActive: { color: colors.textPrimary, fontWeight: '700' },

  header: { flexDirection: 'row', justifyContent: 'flex-end', marginBottom: spacing.sm },
  reset: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '600' },

  // Active filters — wrap-row of pills at the top of the filters tab
  activePillsWrap: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.xs + 2,
    paddingBottom: spacing.sm,
    marginBottom: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderMuted,
  },
  activePill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    backgroundColor: colors.background,
    borderWidth: 1,
    borderColor: colors.borderStrong,
    borderRadius: radius.sm,
    paddingLeft: spacing.sm + 2,
    paddingRight: spacing.xs + 2,
    paddingVertical: spacing.xs + 1,
  },
  activePillLabel: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '600',
  },
  activePillClear: {
    width: 16,
    height: 16,
    alignItems: 'center',
    justifyContent: 'center',
  },

  sectionTitle: { color: colors.textSecondary, fontSize: fontSizes.xs, textTransform: 'uppercase', letterSpacing: 1, marginBottom: spacing.sm, marginTop: spacing.sm },
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs + 2, marginBottom: spacing.md },
  radiusHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'baseline', marginTop: spacing.sm, marginBottom: spacing.sm },
  radiusValue: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700' },
  sliderBounds: { flexDirection: 'row', justifyContent: 'space-between', marginTop: -4, marginBottom: spacing.md },
  sliderBoundText: { color: colors.textSecondary, fontSize: fontSizes.xs },
  chip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.sm,
    paddingHorizontal: spacing.sm + 2,
    paddingVertical: spacing.xs + 2,
    backgroundColor: 'transparent',
  },
  chipActive: { backgroundColor: colors.cta, borderColor: colors.cta },
  chipText: { color: colors.textSecondary, fontSize: fontSizes.sm },
  chipTextActive: { color: '#FFFFFF', fontWeight: '700' },

  applyContainer: {
    marginTop: spacing.md,
    paddingTop: spacing.md,
    borderTopWidth: 1,
    borderTopColor: colors.borderMuted,
  },
  applyButton: { backgroundColor: colors.cta, borderRadius: radius.sm, paddingVertical: spacing.sm + 2, alignItems: 'center' },
  applyText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '700' },

  emptyText: {
    color: colors.textSecondary, fontSize: fontSizes.sm, fontStyle: 'italic',
    textAlign: 'center', paddingVertical: spacing.lg,
  },

  alertRow: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm,
    paddingVertical: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderMuted,
  },
  alertIcon: { width: 24, alignItems: 'center', justifyContent: 'center' },
  alertSport: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },
  alertMeta: { color: colors.textMuted, fontSize: fontSizes.xs, marginTop: 2 },
  alertDeleteBtn: {
    width: 32, height: 32, alignItems: 'center', justifyContent: 'center',
  },

  newAlertBtn: {
    marginTop: spacing.md,
    paddingVertical: spacing.sm,
    borderRadius: radius.sm,
    borderWidth: 1,
    borderColor: colors.cta,
    alignItems: 'center',
    backgroundColor: 'transparent',
  },
  newAlertText: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700' },
});
