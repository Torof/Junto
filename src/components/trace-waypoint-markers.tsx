import { useMemo, useState } from 'react';
import { View, Pressable, StyleSheet } from 'react-native';
import Mapbox from '@rnmapbox/maps';
import { useTranslation } from 'react-i18next';
import { AppText } from '@/components/app-text';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, radius, shadows } from '@/constants/theme';
import type { TraceWaypoint } from '@/services/activity-service';
import { waypointIcon } from '@/utils/trace-waypoints';

// The stops of a trace on a map (00570): a round icon per waypoint; a tap shows
// its name (or its kind) in a bubble, or hands the tap to `onPress` (editor).
export function TraceWaypointMarkers({ waypoints, onPress, onTouch }: {
  waypoints: TraceWaypoint[];
  onPress?: (index: number) => void;
  // Lets the map ignore the press that a marker tap also fires on it.
  onTouch?: () => void;
}) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const [open, setOpen] = useState<number | null>(null);

  return (
    <>
      {waypoints.map((w, i) => {
        const Icon = waypointIcon(w.kind);
        const label = w.name ?? t(`waypoint.kind.${w.kind}`);
        const shown = open === i && !onPress;
        // The bubble sits above the dot in the flow (an absolute child would be
        // clipped by the marker); the anchor keeps the dot's centre on the point.
        return (
          <Mapbox.MarkerView
            key={`wp-${i}-${w.lng}-${w.lat}`}
            id={`wp-${i}`}
            coordinate={[w.lng, w.lat]}
            anchor={{ x: 0.5, y: shown ? (BUBBLE_H + GAP + DOT / 2) / (BUBBLE_H + GAP + DOT) : 0.5 }}
            allowOverlap
          >
            <Pressable
              onPressIn={onTouch}
              onPress={() => (onPress ? onPress(i) : setOpen(open === i ? null : i))}
              hitSlop={10}
              accessibilityRole="button"
              accessibilityLabel={label}
              style={styles.wrap}
            >
              {shown ? (
                <View style={styles.bubble}><AppText style={styles.bubbleText} numberOfLines={1}>{label}</AppText></View>
              ) : null}
              <View style={styles.dot}><Icon size={14} color={colors.mapAction} strokeWidth={2.4} /></View>
            </Pressable>
          </Mapbox.MarkerView>
        );
      })}
    </>
  );
}

const DOT = 26;
const BUBBLE_H = 24;
const GAP = 4;

const createStyles = (colors: AppColors) => StyleSheet.create({
  wrap: { alignItems: 'center', gap: GAP },
  dot: {
    width: DOT, height: DOT, borderRadius: DOT / 2, alignItems: 'center', justifyContent: 'center',
    backgroundColor: colors.pinBackground, borderWidth: 2, borderColor: colors.mapAction, ...shadows.card,
  },
  bubble: {
    height: BUBBLE_H, maxWidth: 180, justifyContent: 'center',
    backgroundColor: colors.surface, borderRadius: radius.md, paddingHorizontal: 8, ...shadows.card,
  },
  bubbleText: { color: colors.textPrimary, fontSize: fontSizes.xs + 1, fontWeight: '700', textAlign: 'center' },
});
