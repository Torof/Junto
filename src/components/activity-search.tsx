import { useState, useMemo } from 'react';
import { View, Text, FlatList, Pressable, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import DateTimePicker from '@react-native-community/datetimepicker';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { type NearbyActivity } from '@/services/activity-service';
import { ActivityCard } from './activity-card';
import { SportDropdown } from './sport-dropdown';

const DISTANCE_OPTIONS = [5, 10, 25, 50, 100] as const;

interface ActivitySearchProps {
  activities: NearbyActivity[];
  userLocation: [number, number];
  routePrefix: '/(visitor)' | '/(auth)';
}

function getDistanceKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

export function ActivitySearch({ activities, userLocation, routePrefix }: ActivitySearchProps) {
  const { t, i18n } = useTranslation();
  const router = useRouter();

  const [sportFilters, setSportFilters] = useState<string[]>([]);
  const [maxDistance, setMaxDistance] = useState<number>(25);
  const [dateMode, setDateMode] = useState<'all' | 'today' | 'week' | 'date' | 'range'>('all');
  const [specificDate, setSpecificDate] = useState<Date | null>(null);
  const [rangeFrom, setRangeFrom] = useState<Date | null>(null);
  const [rangeTo, setRangeTo] = useState<Date | null>(null);
  const [showDatePicker, setShowDatePicker] = useState(false);
  const [showRangeFrom, setShowRangeFrom] = useState(false);
  const [showRangeTo, setShowRangeTo] = useState(false);

  const filtered = useMemo(() => {
    return activities
      .map((a) => ({
        ...a,
        distance: getDistanceKm(userLocation[1], userLocation[0], a.lat, a.lng),
      }))
      .filter((a) => {
        // Distance
        if (a.distance > maxDistance) return false;

        // Sport
        if (sportFilters.length > 0 && !sportFilters.includes(a.sport_key)) return false;

        // Date
        const d = dayjs(a.starts_at);
        if (dateMode === 'today' && !d.isSame(dayjs(), 'day')) return false;
        if (dateMode === 'week' && d.isAfter(dayjs().add(7, 'day'))) return false;
        if (dateMode === 'date' && specificDate && !d.isSame(dayjs(specificDate), 'day')) return false;
        if (dateMode === 'range' && rangeFrom && rangeTo) {
          if (d.isBefore(dayjs(rangeFrom).startOf('day')) || d.isAfter(dayjs(rangeTo).endOf('day'))) return false;
        }

        return true;
      })
      .sort((a, b) => a.distance - b.distance);
  }, [activities, userLocation, sportFilters, maxDistance, dateMode, specificDate, rangeFrom, rangeTo]);

  return (
    <View style={styles.container}>
      {/* Filters */}
      <View style={styles.filters}>
        {/* Distance */}
        <Text style={styles.filterLabel}>{t('search.distance')}</Text>
        <View style={styles.chipRow}>
          {DISTANCE_OPTIONS.map((d) => (
            <Pressable
              key={d}
              style={[styles.chip, maxDistance === d && styles.chipActive]}
              onPress={() => setMaxDistance(d)}
            >
              <Text style={[styles.chipText, maxDistance === d && styles.chipTextActive]}>{d} km</Text>
            </Pressable>
          ))}
        </View>

        {/* Date */}
        <Text style={styles.filterLabel}>{t('map.dateLabel')}</Text>
        <View style={styles.chipRow}>
          {(['all', 'today', 'week'] as const).map((option) => (
            <Pressable
              key={option}
              style={[styles.chip, dateMode === option && styles.chipActive]}
              onPress={() => setDateMode(option)}
            >
              <Text style={[styles.chipText, dateMode === option && styles.chipTextActive]}>
                {t(`map.date.${option}`)}
              </Text>
            </Pressable>
          ))}
          <Pressable
            style={[styles.chip, dateMode === 'date' && styles.chipActive]}
            onPress={() => setShowDatePicker(true)}
          >
            <Text style={[styles.chipText, dateMode === 'date' && styles.chipTextActive]}>
              {dateMode === 'date' && specificDate
                ? dayjs(specificDate).locale(i18n.language).format('D MMM')
                : t('map.date.pickDate')}
            </Text>
          </Pressable>
          <Pressable
            style={[styles.chip, dateMode === 'range' && styles.chipActive]}
            onPress={() => setShowRangeFrom(true)}
          >
            <Text style={[styles.chipText, dateMode === 'range' && styles.chipTextActive]}>
              {dateMode === 'range' && rangeFrom && rangeTo
                ? `${dayjs(rangeFrom).locale(i18n.language).format('D MMM')} → ${dayjs(rangeTo).locale(i18n.language).format('D MMM')}`
                : t('map.date.pickRange')}
            </Text>
          </Pressable>
        </View>

        {showDatePicker && (
          <DateTimePicker value={specificDate ?? new Date()} mode="date" minimumDate={new Date()} onChange={(_e, date) => {
            setShowDatePicker(false);
            if (date) { setSpecificDate(date); setDateMode('date'); }
          }} />
        )}
        {showRangeFrom && (
          <DateTimePicker value={rangeFrom ?? new Date()} mode="date" minimumDate={new Date()} onChange={(_e, date) => {
            setShowRangeFrom(false);
            if (date) { setRangeFrom(date); setRangeTo(dayjs(date).add(7, 'day').toDate()); setShowRangeTo(true); }
          }} />
        )}
        {showRangeTo && (
          <DateTimePicker value={rangeTo ?? dayjs().add(7, 'day').toDate()} mode="date" minimumDate={rangeFrom ?? new Date()} onChange={(_e, date) => {
            setShowRangeTo(false);
            if (date) { setRangeTo(date); setDateMode('range'); }
          }} />
        )}

        {/* Sport */}
        <Text style={styles.filterLabel}>{t('map.sportLabel')}</Text>
        <SportDropdown
          selected={sportFilters}
          onSelect={(key) => setSportFilters((prev) =>
            prev.includes(key) ? prev.filter((k) => k !== key) : [...prev, key]
          )}
          multiSelect
          label={t('map.sportLabel')}
        />
      </View>

      {/* Results */}
      <Text style={styles.resultCount}>
        {filtered.length} {t('search.results')}
      </Text>

      {filtered.length === 0 ? (
        <View style={styles.empty}>
          <Text style={styles.emptyText}>{t('search.noResults')}</Text>
        </View>
      ) : (
        <FlatList
          data={filtered}
          keyExtractor={(item) => item.id}
          renderItem={({ item }) => (
            <View>
              <Text style={styles.distanceLabel}>{item.distance.toFixed(1)} km</Text>
              <ActivityCard
                activity={item}
                onPress={() => router.push(`${routePrefix}/activity/${item.id}`)}
              />
            </View>
          )}
          contentContainerStyle={styles.list}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  filters: { padding: spacing.md, paddingBottom: 0 },
  filterLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, textTransform: 'uppercase', marginBottom: spacing.xs, marginTop: spacing.md },
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs },
  chip: { backgroundColor: colors.surface, borderRadius: radius.full, paddingHorizontal: spacing.sm, paddingVertical: spacing.xs },
  chipActive: { backgroundColor: colors.cta },
  chipText: { color: colors.textSecondary, fontSize: fontSizes.xs },
  chipTextActive: { color: colors.textPrimary, fontWeight: 'bold' },
  resultCount: { color: colors.textSecondary, fontSize: fontSizes.xs, paddingHorizontal: spacing.md, paddingTop: spacing.md },
  list: { padding: spacing.md },
  distanceLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, marginBottom: 2, marginLeft: spacing.xs },
  empty: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  emptyText: { color: colors.textSecondary, fontSize: fontSizes.md },
});
