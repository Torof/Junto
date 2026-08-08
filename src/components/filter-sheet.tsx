import { useState, useMemo } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet, Modal, Alert, TextInput } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import DateTimePicker from '@react-native-community/datetimepicker';
import Slider from '@react-native-community/slider';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import * as Burnt from 'burnt';
import { Radar, Trash2, X, ChevronDown, ArrowUp, ArrowDown, Check, LocateFixed } from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import { useMapStore, type LevelTier, type SortBy, type SortDir } from '@/store/map-store';
import { CollapsibleSection } from './collapsible-section';
import { PlaceSearchBar } from './place-search-bar';
import { useSports } from '@/hooks/use-sports';
import { getSportIcon } from '@/constants/sport-icons';
import type { PlaceResult } from '@/services/geocode-service';
import { alertService } from '@/services/alert-service';
import type { AppColors } from '@/constants/colors';

const LEVEL_KEY: Record<LevelTier, string> = {
  Débutant: 'beginner',
  Intermédiaire: 'intermediate',
  Avancé: 'advanced',
  Expert: 'expert',
};

type TabKey = 'filters' | 'sort' | 'alerts';

interface FilterSheetProps {
  visible: boolean;
  onClose: () => void;
  hideAlertsTab?: boolean;
  // Show the 'Tri' tab — only meaningful for contexts that show a
  // list (drawer + mes-activites). Map markers don't have an order
  // so the map FAB's FilterSheet leaves this off.
  showSortTab?: boolean;
  // Filter state source. Defaults to useMapStore (the map's filter
  // state). mes-activites passes useMyActivitiesFilterStore so its
  // filter modal operates on independent state.
  useStore?: typeof useMapStore;
  // Show the Activités/Pros entity-type checkboxes. Defaults true
  // (map context). mes-activites passes false — that screen surfaces
  // catalog via a dedicated sub-tab, not the entity filter.
  showEntityFilter?: boolean;
  // Map context: pick a place from the filter → fly the map there (and usually
  // close the filter). Omitted where there's no map (e.g. mes-activites).
  onPlaceSelect?: (place: PlaceResult) => void;
  onResetLocation?: () => void;         // back to "my position"
  locationLabel?: string | null;        // chosen place name, or null = my position
}

