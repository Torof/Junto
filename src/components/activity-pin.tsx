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
const PILL_WIDTH = 32;
const PILL_HEIGHT = 16;
// viewBox y where the sport emoji is vertically centered (raised inside the head bulb).
const ICON_CENTER_Y_VBX = 24;

// Path from claude_design/pin-junto-template.svg — classic location pin silhouette.
const PIN_PATH = 'M 27 2 C 13 2 4 12 4 25 C 4 38 27 62 27 62 C 27 62 50 38 50 25 C 50 12 41 2 27 2 Z';

// Tip of the pin in viewBox coords is (27, 62); anchor the marker so the tip
// sits exactly on the geographic point.
export const ACTIVITY_PIN_ANCHOR = { x: 0.5, y: 62 / VIEWBOX_H };

// Badge centered on the top of the dome (north) — half inside the head, half outside above.
const BADGE_CX_RATIO = 27 / VIEWBOX_W;
const BADGE_CY_RATIO = 2 / VIEWBOX_H;

export function ActivityPin({ activity }: ActivityPinProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const joined = activity.participant_count;
  const isFull = joined >= activity.max_participants;
  const pillColor = isFull ? colors.error : colors.success;
  const timeStatus = getActivityTimeStatus(activity.starts_at, activity.status);
  const fillColor =
    timeStatus === 'in_progress'
      ? colors.success
      : timeStatus === 'soon'
        ? colors.warning
        : colors.pinBackground;

  const pillLeft = BADGE_CX_RATIO * PIN_WIDTH - PILL_WIDTH / 2;
  const pillTop = BADGE_CY_RATIO * PIN_HEIGHT - PILL_HEIGHT / 2;

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
      <View style={[styles.pill, { backgroundColor: pillColor, left: pillLeft, top: pillTop }]}>
        <Text style={styles.pillText}>{joined}/{activity.max_participants}</Text>
      </View>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
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
  pill: {
    width: PILL_WIDTH,
    height: PILL_HEIGHT,
    borderRadius: PILL_HEIGHT / 2,
    position: 'absolute',
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1.5,
    borderColor: colors.pinBorder,
  },
  pillText: {
    color: '#FFFFFF',
    fontSize: 10,
    fontWeight: '800',
    letterSpacing: 0.2,
  },
});
