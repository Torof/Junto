import { useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import Svg, { Path } from 'react-native-svg';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { getActivityTimeStatus } from '@/utils/activity-status';
import { getSportIcon } from '@/constants/sport-icons';
import { type NearbyActivity } from '@/services/activity-service';

interface ActivityPinProps {
  activity: NearbyActivity;
}

// Render size (preserves the 54x64 design viewBox aspect ratio).
const VIEWBOX_W = 54;
const VIEWBOX_H = 64;
const PIN_WIDTH = 56;
const PIN_HEIGHT = Math.round((PIN_WIDTH * VIEWBOX_H) / VIEWBOX_W);
// viewBox y where the sport emoji is vertically centered (raised inside the head bulb).
const ICON_CENTER_Y_VBX = 24;

// Path from claude_design/pin-junto-template.svg — classic location pin silhouette.
const PIN_PATH = 'M 27 2 C 13 2 4 12 4 25 C 4 38 27 62 27 62 C 27 62 50 38 50 25 C 50 12 41 2 27 2 Z';

// Tip of the pin in viewBox coords is (27, 62); anchor the marker so the tip
// sits exactly on the geographic point.
export const ACTIVITY_PIN_ANCHOR = { x: 0.5, y: 62 / VIEWBOX_H };

export function ActivityPin({ activity }: ActivityPinProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const timeStatus = getActivityTimeStatus(activity.starts_at, activity.status);
  const fillColor =
    timeStatus === 'in_progress'
      ? colors.success
      : timeStatus === 'soon'
        ? '#FBBF24'
        : colors.pinBackground;

  return (
    <View style={styles.wrapper}>
      <Svg width={PIN_WIDTH} height={PIN_HEIGHT} viewBox={`0 0 ${VIEWBOX_W} ${VIEWBOX_H}`}>
        <Path
          d={PIN_PATH}
          fill={fillColor}
          stroke={colors.pinBorder}
          strokeWidth={2}
          strokeOpacity={0.55}
          strokeLinejoin="round"
        />
      </Svg>
      <View style={styles.iconWrap}>
        <Text style={styles.icon}>{getSportIcon(activity.sport_key)}</Text>
      </View>
    </View>
  );
}

const createStyles = (_colors: AppColors) => StyleSheet.create({
  wrapper: {
    width: PIN_WIDTH,
    height: PIN_HEIGHT,
    overflow: 'visible',
    shadowColor: '#0A0F1A',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.45,
    shadowRadius: 4,
    elevation: 6,
  },
  iconWrap: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: PIN_HEIGHT * (1 - 2 * (ICON_CENTER_Y_VBX / VIEWBOX_H)),
    alignItems: 'center',
    justifyContent: 'center',
  },
  icon: {
    fontSize: 16,
  },
});