export function FilterSheet({
  visible,
  onClose,
  hideAlertsTab = false,
  showSortTab = false,
  useStore = useMapStore,
  showEntityFilter = true,
  onPlaceSelect,
  onResetLocation,
  locationLabel,
}: FilterSheetProps) {
  const { t, i18n } = useTranslation();
  const colors = useColors();
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const {
    filters,
    toggleSportFilter,
    setDateMode,
    setDateRange,
    toggleLevelTier,
    setRadiusKm,
    setSortBy,
    setSortDir,
    toggleShowActivities,
    toggleShowProOfferings,
    resetFilters,
  } = useStore();
  const [showRangeFrom, setShowRangeFrom] = useState(false);
  const [showRangeTo, setShowRangeTo] = useState(false);
  const [tab, setTab] = useState<TabKey>('filters');
  const styles = useMemo(() => createStyles(colors), [colors]);

  const hasActiveFilters =
    filters.sportKeys.length > 0
    || filters.dateMode !== 'all'
    || filters.levelTiers.length > 0
    || filters.visibilities.length > 0
    || filters.radiusKm !== null;

  return (
    <Modal visible={visible} animationType="slide" transparent>
      <Pressable style={styles.backdrop} onPress={onClose}>
        <Pressable style={[styles.sheet, { paddingBottom: Math.max(insets.bottom + spacing.sm, spacing.md) }]} onPress={() => {}}>
          {/* Close button — top-left circle. Provides an explicit
              dismiss target alongside the tap-backdrop affordance. */}
          <Pressable style={styles.closeBtn} onPress={onClose} hitSlop={8}>
            <X size={14} color={colors.textPrimary} strokeWidth={2.4} />
          </Pressable>

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
            {showSortTab && (
              <Pressable
                style={[styles.tab, tab === 'sort' && styles.tabActive]}
                onPress={() => setTab('sort')}
              >
                <Text style={[styles.tabText, tab === 'sort' && styles.tabTextActive]}>
                  {t('map.tabs.sort')}
                </Text>
              </Pressable>
            )}
            {!hideAlertsTab && (
              <Pressable
                style={[styles.tab, tab === 'alerts' && styles.tabActive]}
                onPress={() => setTab('alerts')}
              >
                <Text style={[styles.tabText, tab === 'alerts' && styles.tabTextActive]}>
                  {t('map.tabs.alerts')}
                </Text>
              </Pressable>
            )}
            {hasActiveFilters && (
              <Pressable onPress={resetFilters} style={styles.resetSlot} hitSlop={6}>
                <Text style={styles.reset}>{t('map.resetFilters')}</Text>
              </Pressable>
            )}
          </View>

          {tab === 'filters' ? (
            <FiltersTab
              filters={filters}
              toggleSportFilter={toggleSportFilter}
              setDateMode={setDateMode}
              setDateRange={setDateRange}
              toggleLevelTier={toggleLevelTier}
              setRadiusKm={setRadiusKm}
              setSortBy={setSortBy}
              setSortDir={setSortDir}
              toggleShowActivities={toggleShowActivities}
              toggleShowProOfferings={toggleShowProOfferings}
              showEntityFilter={showEntityFilter}
              onPlaceSelect={onPlaceSelect}
              onResetLocation={onResetLocation}
              locationLabel={locationLabel}
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
              useStore={useStore}
            />
          ) : tab === 'sort' ? (
            <SortTab
              sortBy={filters.sortBy}
              sortDir={filters.sortDir}
              setSortBy={setSortBy}
              setSortDir={setSortDir}
              onClose={onClose}
              t={t}
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
  setDateRange: (f: string, t: string) => void;
  toggleLevelTier: (tier: LevelTier) => void;
  setRadiusKm: (km: number | null) => void;
  setSortBy: (s: SortBy) => void;
  setSortDir: (d: SortDir) => void;
  toggleShowActivities: () => void;
  toggleShowProOfferings: () => void;
  showEntityFilter: boolean;
  onPlaceSelect?: (place: PlaceResult) => void;
  onResetLocation?: () => void;
  locationLabel?: string | null;
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
  useStore: typeof useMapStore;
}

function FiltersTab({
  filters, toggleSportFilter, setDateMode, setDateRange,
  toggleLevelTier, setRadiusKm, setSortBy, setSortDir,
  toggleShowActivities, toggleShowProOfferings, showEntityFilter, onPlaceSelect, onResetLocation, locationLabel, resetFilters,
  showRangeFrom, setShowRangeFrom, showRangeTo, setShowRangeTo,
  onClose, t, lang, styles, colors,
}: FiltersTabProps) {
  const { data: sports } = useSports();
  const levelTierList = Object.keys(LEVEL_KEY) as LevelTier[];
  const [sportSearch, setSportSearch] = useState('');
  const visibleSports = useMemo(() => {
    const q = sportSearch.trim().toLowerCase();
    const all = sports ?? [];
    if (!q) return all;
    return all.filter((s) => t(`sports.${s.key}`, { defaultValue: s.key }).toLowerCase().includes(q));
  }, [sports, sportSearch, t]);

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

  if (filters.sortBy !== null) {
    const arrow = filters.sortDir === 'desc' ? ' ↓' : ' ↑';
    activePills.push({
      id: 'sort',
      label: `${t(`map.sortBy.${filters.sortBy}`)}${arrow}`,
      clear: () => { setSortBy(null); setSortDir('asc'); },
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

  const dateSummary = filters.dateMode === 'all' ? null
    : filters.dateMode === 'today' ? t('map.date.today')
    : filters.dateMode === 'week' ? t('map.date.week')
    : filters.dateMode === 'date' && filters.specificDate
      ? dayjs(filters.specificDate).locale(lang).format('D MMM')
    : filters.dateMode === 'range' && filters.rangeFrom && filters.rangeTo
      ? (dayjs(filters.rangeFrom).isSame(filters.rangeTo, 'day')
          ? dayjs(filters.rangeFrom).locale(lang).format('D MMM')
          : `${dayjs(filters.rangeFrom).locale(lang).format('D MMM')} → ${dayjs(filters.rangeTo).locale(lang).format('D MMM')}`)
      : null;

  return (
    <>
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
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingBottom: spacing.md }}
        keyboardShouldPersistTaps="handled"
      >
        {onPlaceSelect && (
          <CollapsibleSection
            title={t('map.locationLabel', { defaultValue: 'Localisation' })}
            summary={locationLabel ?? t('map.myPosition', { defaultValue: 'Ma position' })}
          >
            <PlaceSearchBar onSelect={onPlaceSelect} />
            {locationLabel && onResetLocation && (
              <Pressable style={styles.optRow} onPress={onResetLocation}>
                <LocateFixed size={16} color={colors.cta} strokeWidth={2.2} />
                <Text style={[styles.optLabel, { color: colors.cta }]}>{t('map.backToMyPosition', { defaultValue: 'Revenir à ma position' })}</Text>
              </Pressable>
            )}
          </CollapsibleSection>
        )}

        {/* Entity-type filter — controls what shows on the map AND in
            the drawer. Both on by default; user opts out per type.
            Hidden in mes-activites context (no offerings shown there
            via this filter; the Catalogue sub-tab handles it). */}
        {showEntityFilter && (
        <CollapsibleSection
          title={t('map.showLabel', { defaultValue: 'Afficher' })}
          summary={filters.showActivities && filters.showProOfferings ? null
            : filters.showActivities ? t('map.typeActivities', { defaultValue: 'Passionnés' })
            : filters.showProOfferings ? t('map.typePros', { defaultValue: 'Pros' })
            : t('map.showNone', { defaultValue: 'Rien' })}
        >
          <View style={styles.typeRow}>
            <Pressable
              style={[styles.typeChip, filters.showActivities && styles.typeChipActive]}
              onPress={toggleShowActivities}
              accessibilityRole="checkbox"
              accessibilityState={{ checked: filters.showActivities }}
            >
              <View style={[styles.typeCheckbox, filters.showActivities && styles.typeCheckboxOn]}>
                {filters.showActivities && <Text style={styles.typeCheckboxMark}>✓</Text>}
              </View>
              <Text style={[styles.typeChipText, filters.showActivities && styles.typeChipTextActive]}>
                {t('map.typeActivities', { defaultValue: 'Passionnés' })}
              </Text>
            </Pressable>
            <Pressable
              style={[styles.typeChip, filters.showProOfferings && styles.typeChipActive]}
              onPress={toggleShowProOfferings}
              accessibilityRole="checkbox"
              accessibilityState={{ checked: filters.showProOfferings }}
            >
              <View style={[styles.typeCheckbox, filters.showProOfferings && styles.typeCheckboxOn]}>
                {filters.showProOfferings && <Text style={styles.typeCheckboxMark}>✓</Text>}
              </View>
              <Text style={[styles.typeChipText, filters.showProOfferings && styles.typeChipTextActive]}>
                {t('map.typePros', { defaultValue: 'Pros' })}
              </Text>
            </Pressable>
          </View>
        </CollapsibleSection>
        )}

        <CollapsibleSection
          title={t('map.radiusLabel')}
          summary={filters.radiusKm !== null ? `${filters.radiusKm} km` : t('map.radiusOff')}
        >
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
        </CollapsibleSection>

        <CollapsibleSection title={t('map.dateLabel', { defaultValue: 'Période' })} summary={dateSummary}>
          <View style={styles.chipRow}>
            {(['all', 'today', 'week'] as const).map((mode) => (
              <Pressable
                key={mode}
                style={[styles.chip, filters.dateMode === mode && styles.chipActive]}
                onPress={() => setDateMode(mode)}
              >
                <Text style={[styles.chipText, filters.dateMode === mode && styles.chipTextActive]}>
                  {mode === 'all' ? t('map.date.all', { defaultValue: 'Toutes' })
                    : mode === 'today' ? t('map.date.today')
                    : t('map.date.week')}
                </Text>
              </Pressable>
            ))}
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
          </View>
        </CollapsibleSection>

        <CollapsibleSection title={t('map.sportLabel')} summary={sportActive ? sportLabel : null}>
          <TextInput
            style={styles.sportSearch}
            value={sportSearch}
            onChangeText={setSportSearch}
            placeholder={t('map.searchSport')}
            placeholderTextColor={colors.textSecondary}
            autoCorrect={false}
          />
          {visibleSports.map((s) => {
            const on = filters.sportKeys.includes(s.key);
            return (
              <Pressable key={s.key} style={styles.optRow} onPress={() => toggleSportFilter(s.key)}>
                <Text style={styles.optEmoji}>{getSportIcon(s.key)}</Text>
                <Text style={[styles.optLabel, on && styles.optLabelActive]} numberOfLines={1}>{t(`sports.${s.key}`, { defaultValue: s.key })}</Text>
                {on && <Check size={18} color={colors.cta} strokeWidth={2.4} />}
              </Pressable>
            );
          })}
        </CollapsibleSection>

        <CollapsibleSection title={t('map.levelLabel')} summary={levelActive ? levelLabel : null}>
          {levelTierList.map((tier) => {
            const on = filters.levelTiers.includes(tier);
            return (
              <Pressable key={tier} style={styles.optRow} onPress={() => toggleLevelTier(tier)}>
                <Text style={[styles.optLabel, on && styles.optLabelActive]} numberOfLines={1}>{t(`map.levelTier.${LEVEL_KEY[tier]}`)}</Text>
                {on && <Check size={18} color={colors.cta} strokeWidth={2.4} />}
              </Pressable>
            );
          })}
        </CollapsibleSection>

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


      <View style={styles.applyContainer}>
        <Pressable style={styles.applyButton} onPress={onClose}>
          <Text style={styles.applyText}>{t('map.apply')}</Text>
        </Pressable>
      </View>
    </>
  );
}

// ============================================================================
// Sort tab — choose the metric (date / distance / sport / remaining)
// and the direction (asc / desc).
// ============================================================================

interface SortTabProps {
  sortBy: SortBy;
  sortDir: SortDir;
  setSortBy: (s: SortBy) => void;
  setSortDir: (d: SortDir) => void;
  onClose: () => void;
  t: (k: string, opts?: Record<string, unknown>) => string;
  styles: ReturnType<typeof createStyles>;
}

const SORT_OPTIONS: Exclude<SortBy, null>[] = ['date', 'distance', 'sport', 'remaining'];

function SortTab({ sortBy, sortDir, setSortBy, setSortDir, onClose, t, styles }: SortTabProps) {
  // Each chip cycles inactive → asc → desc → inactive on successive
  // taps. When inactive across all chips, the list falls back to the
  // default sort (date asc) — see useFilteredActivities / mes-activites.
  const onPress = (opt: Exclude<SortBy, null>) => {
    if (sortBy !== opt) {
      setSortBy(opt);
      setSortDir('asc');
      return;
    }
    if (sortDir === 'asc') {
      setSortDir('desc');
      return;
    }
    // Was desc → reset to inactive.
    setSortBy(null);
    setSortDir('asc');
  };

  return (
    <>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingBottom: spacing.md }}
        keyboardShouldPersistTaps="handled"
      >
        <View style={styles.chipRow}>
          {SORT_OPTIONS.map((opt) => {
            const active = sortBy === opt;
            const Chevron = active && sortDir === 'desc' ? ArrowDown : ArrowUp;
            const chevronColor = active ? '#FFFFFF' : (styles.chipText.color as string);
            return (
              <Pressable
                key={opt}
                style={[styles.chip, active && styles.chipActive, styles.dirChip]}
                onPress={() => onPress(opt)}
              >
                <Text style={[styles.chipText, active && styles.chipTextActive]}>
                  {t(`map.sortBy.${opt}`)}
                </Text>
                {active && <Chevron size={14} color={chevronColor} strokeWidth={2.4} />}
              </Pressable>
            );
          })}
        </View>
      </ScrollView>

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
    padding: spacing.md, height: '96%',
  },
  handle: { width: 40, height: 4, borderRadius: 2, backgroundColor: colors.textSecondary, alignSelf: 'center', marginBottom: spacing.md, opacity: 0.4 },

  // Top-right close affordance — small circle with an X icon.
  closeBtn: {
    position: 'absolute',
    top: spacing.sm,
    right: spacing.sm,
    width: 28,
    height: 28,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: colors.borderStrong,
    backgroundColor: 'transparent',
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 10,
  },

  tabBar: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    marginBottom: spacing.md,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderMuted,
  },
  // Reset slot — same rank as the filters/alerts tabs, but text-only
  // (no underline). Sticks to the right edge of the tab bar via auto
  // left margin.
  resetSlot: {
    paddingVertical: spacing.sm,
    marginLeft: 'auto',
  },
  tab: {
    paddingVertical: spacing.sm,
    borderBottomWidth: 2,
    borderBottomColor: 'transparent',
  },
  tabActive: { borderBottomColor: colors.borderStrong },
  tabText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '500' },
  tabTextActive: { color: colors.textPrimary, fontWeight: '700' },

  reset: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700' },

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
  typeSection: { marginBottom: spacing.sm },
  typeRow: { flexDirection: 'row', gap: spacing.sm },
  typeChip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    paddingVertical: spacing.xs + 2,
    paddingHorizontal: spacing.sm + 2,
    borderRadius: radius.sm,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    flex: 1,
  },
  typeChipActive: { borderColor: colors.cta, borderWidth: 2 },
  typeChipText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600' },
  typeChipTextActive: { color: colors.textPrimary, fontWeight: '700' },
  typeCheckbox: {
    width: 18, height: 18, borderRadius: 3,
    borderWidth: 1.5, borderColor: colors.borderMuted,
    alignItems: 'center', justifyContent: 'center',
  },
  typeCheckboxOn: { backgroundColor: colors.cta, borderColor: colors.cta },
  typeCheckboxMark: { color: '#FFFFFF', fontSize: 12, fontWeight: '900' },
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs + 2, marginBottom: spacing.md },
  radiusHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'baseline', marginTop: spacing.sm, marginBottom: spacing.sm },
  radiusValue: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700' },
  sliderBounds: { flexDirection: 'row', justifyContent: 'space-between', marginTop: -4, marginBottom: spacing.md },
  sliderBoundText: { color: colors.textSecondary, fontSize: fontSizes.xs },
  optRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, paddingVertical: spacing.sm },
  optEmoji: { fontSize: 18, width: 24, textAlign: 'center' },
  optLabel: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.md },
  optLabelActive: { fontWeight: '700', color: colors.cta },
  sportSearch: {
    color: colors.textPrimary, fontSize: fontSizes.md,
    borderWidth: 1, borderColor: colors.borderMuted, borderRadius: radius.sm,
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm, marginBottom: spacing.sm,
  },
  placeSearchWrap: { marginBottom: spacing.sm, zIndex: 20 },
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

  dirChip: { flexDirection: 'row', alignItems: 'center', gap: 6 },
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
