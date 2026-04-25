import { useMemo, useRef } from 'react';
import { View, Text, Pressable, StyleSheet, useWindowDimensions } from 'react-native';
import BottomSheet, { BottomSheetFlatList } from '@gorhom/bottom-sheet';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { ChevronUp } from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { type NearbyActivity } from '@/services/activity-service';
import { ActivityCard } from './activity-card';

interface Props {
  activities: NearbyActivity[];
  userLocation: [number, number];
  onItemPress?: (activity: NearbyActivity) => void;
}

function getDistanceKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function CollapsedDrawerHandle({ count, onExpand, height }: { count: number; onExpand: () => void; height: number }) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  return (
    <Pressable onPress={onExpand} style={[styles.handleWrapper, { height }]}>
      <View style={styles.grip} />
      <View style={styles.titleRow}>
        <Text style={[styles.title, count === 0 && styles.titleMuted]}>
          {t('map.resultsCount', { count })}
        </Text>
        {count > 0 && (
          <View style={styles.chip}>
            <Text style={styles.chipLabel}>{t('map.seeList')}</Text>
            <ChevronUp size={12} color={colors.cta} strokeWidth={2.5} />
          </View>
        )}
      </View>
      <View style={{ flex: 1 }} />
    </Pressable>
  );
}

export function ActivitiesBottomSheet({ activities, userLocation, onItemPress }: Props) {
  const { t } = useTranslation();
  const router = useRouter();
  const sheetRef = useRef<BottomSheet>(null);
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { height: windowHeight } = useWindowDimensions();

  const snapPoints = useMemo(() => ['10%', '50%', '92%'], []);
  // The handle wrapper must fill the collapsed snap height exactly, otherwise
  // the flatlist content shows through underneath. 10% of the window height
  // matches the first snap point.
  const collapsedHeight = Math.round(windowHeight * 0.10);

  const sorted = useMemo(() => {
    return activities
      .map((a) => ({ ...a, distance: getDistanceKm(userLocation[1], userLocation[0], a.lat, a.lng) }))
      .sort((a, b) => a.distance - b.distance);
  }, [activities, userLocation]);

  return (
    <BottomSheet
      ref={sheetRef}
      index={0}
      snapPoints={snapPoints}
      backgroundStyle={styles.sheetBackground}
      handleComponent={() => (
        <CollapsedDrawerHandle
          count={sorted.length}
          onExpand={() => sheetRef.current?.snapToIndex(2)}
          height={collapsedHeight}
        />
      )}
      containerStyle={styles.sheetContainer}
    >
      <BottomSheetFlatList
        data={sorted}
        keyExtractor={(item) => item.id}
        contentContainerStyle={styles.list}
        renderItem={({ item }) => (
          <ActivityCard
            activity={item}
            distanceKm={item.distance}
            onPress={() => {
              if (onItemPress) onItemPress(item);
              router.push(`/(auth)/activity/${item.id}`);
            }}
          />
        )}
        ListEmptyComponent={
          <View style={styles.empty}>
            <Text style={styles.emptyText}>{t('search.noResults')}</Text>
          </View>
        }
      />
    </BottomSheet>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  sheetContainer: { zIndex: 20 },
  sheetBackground: {
    backgroundColor: colors.background,
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    borderTopWidth: 1,
    borderTopColor: colors.line,
  },

  handleWrapper: {
    backgroundColor: colors.background,
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    borderTopWidth: 1,
    borderTopColor: colors.line,
    paddingHorizontal: 18,
    paddingTop: 8,
    paddingBottom: 0,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: -8 },
    shadowOpacity: 0.35,
    shadowRadius: 16,
    elevation: 8,
  },
  grip: {
    width: 48,
    height: 4.5,
    borderRadius: 3,
    backgroundColor: colors.textSecondary,
    opacity: 0.7,
    alignSelf: 'center',
    marginBottom: 8,
  },
  titleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  title: {
    color: colors.textPrimary,
    fontSize: 18,
    fontWeight: '800',
    letterSpacing: -0.4,
  },
  titleMuted: {
    color: colors.textSecondary,
  },
  chip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.line,
    borderRadius: 999,
    paddingHorizontal: 12,
    paddingVertical: 7,
  },
  chipLabel: {
    color: colors.cta,
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 1.1,
    textTransform: 'uppercase',
  },

  list: {
    paddingHorizontal: spacing.md,
    paddingTop: spacing.sm,
    paddingBottom: spacing.xl,
  },
  empty: {
    padding: spacing.xl,
    alignItems: 'center',
  },
  emptyText: {
    color: colors.textSecondary,
    fontSize: fontSizes.md,
  },
});
