import { useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import Svg, { Path } from 'react-native-svg';
import { Lock } from 'lucide-react-native';
import { fontSizes, radius } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { getActivityTimeStatus } from '@/utils/activity-status';
import { getSportIcon } from '@/constants/sport-icons';
import { type NearbyActivity } from '@/services/activity-service';

interface ActivityPinProps {
  activity: NearbyActivity;
}

const PIN_SIZE = 44;
const DOT_SIZE = 16;
// Tail geometry: corners sit on the visual middle of the 1.5px border
// so the tail's stroke and the circle's stroke share pixels at the
// junction. Tip extends below.
const BORDER_WIDTH = 1.5;
const ANCHOR_RADIUS = PIN_SIZE / 2 - BORDER_WIDTH / 2;
const TAIL_HALF_WIDTH = 9;
const TAIL_TOP_Y = PIN_SIZE / 2 + Math.sqrt(
  ANCHOR_RADIUS ** 2 - TAIL_HALF_WIDTH ** 2
);
const TAIL_BOTTOM_Y = PIN_SIZE + 6;
const TOTAL_HEIGHT = TAIL_BOTTOM_Y + 2;

// Anchor point for Mapbox MarkerView so the tail's tip sits exactly on
// the geographic coordinate (x centered, y at the tip).
export const ACTIVITY_PIN_ANCHOR = { x: 0.5, y: TAIL_BOTTOM_Y / TOTAL_HEIGHT };

export function ActivityPin({ activity }: ActivityPinProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const joined = activity.participant_count;
  const isFull = joined >= activity.max_participants;
  const dotColor = isFull ? colors.error : colors.success;
  const timeStatus = getActivityTimeStatus(activity.starts_at, activity.status);
  const circleStyle =
    timeStatus === 'in_progress'
      ? styles.circleInProgress
      : timeStatus === 'soon'
        ? styles.circleSoon
        : null;
  const tailFill =
    timeStatus === 'in_progress'
      ? colors.success
      : timeStatus === 'soon'
        ? colors.warning
        : colors.pinBackground;

  return (
    <View style={styles.wrapper}>
      <View style={[styles.circle, circleStyle]}>
        <Text style={styles.icon}>{getSportIcon(activity.sport_key)}</Text>
      </View>
      <Svg width={PIN_SIZE} height={TOTAL_HEIGHT} style={StyleSheet.absoluteFill}>
        <Path
          d={`M ${PIN_SIZE / 2 - TAIL_HALF_WIDTH} ${TAIL_TOP_Y} L ${PIN_SIZE / 2} ${TAIL_BOTTOM_Y} L ${PIN_SIZE / 2 + TAIL_HALF_WIDTH} ${TAIL_TOP_Y}`}
          fill={tailFill}
          stroke={colors.pinBorder}
          strokeWidth={1.5}
          strokeLinejoin="miter"
          strokeLinecap="butt"
        />
      </Svg>
      <View style={[styles.dot, { backgroundColor: dotColor }]}>
        {isFull ? (
          <Lock size={10} color={colors.pinBorder} strokeWidth={3} />
        ) : (
          <Text style={styles.dotText}>{joined}</Text>
        )}
      </View>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  wrapper: {
    width: PIN_SIZE,
    height: TOTAL_HEIGHT,
    overflow: 'visible',
  },
  circle: {
    width: PIN_SIZE,
    height: PIN_SIZE,
    borderRadius: radius.full,
    backgroundColor: colors.pinBackground,
    borderWidth: 1.5,
    borderColor: colors.pinBorder,
    alignItems: 'center',
    justifyContent: 'center',
  },
  circleSoon: {
    backgroundColor: colors.warning,
  },
  circleInProgress: {
    backgroundColor: colors.success,
  },
  icon: {
    fontSize: 18,
  },
  dot: {
    width: DOT_SIZE,
    height: DOT_SIZE,
    borderRadius: DOT_SIZE / 2,
    position: 'absolute',
    top: -(DOT_SIZE / 2) + 6,
    right: -(DOT_SIZE / 2) + 6,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1.5,
    borderColor: colors.pinBorder,
  },
  dotText: {
    color: colors.pinBorder,
    fontSize: fontSizes.xs - 3,
    fontWeight: 'bold',
  },
});
