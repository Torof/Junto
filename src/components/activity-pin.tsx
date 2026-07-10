import { useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import Svg, { Path, Circle } from 'react-native-svg';
import { Lock } from 'lucide-react-native';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { getActivityTimeStatus } from '@/utils/activity-status';
import { getSportIcon } from '@/constants/sport-icons';
import { type NearbyActivity } from '@/services/activity-service';

interface ActivityPinProps {
  activity: NearbyActivity;
}

// Render size (preserves the 54x64 design viewBox aspect ratio).
// Shrunk from 56 to 40 (~28%) for a less cluttered map — three
// silhouettes at the previous size dominated the visual field.
const VIEWBOX_W = 54;
const VIEWBOX_H = 54;
const PIN_WIDTH = 40;
const PIN_HEIGHT = Math.round((PIN_WIDTH * VIEWBOX_H) / VIEWBOX_W);
// viewBox y where the sport emoji is vertically centered (raised inside the head bulb).
const ICON_CENTER_Y_VBX = 24;

// Location-pin silhouette with a short, softly-pointed bottom (2026-07-01) —
// the tail sits at y≈52 and the lower control points ride just above the tip
// so the bottom reads as a gentle point (a hair less rounded than the fully
// level version), still clearly non-circular (bulb on top, taper below).
const PIN_PATH = 'M 27 2 C 13 2 4 12 4 25 C 4 36 21 50 27 52 C 33 50 50 36 50 25 C 50 12 41 2 27 2 Z';

// Bottom point in viewBox coords is (27, 52); anchor the marker so it sits on
// the geographic point.
export const ACTIVITY_PIN_ANCHOR = { x: 0.5, y: 52 / VIEWBOX_H };

export function ActivityPin({ activity }: ActivityPinProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const timeStatus = getActivityTimeStatus(activity.starts_at, activity.status);
  const fillColor =
    timeStatus === 'in_progress'
      ? colors.success
      : timeStatus === 'soon'
        ? '#FBBF24'
        : colors.pinFrame;

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
        {/* Ivory content plate — completes the universal pin grammar
            (outline → frame → plate → glyph). The status color draws
            the round frame instead of flooding the bulb, so the sport
            emoji always sits on ivory. Default (published) state shows
            a subtle stone frame (pinFrame) to keep the construction
            visible. A thin near-black ring outlines the emoji disc. */}
        <Circle
          cx={27}
          cy={24}
          r={18.5}
          fill={colors.pinBackground}
          stroke={colors.pinBorder}
          strokeWidth={1.5}
          strokeOpacity={0.95}
        />
      </Svg>
      <View style={styles.iconWrap}>
        <Text style={styles.icon}>{getSportIcon(activity.sport_key)}</Text>
      </View>
      {/* Private outing — only its members ever see this pin (view 00315),
          so the padlock reads as "your private outing", not someone's
          secret. Ink badge, top-right of the bulb. */}
      {(activity.visibility === 'private_link' || activity.visibility === 'private_link_approval') && (
        <View style={styles.lockBadge}>
          <Lock size={9} color={colors.pinBackground} strokeWidth={2.8} />
        </View>
      )}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  lockBadge: {
    position: 'absolute',
    top: -2,
    right: -2,
    width: 16,
    height: 16,
    borderRadius: 8,
    backgroundColor: colors.pinBorder,
    borderWidth: 1.5,
    borderColor: colors.pinBackground,
    alignItems: 'center',
    justifyContent: 'center',
  },
  wrapper: {
    width: PIN_WIDTH,
    height: PIN_HEIGHT,
    overflow: 'visible',
    shadowColor: '#0A0F1A',
    shadowOffset: { width: 0, height: 5 },
    shadowOpacity: 0.6,
    shadowRadius: 6,
    elevation: 10,
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
    // Sized to fill the ~27px ivory plate so the sport emoji reads clearly
    // on the map (emoji glyphs can't be colour-saturated, so size is the lever).
    fontSize: 17,
  },
});
